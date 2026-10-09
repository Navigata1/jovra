# Zero-stroke error safety reconciliation

Schema-valid forcedError/unforcedError with strokeCount=0 previously derived rallyLength=-1, violating engine-output's nonnegative constraint. Keep the raw observation and point winner, retain outcomeInconsistent, and derive null (unknown) length. An explicitly recorded rallyLength remains authoritative; this change applies only to the computed value.

Public Python test was red for both end types before the shared fix. New S65/S66 fixtures use 18 hand-derived fold/stat assertions: raw0 preserved, winnerB preserved, conflict retained, score0–1, unknown rally bucket1 and0–4 bucket0, total shots0. Generated full outputs are written only after these assertions pass. All previous 103 scoring fixtures and all other prior fixture/contract files remain byte-identical; full reference and98 Python tests pass. The equivalent native guard is included in the subsequent bounded scorer port; this prerequisite does not close T04.
