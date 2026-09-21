import QtTest
import QtQuick

// Exercises the shipped config-refresh debounce rule through the real QML JS
// engine (run via qmltestrunner, registered as the "refreshdebounce" CTest
// test). See refreshdebounce.mjs for why the rule exists.
import "../../ui/components/refreshdebounce.mjs" as RD

TestCase {
    name: "RefreshDebounce"

    // An edit arms the timer, then the periodic refresh tick fires inside the
    // 600ms window and starts a refresh that already carries the edit. The
    // queued one is redundant and would only cancel and redial that refresh.
    function test_refreshTickInsideDebounceWindowIsRedundant() {
        var armedByEdit = 42172
        var startedByPeriodicTick = 42690
        verify(RD.shouldSkipConfigRefresh(startedByPeriodicTick, armedByEdit))
    }

    // A real edit arms the timer after the running refresh began, so that
    // refresh predates the change and the queued one has to go ahead.
    function test_editDuringRefreshStillRefreshes() {
        var startedEarlier = 1000
        var armedByEdit = 1400
        verify(!RD.shouldSkipConfigRefresh(startedEarlier, armedByEdit))
    }

    // Before the first refresh of a session there is nothing in flight to
    // inherit the config, so the queued refresh is the only one that will run.
    function test_firstEverRefreshIsNotSkipped() {
        verify(!RD.shouldSkipConfigRefresh(0, 5000))
    }

    // Both unset: no refresh has run, so the queued one still has work.
    function test_coldStateIsNotSkipped() {
        verify(!RD.shouldSkipConfigRefresh(0, 0))
    }

    // Same millisecond is too close to call, and skipping a refresh that may
    // predate the change is the worse error: it leaves stale config on screen
    // until the next interval, where a redundant refresh only costs a round
    // trip. Ties go to refreshing.
    function test_sameMillisecondRefreshes() {
        verify(!RD.shouldSkipConfigRefresh(7000, 7000))
    }

    // Guards against a string slipping in from a QML property and turning the
    // comparison into a lexicographic one, where "900" > "1000".
    function test_numericComparisonNotLexicographic() {
        verify(!RD.shouldSkipConfigRefresh("900", "1000"))
        verify(RD.shouldSkipConfigRefresh("1000", "900"))
    }
}
