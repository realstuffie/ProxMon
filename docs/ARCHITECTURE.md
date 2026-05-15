# Architecture

Design decisions that aren't obvious from reading the code alone.

---

## Credential security model

### Why credentials are never Q_PROPERTYs

Qt's property system makes any value set through it visible to the QML/JavaScript V4 engine. The V4 heap is garbage-collected and makes no guarantees about when (or whether) memory is zeroed — a credential written to a Q_PROPERTY can persist as a JS string long after the call site considers it done. Strings in V4 are also reference-counted and may be interned, producing additional copies at unpredictable points.

To prevent this, the auth header and VNC ticket are never exposed as Q_PROPERTYs. They are delivered directly from C++ via:

- `setAuthHeaderSecure(QByteArray)` — called by `ProxmoxController::deliverConsoleAuth()`
- `setTicketSecure(QByteArray)` — called by `ProxmoxController::deliverConsoleTicket()`

Both are `Q_INVOKABLE` only so they can be invoked via `QMetaObject::invokeMethod` with `Qt::DirectConnection`. QML can call them but cannot read them back — there is no getter.

### The pending registry pattern

`ProxmoxController` maintains two maps keyed by `sessionKey`:

```
QHash<QString, QByteArray> m_pendingConsoleAuth
QMap<QString, QByteArray>  m_pendingConsoleTicket
```

When a proxy-ready signal arrives from `ProxmoxClient`, the controller stashes both credentials into these maps and emits `consoleReady` / `lxcConsoleReady` without the credentials in the signal arguments. QML handles the signal, creates the console object, then calls `deliverConsoleAuth` / `deliverConsoleTicket` to push credentials directly into C++ targets — they never appear in the signal args or in any JS variable.

Each map entry is consumed exactly once. `deliverConsoleTicket` accepts a primary and optional secondary target so both `VncWsProxy` and `VncClient` can be fed from a single atomic consume.

### Burn discipline

All burns follow `fill(0)` then `clear()` — in that order. `clear()` alone drops the reference without zeroing the backing buffer. `fill(0)` zeroes before dropping. This is consistent across all credential holders.

Burn points:

| Holder                       | What          | When                                                                    |
|------------------------------|---------------|-------------------------------------------------------------------------|
| `VncWsProxy::m_ticket`       | VNC ticket    | `onWsConnected` — HTTP upgrade complete, ticket already in WS URL       |
| `VncWsProxy::m_authHeader`   | Auth header   | `onWsConnected` — same point                                            |
| `VncClient::m_ticket`        | VNC ticket    | Immediately after `strdup` into libvncclient client-data slot 1         |
| libvncclient slot 1          | C-string copy | Worker thread, after `rfbInitClient` handshake completes                |
| `LxcTerminal::m_ticket`      | Ticket        | Immediately after `sendTextMessage` of the `user:ticket\n` auth line   |
| `LxcTerminal::m_authHeader`  | Auth header   | WS `connected` lambda — HTTP upgrade complete                           |
| `ProxmoxController` maps     | Both          | `deliver*` — `fill(0)` in-map, erase, then `fill(0)` on local copy     |

Note on Qt CoW: `QByteArray` uses implicit sharing. `it.value().fill(0)` in the deliver methods detaches the map's copy into a new zeroed block, leaving the local variable holding the real data. The local variable's final `fill(0)` then zeroes that. This is intentional — targets receive the real bytes; map and local copies are zeroed.

---

## VNC console architecture

### Why a WebSocket-to-TCP bridge (VncWsProxy)

Proxmox only exposes VNC sessions through a WebSocket endpoint (`/api2/json/nodes/{node}/{kind}/{vmid}/vncwebsocket`). libvncclient speaks raw TCP. `VncWsProxy` bridges the two: it binds a random local TCP port, accepts libvncclient's connection, and forwards bytes bidirectionally over a WebSocket to Proxmox. libvncclient is unaware of the proxy.

### Why VncClient runs on a worker thread

`rfbInitClient()` and `HandleRFBServerMessage()` both block on socket I/O. Running them on the main thread would deadlock Qt's event loop — `VncWsProxy` depends on the event loop to deliver WebSocket frames. The entire RFB session therefore runs on a `QThread`. All Qt-facing work is marshalled back via `QueuedConnection`.

