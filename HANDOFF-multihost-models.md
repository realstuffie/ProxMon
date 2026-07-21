# Handoff: convert multi-host to the diffing model

## Goal
Multi-host currently rebuilds all delegates every poll (plain nested-array
Repeaters). Port it to the same `VariantListModel` diffing approach already
live on single-host, so rows update in place. This is the case where the win
is biggest: more hosts x more nodes x more rows, polled across several
endpoints.

## What already landed (single-host, do not redo)
- `VariantListModel` (contents/lib/variantlistmodel.{h,cpp}): keyed diffing
  QAbstractListModel over QVariantMap rows. First-wins dedupe on duplicate
  keys is built in. Roles: single `itemData` role; exposes `count` and
  `runningCount`.
- Controller owns `m_nodesModel` plus per-node `m_vmModelsByNode` /
  `m_lxcModelsByNode`, published by `publishSingleHostModels()` from
  `correlateBackups()`.
- Sorting moved to C++: `ProxmoxDataUtils::sortItems(list, mode)`, driven by
  the `defaultSorting` property. Mirrors the old QML `sortByStatus()`.
- Visibility gate: `viewActive` property (bound to `root.expanded` in
  main.qml). `publishSingleHostModels()` no-ops while collapsed; a catch-up
  publish runs on expand via `setViewActive()`. Carry this pattern over.

## Current multi-host state (what still uses the old path)
- Delegates render the nested endpoint lists in `m_displayedEndpoints`, not
  the models. `correlateBackups()` keeps both representations correlated.
- QML still calls `getVmsForNodeMulti` / `getLxcForNodeMulti` (JS sort + JS
  dedupe) and the `*Multi` count helpers.
- `publishSingleHostModels()` bails unless `connectionMode == "single"`.

## The conversion

### Keys
Single-host keys on `node` (nodes) and `node`+`vmid` (children). Multi-host
must disambiguate across endpoints:
- endpoints model: key on `sessionKey`
- nodes model (per endpoint): key on `sessionKey`+`node`
- vm/lxc submodels (per node): key on `sessionKey`+`node`+`vmid`

If the product intent is to dedupe the same guest seen through two hosts,
drop `sessionKey` from the child key so first-wins collapses them (this is
what `getVmsForNodeMulti` does in JS today). Decide which; it changes the key
fields only, not the algorithm.

### Structure
Mirror the single-host shape one level deeper:
- `m_endpointsModel` (VariantListModel, key `sessionKey`)
- per endpoint: a nodes submodel, stored in a
  `QHash<QString /*sessionKey*/, VariantListModel*>`
- per (endpoint,node): vm/lxc submodels, keyed by `sessionKey`+`node`
- each endpoint row carries a `nodesModel` pointer; each node row carries
  `vmsModel` / `lxcsModel` pointers (same stable-pointer trick, so unchanged
  rows compare equal)

### Publish function
Add `publishMultiHostModels()` parallel to the single-host one:
- guard `if (!m_viewActive || m_connectionMode != "multiHost") return;`
- walk `m_displayedEndpoints`; group + `sortItems()` each node's children in
  C++; `applyItems()` into the submodels
- reap vanished endpoints/nodes (deleteLater + erase), same as single-host
- call it from `correlateBackups()` alongside `publishSingleHostModels()`
  (each no-ops in the wrong mode)
- clear from `clearSingleHostModels()`'s sibling on mode change

### QML
- swap the multi-host Repeater(s) to bind the endpoint/node models and read
  `itemData` instead of `modelData`
- per-node counts come from `submodel.runningCount` / `submodel.count`, same
  as NodeSection already does on single-host

## Cleanup once converted
- delete `getVmsForNode` / `getLxcForNode` and the per-node count helpers in
  main.qml (already dead on single-host, kept only for the multi path)
- delete `getVmsForNodeMulti` / `getLxcForNodeMulti` and `*Multi` counts
- remove the `onDefaultSortingChanged` refetch trigger in main.qml: the model
  re-sorts via diff (row moves) without a network round-trip. Confirm nothing
  else depends on that refetch first.

## Tests
Extend tst_variantlistmodel (or add a controller-level test) for:
- cross-host dedupe with the chosen key (first-wins vs. keep-both)
- a reorder that moves a row down, and a combined move+dataChanged in one
  apply (single-host tests only cover move-up today)

## Verify
- `cmake -B build-tests -S contents/lib -DPROXMON_BUILD_TESTS=ON && \
   cmake --build build-tests && ctest --test-dir build-tests`
- visual: expand multi-host popup, confirm rows populate on first open,
  no flashing on refresh, scroll position survives a poll; collapse and
  confirm the panel badge still updates (flat lists feed it, not the models)

## Notes / gotchas
- Row equality relies on the submodel QObject* pointers staying stable across
  refreshes. Reuse from the hash; never rebuild per poll.
- Keep the flat `displayedVmData` / `displayedLxcData` as-is: notifications,
  tooltip, footer, and the collapsed badge read them, not the models.
- O(n^2) diff is fine at realistic guest counts; don't "optimize" it into a
  hash-reconcile unless a profiler says so.
