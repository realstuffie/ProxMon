#pragma once

#include <algorithm>

// Counts the PBS requests still in flight across the three tiers a refresh
// walks: one datastore listing per endpoint, one namespace listing per
// datastore, one snapshot listing per namespace.
//
// The invariant this type exists to hold: a tier's completion decrements its
// own counter and adds the requests it spawned in the same call. The total
// therefore never reaches zero while work is still to be issued. A caller that
// decremented first and added the next tier later would let isComplete()
// report true in the gap, and correlation would run against partial results.
//
// Decrements are floored at zero. A reply from a superseded refresh can arrive
// after reset() and must not drive a counter negative, which would strand the
// tally permanently incomplete.
class PbsRequestTally {
public:
    void reset() {
        m_endpoints = 0;
        m_namespaces = 0;
        m_snapshots = 0;
    }

    void addEndpoint() { m_endpoints += 1; }

    // The datastore listing failed, or its secret could not be read.
    void endpointFailed() { decrement(m_endpoints); }

    // The datastore listing returned, spawning one namespace listing each.
    void datastoresReceived(int datastoreCount) {
        decrement(m_endpoints);
        m_namespaces += std::max(0, datastoreCount);
    }

    // The namespace listing returned, spawning one snapshot listing each.
    void namespacesReceived(int namespaceCount) {
        decrement(m_namespaces);
        m_snapshots += std::max(0, namespaceCount);
    }

    // A snapshot listing returned or failed. Spawns nothing.
    void snapshotFinished() { decrement(m_snapshots); }

    bool isComplete() const {
        return m_endpoints == 0 && m_namespaces == 0 && m_snapshots == 0;
    }

    int pendingEndpoints() const { return m_endpoints; }
    int pendingNamespaces() const { return m_namespaces; }
    int pendingSnapshots() const { return m_snapshots; }

private:
    static void decrement(int &counter) {
        if (counter > 0) {
            counter -= 1;
        }
    }

    int m_endpoints = 0;
    int m_namespaces = 0;
    int m_snapshots = 0;
};
