# Architecture

Design decisions that aren't obvious from reading the code alone.

## Credential security model

### Scope and intended lifetimes

ProxMon uses QtKeychain for persistent API token storage and reads secrets on
demand. It does not maintain a client-wide token cache. The intended policy is
to release application-held API secrets and authorization headers when the
operation that needs them ends. Console tickets may remain in owned memory for
the console session and should be released when that session ends.

These are lifetime and exposure goals, not guarantees that every plaintext
copy is erased. The current implementation still uses shared Qt buffers;
exclusive ownership and reliable wiping of application-owned credential
buffers remain implementation work. The cleanup points below describe what
the code currently attempts, not a completed secure-buffer design.

ProxMon runs inside plasmashell and does not provide credential isolation from
unrestricted processes running as the same user, privileged attackers, or
malicious code inside plasmashell. QtKeychain delegates access control to the
system wallet, whose unlocked entries may be accessible to other user
processes. This model does not promise complete erasure from RAM, swap or core
dumps, or control over copies held by the wallet, Qt or TLS libraries.

### Runtime credential flow outside QML

Runtime keyring reads stay entirely in C++. `ProxmoxClient` and `SecretStore`
are internal implementation types and are not registered with the QML engine.
In the normal runtime flow, QML asks `ProxmoxController` to perform an operation
using endpoint identity and operation arguments, without receiving the
resolved API token secret.

`SecretStore` attaches completion callbacks to each individual QtKeychain job.
This preserves the relationship between an endpoint lookup and its result even
when several endpoint reads complete out of order. There is no shared
secret-bearing Qt signal that QML can observe, and no client-wide cached token
secret. Single-host child enumeration performs a fresh scoped keyring read,
matching the multi-host request flow.

The configuration password fields remain a deliberate exception. A secret
typed by the user passes through the KCM's QML text field and configuration
handoff before storage in the keyring. Clearing the field and handoff removes
their logical values but does not guarantee erasure of backing memory.

### Why runtime credentials are not Q_PROPERTYs

Exposing a readable credential property on a QML object lets JavaScript obtain
the value and create additional copies. The QML/JavaScript engine does not
guarantee that those copies are erased when the operation ends.

To avoid that exposure in the normal console flow, the transport types do not
expose the auth header or ticket as Q_PROPERTYs. C++ delivers them through:

- `setAuthHeaderSecure(const QByteArray &)`, called by `ProxmoxController::deliverConsoleAuth()`
- `setTicketSecure(const QByteArray &)`, called by `ProxmoxController::deliverConsoleTicket()`

These methods are `Q_INVOKABLE` and the controller calls them through
`QMetaObject::invokeMethod` with `Qt::DirectConnection`. The transport types
provide no credential getters. The `Secure` suffix describes the intended
handoff, not a memory-erasure guarantee or a boundary against malicious code
inside plasmashell.

### The pending registry pattern

`ProxmoxController` maintains two maps keyed by a unique console request ID:

```cpp
QHash<QString, QByteArray> m_pendingConsoleAuth
QMap<QString, QByteArray>  m_pendingConsoleTicket
```

When a proxy-ready signal arrives from `ProxmoxClient`, the controller stashes both credentials under that request ID and emits `consoleReady` / `lxcConsoleReady` without the credentials in the signal arguments. In the normal console flow, QML passes the non-secret request ID back to `deliverConsoleAuth` / `deliverConsoleTicket`, which push credentials directly into the C++ transport targets. Request IDs prevent simultaneous consoles on one endpoint from consuming each other's handoff state; they are not an authorization mechanism.

Each map entry is consumed exactly once. `deliverConsoleTicket` accepts a primary and optional secondary target so both `VncWsProxy` and `VncClient` can be fed from a single atomic consume.

### Current cleanup and its limits

Qt credential holders generally call `fill(0)` before clearing a value or
removing it from a map. `clear()` alone releases the reference without wiping
the allocation. With an exclusively owned `QByteArray`, `fill(0)` writes zeros
to that buffer. With a shared buffer, it detaches and zeroes a separate
allocation, leaving the original bytes in the other owners' buffer.

Current console cleanup points:

