#!/usr/bin/env python3
"""Executable examples only: no native transport, scoring engine or camera access."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
FIXTURE = ROOT / 'design-reference/adaptive/brief/watch-snapshot.sample.json'

def freshness(age_at_bridge_ms, since_receive_ms, bounded, baseline_valid):
    if not bounded or not baseline_valid:
        return 'Unknown'
    age = age_at_bridge_ms + since_receive_ms
    if age < 0:
        raise ValueError('Negative age is invalid')
    return 'Fresh' if age <= 5000 else 'Delayed' if age <= 15000 else 'Unknown'

def accept_snapshot(expected_session, expected_epoch, previous_seq, envelope):
    return (envelope['sessionId'] == expected_session
            and envelope['hostEpoch'] == expected_epoch
            and envelope['snapshotSeq'] > previous_seq)

class SampleCommandLedger:
    def __init__(self):
        self.revision = 42
        self.receipts = {}
        self.applied = []

    def submit(self, command):
        key = command['commandId']
        fingerprint = json.dumps(command, sort_keys=True)
        if key in self.receipts:
            old_fingerprint, old_receipt = self.receipts[key]
            return old_receipt if fingerprint == old_fingerprint else 'RejectedIdReuse'
        if command['role'] != 'scorer':
            result = 'Rejected'
        elif command['baseEventRevision'] != self.revision:
            result = 'Conflicted'
        else:
            self.revision += 1
            self.applied.append(key)
            result = 'Accepted'
        self.receipts[key] = (fingerprint, result)
        return result

def main():
    snapshot = json.loads(FIXTURE.read_text())
    assert snapshot['sample'] is True
    assert len(snapshot['devices']) == 6
    assert accept_snapshot('sample-jon-alex', 3, 7, snapshot)
    assert not accept_snapshot('wrong-room', 3, 7, snapshot)
    assert not accept_snapshot('sample-jon-alex', 4, 7, snapshot)
    assert not accept_snapshot('sample-jon-alex', 3, 8, snapshot)
    rows = [(d, freshness(d['ageAtBridgeMs'], 0, True, True)) for d in snapshot['devices']]
    fresh_recording = sum(d['captureState'] == 'Recording' and state == 'Fresh' for d, state in rows)
    assert fresh_recording == 5
    assert dict((d['deviceId'], state) for d, state in rows)['c3'] == 'Unknown'
    assert freshness(2000, 4000, True, True) == 'Delayed'
    assert freshness(2000, 14000, True, True) == 'Unknown'
    assert freshness(0, 0, False, True) == 'Unknown'  # queued transit unbounded
    assert freshness(0, 0, True, False) == 'Unknown'  # process monotonic baseline lost
    assert freshness(5000, 0, True, True) == 'Fresh'
    assert freshness(15000, 0, True, True) == 'Delayed'
    try:
        freshness(-1, 0, True, True)
        raise AssertionError('Negative age accepted')
    except ValueError:
        pass
    last_elapsed = snapshot['devices'][2]['lastReportedElapsedMs']
    assert last_elapsed == 746000  # frozen 12:26, never extrapolated to 12:34
    command = {'commandId': 'sample-point-43', 'role': 'scorer', 'baseEventRevision': 42, 'pointWinner': 'jon'}
    ledger = SampleCommandLedger()
    assert ledger.submit(command) == 'Accepted'
    assert ledger.submit(command) == 'Accepted'
    assert len(ledger.applied) == 1 and ledger.revision == 43
    assert ledger.submit({**command, 'pointWinner': 'alex'}) == 'RejectedIdReuse'
    assert ledger.submit({**command, 'commandId': 'other-point'}) == 'Conflicted'
    assert ledger.submit({**command, 'commandId': 'viewer-point', 'role': 'viewer', 'baseEventRevision': 43}) == 'Rejected'
    result = {'sampleFreshRecordingCount': fresh_recording, 'enrolled': 6,
              'fixturesPassed': True, 'nativeTransportTested': False,
              'productionAuthenticationTested': False, 'physicalCaptureTested': False}
    print(json.dumps(result, indent=2))

if __name__ == '__main__':
    main()