Concurrent socket writes from the main thread (key/pointer/resize events via `SendKeyEvent` / `SendPointerEvent` / `WriteToRFBServer`) are safe alongside the worker thread's reads at the kernel level — the RFB protocol is client-request/server-response on separate directions.

### Frame coalescing

libvncclient's `GotFrameBufferUpdate` callback fires once per dirty rect per `HandleRFBServerMessage` call, which can be many times per server message. Rather than emitting a signal per rect (expensive cross-thread marshalling + N repaints), the callback only sets an atomic dirty flag. The poll loop checks the flag once after `HandleRFBServerMessage` returns and emits a single `frameUpdated` signal per message.

### SetDesktopSize (resize) workaround

libvncclient ≤ 0.9.15 truncates the SCREEN array in its `SendExtDesktopSize` implementation (LibVNC issue #640), causing QEMU to silently reject resize requests. `VncClient::resizeRemote` hand-crafts the `SetDesktopSize` (251) wire frame directly rather than using libvncclient's helper.

---

## LXC terminal architecture

### Why LxcTerminal owns its own QMainWindow

`QTermWidget` is a `QWidget`. QWidgets cannot be embedded into a QML scene — Qt's QML renderer and the widget stack use separate paint surfaces. The alternatives considered were:

- **Render to offscreen surface, blit into QML**: high complexity, poor performance for terminal use.
- **X11 window embedding (XEmbed)**: not portable to Wayland.
- **Own top-level window**: simple and reliable. `LxcTerminal` creates a `QMainWindow` with a `QTermWidget` child, shows it as a separate native window, and QML interacts only via `Q_INVOKABLE` methods and signals.

### Proxmox terminal protocol

The LXC terminal uses the same `vncwebsocket` endpoint as VNC but speaks a different protocol:

1. Connect via WebSocket with the ticket in the URL query string and the auth header.
2. On connect: send `user:ticket\n` as a text frame.
3. Server replies `OK` (with optional trailing `\n`).
4. Bidirectional terminal traffic:
   - Server → client: raw text/binary frames → `QTermWidget`
   - Client → server: `0:LEN:DATA` frames
   - Resize: `1:cols:rows:` frames

### Receiving data into QTermWidget

`QTermWidget` exposes `sendText(QString)` publicly, but this echoes input — it's intended for injecting keystrokes, not received server data. The correct injection point is `Konsole::Session::onReceiveBlock(const char*, int)` (or equivalent depending on qtermwidget version), which feeds the emulation layer directly. `LxcTerminal` locates the `Konsole::Session` child via `findChildren` and resolves the slot name once at window creation, then invokes it by name for each received frame.

### Initial resize strategy

Proxmox's pty size is set by `TIOCSWINSZ` when the terminal reports its grid dimensions. Sending the same size twice (e.g. the compiled-in 80×24 default) produces no `SIGWINCH` and the shell never redraws. To force a real delta:

1. Send immediately after auth-OK with whatever `QTermWidget` reports (or 81×25 if layout hasn't settled — deliberately non-default).
2. Re-send 120 ms later with the actual post-layout grid.
3. At 500 ms, if fewer than 24 bytes of terminal output have arrived, send a wake CR (`0:1:\r`) to nudge containers with a silent getty.

---

## ProxmoxController

### Session key model

In single-host mode the session key is an empty string. In multi-host mode it identifies which endpoint the request belongs to. All multi-endpoint state is keyed by session key — the pending console maps, endpoint resolution, error routing. This lets a single controller instance manage parallel sessions against different Proxmox nodes without coupling.

### Pending console name stash

`ProxmoxClient` returns `vmName` via the node children response, but the `vncProxyReady` / `ttyProxyReady` signals don't carry it (they're issued later, from a different request). `m_pendingConsoleNames` bridges the gap — populated in `readSingleSecretFor` / `readMultiSecretFor` when the console request is dispatched, drained in the proxy-ready lambdas.

---

## Multi-host vs single-host

The two modes share the same `ProxmoxClient` and signal paths. The only runtime difference is:

- **Single**: session key is `""`, endpoint config comes from controller-level properties (`m_host`, `m_port`, etc.).
- **Multi**: session key is a stable string identifying the endpoint, config is resolved via `endpointBySession()` from `m_endpoints`.

`ProxmoxController` resolves per-session overrides (api port, ignoreSsl) in the proxy-ready lambdas before emitting the console-ready signal, so callers downstream don't need to know which mode is active.
