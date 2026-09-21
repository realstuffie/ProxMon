// Decides whether a queued config-change refresh still has work to do.
//
// A config change cancels the refresh in progress and arms a debounce timer, so
// a burst of edits costs one refresh instead of one per keystroke. The
// controller reads its host, token and storage settings from bindings that
// update as soon as the config does, so a refresh that starts after the timer
// was armed already carries the new config. Firing the queued one would cancel
// that refresh's in-flight requests and redial them for nothing.
//
// The case this covers is the periodic refresh tick, which calls fetchData()
// with no guard of its own. An edit landing inside the debounce window lets the
// tick start a refresh that already has the change, and the timer would then
// throw that refresh away. A refresh that started before the arming predates
// the change and does need replacing.
//
// The widget's own startup no longer reaches here: main.qml ignores the initial
// binding pass outright, so nothing arms the timer then.
//
// Times are epoch milliseconds from Date.now(). Zero means never, the state
// before the first arming or the first refresh, and a refresh at the same
// millisecond as the arming counts as too early to carry the change.
export function shouldSkipConfigRefresh(lastRefreshStartedAt, configRefreshArmedAt) {
    return Number(lastRefreshStartedAt) > Number(configRefreshArmedAt)
}
