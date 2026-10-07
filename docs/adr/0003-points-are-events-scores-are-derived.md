# Points are events; scoreboards and stats are always derived

A match is stored as an ordered list of **point events** (server, outcome, how it ended, timestamps, shots), never as
stored scores. Every scoreboard state, set score, stat and export is computed by replaying the events through the
scoring state machine. Each point keeps the automatic suggestion (`detected`) separately from the user's decision
(`reviewed`); the effective outcome is the reviewed one when present. Correcting point 12 therefore re-derives points
13…N, every summary and every burned-in export overlay with no special-case cascade code, and the original model
output survives for benchmarking.