| Holder                      | What          | Cleanup attempted at                                                  |
|-----------------------------|---------------|-----------------------------------------------------------------------|
| `VncWsProxy::m_ticket`      | VNC ticket    | `onWsConnected`, HTTP upgrade complete, ticket already in WS URL     |
| `VncWsProxy::m_authHeader`  | Auth header   | `onWsConnected`, same point                                          |
| `VncClient::m_ticket`       | VNC ticket    | Immediately after `strdup` into libvncclient client-data slot 1       |
| libvncclient slot 1         | C-string copy | Worker thread, after `rfbInitClient` handshake completes              |
| `LxcTerminal::m_ticket`     | Ticket        | Immediately after `sendTextMessage` of the `user:ticket\n` auth line  |
| `LxcTerminal::m_authHeader` | Auth header   | WS `connected` lambda, HTTP upgrade complete                         |
| `ProxmoxController` maps    | Both          | `deliver*`: `fill(0)` in-map, erase, then `fill(0)` on local copy    |

In the controller's `deliver*` methods, the local variable initially shares
the map entry's buffer. Wiping the map value detaches it. The target setters
then share the local variable's original buffer, so its final `fill(0)` also
detaches. The controller drops its references but does not erase the bytes
retained by those targets. The same ownership issue applies to setters and
`clearCredentials()` whenever another owner still shares the buffer.

Replacing `fill(0)` with `explicit_bzero(array.data(), array.size())` is not a
fix for shared ownership: non-const `QByteArray::data()` also detaches. Reliable
wiping requires exclusive ownership of the allocation being erased and a
wipe operation that cannot be optimized away. It does not erase separate
copies made earlier.

The C-string stored in libvncclient slot 1 is a separate allocation. Its
cleanup explicitly calls `explicit_bzero` before `free`, but this only covers
that allocation, not additional copies made by libvncclient.

API polling also places authorization headers into `QNetworkRequest` objects.
Replies retain their requests, and `QWebSocket` retains its opening request,
including its headers and ticket-bearing URL, after the handshake. Clearing
ProxMon's own fields does not clear those retained requests. Serialization,
string conversions and TLS processing can introduce further copies outside
the application's wipe control. Releasing a request or socket is not a
guarantee that its former allocations have been overwritten.

## VNC console architecture

### Why a WebSocket-to-TCP bridge (VncWsProxy)

Proxmox only exposes VNC sessions through a WebSocket endpoint (`/api2/json/nodes/{node}/{kind}/{vmid}/vncwebsocket`). libvncclient speaks raw TCP. `VncWsProxy` bridges the two: it binds a random local TCP port, accepts libvncclient's connection, and forwards bytes bidirectionally over a WebSocket to Proxmox. libvncclient is unaware of the proxy.

### Why VncClient runs on a worker thread

`rfbInitClient()` and `HandleRFBServerMessage()` both block on socket I/O. Running them on the main thread would deadlock Qt's event loop, and `VncWsProxy` depends on that event loop to deliver WebSocket frames. The entire RFB session therefore runs on a `QThread`. All Qt-facing work is marshalled back via `QueuedConnection`.

Concurrent socket writes from the main thread (key/pointer/resize events via `SendKeyEvent` / `SendPointerEvent` / `WriteToRFBServer`) are safe alongside the worker thread's reads at the kernel level, since the RFB protocol is client-request/server-response on separate directions.

### Frame coalescing

libvncclient's `GotFrameBufferUpdate` callback fires once per dirty rect per `HandleRFBServerMessage` call, which can be many times per server message. Rather than emitting a signal per rect (expensive cross-thread marshalling + N repaints), the callback only sets an atomic dirty flag. The poll loop checks the flag once after `HandleRFBServerMessage` returns and emits a single `frameUpdated` signal per message.

### Remote resize (dropped in v0.7.3)

An earlier version implemented client-driven `SetDesktopSize` resize, hand-crafting the wire frame because libvncclient ≤ 0.9.15 truncates the SCREEN array in its helper (LibVNC issue #640). It was removed: behaviour across QEMU/Proxmox versions was inconsistent, and a fixed framebuffer with server-driven desktop-resize support (the `MallocFrameBuffer` realloc callback in `VncClient`) proved the better trade. The view letterboxes to fit instead.

### TLS trust on the console path

The WSS handshake validates the server certificate against the same configured CA as the API path. The controller resolves the cert per session (controller-wide in single-host; shared vs per-endpoint in multi-host, already resolved in `readNextMultiSecret`) and forwards it on `consoleReady` / `lxcConsoleReady`; `VncWsProxy` and `LxcTerminal` append it to their `QSslConfiguration` before `open()`. `ignoreSsl` (`VerifyNone`) takes precedence when enabled. Certificate material is public, so passing it through these signals is compatible with the credential-isolation model. It is not delivered via the pending registry.

## LXC terminal architecture

### Why LxcTerminal owns its own QMainWindow

`QTermWidget` is a `QWidget`. QWidgets cannot be embedded into a QML scene, because Qt's QML renderer and the widget stack use separate paint surfaces. The alternatives considered were:

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

`QTermWidget` exposes `sendText(QString)` publicly, but this echoes input. It is intended for injecting keystrokes, not received server data. The correct path is `write(getPtySlaveFd(), data, size)`, which writes directly to the PTY slave file descriptor. The kernel delivers the bytes to QTermWidget's PTY master side, which feeds the emulation layer without echo. This is the approach documented in QTermWidget's RemoteTerm example.

`sendText` is kept as a fallback for the case where `getPtySlaveFd()` returns -1 (layout not yet settled), but in practice the fd is always valid after `startTerminalTeletype()`.

### Copy/paste and keyboard bindings

`setKeyBindings("linux")` enables Ctrl+Shift+C / Ctrl+Shift+V for clipboard copy/paste.

Right-click context menu (Copy/Paste) is implemented via an event filter installed on `QTermWidget` and all its internal child widgets. Mouse and context events land on QTermWidget's internal `TerminalDisplay` child rather than on the `QTermWidget` itself, so the filter must cover the full child tree (`findChildren<QWidget*>()`) to intercept them reliably.

### Resize strategy

Resize has two legs:

1. **Local PTY.** `ioctl(fd, TIOCSWINSZ, &ws)` on the PTY slave fd updates the kernel's idea of the terminal size so local signals and `ioctl(TIOCGWINSZ)` calls inside the container see the correct dimensions.
2. **Remote side.** A `1:cols:rows:` WebSocket frame tells Proxmox's termproxy to send `SIGWINCH` to the shell process.

Both legs fire together in `sendCurrentResize`. A `QResizeEvent` on the `QTermWidget` triggers a two-pass send (0 ms + 150 ms) to catch cases where the grid count hasn't settled on the first fire.

Sending the same size twice produces no `SIGWINCH`. To force a real delta on first connect, the fallback size is 81×25 (not the standard 80×24), ensuring the first resize frame always differs from the default pty allocation:

1. Send immediately after auth-OK (or 81×25 if grid not yet available).
2. Re-send 120 ms later with the actual post-layout grid.
3. At 500 ms, if fewer than 24 bytes of terminal output have arrived, send a wake CR (`0:1:\r`) to nudge containers with a silent getty.

## ProxmoxController

### Session key model

In single-host mode the session key is an empty string. In multi-host mode it identifies which endpoint the request belongs to. All multi-endpoint state is keyed by session key: the pending console maps, endpoint resolution, error routing. This lets a single controller instance manage parallel sessions against different Proxmox nodes without coupling.

### Pending console name stash

`ProxmoxClient` returns `vmName` via the node children response, but the `vncProxyReady` / `ttyProxyReady` signals don't carry it (they're issued later, from a different request). `m_pendingConsoleNames` bridges the gap. It's keyed by the same unique request ID, populated in `readSingleSecretFor` / `readMultiSecretFor` when the console request is dispatched, and drained in the proxy-ready lambdas.

## Multi-host vs single-host

The two modes share the same `ProxmoxClient` and signal paths. The only runtime difference is:

- **Single**: session key is `""`, endpoint config comes from controller-level properties (`m_host`, `m_port`, etc.).
- **Multi**: session key is a stable string identifying the endpoint, config is resolved via `endpointBySession()` from `m_endpoints`.

`ProxmoxController` resolves per-session overrides (api port, ignoreSsl, trusted CA) in the proxy-ready lambdas before emitting the console-ready signal, so callers downstream don't need to know which mode is active.
