"""JOVRA Studio reference implementation (standard library only).

core      exact rounding, time <-> frame, integer pct, canonical JSON hashing, typed rejections, fixture patches
edl       jovra.edit-plan/2 validator and the clean-alternate derivation
syncfit   speed of sound, sound-travel delays, the piecewise sync-map fitter and its review-state rules
jobstate  RenderJob transition checker and history replay
ledger    quote credits, quote acceptance and the idempotent reservation ledger
records   semantic rules for the other Studio records

generate_fixtures.py (beside this package) writes spec/studio/fixtures deterministically;
scripts/spec/validate_studio.py checks every fixture against its schema and re-runs this reference.
"""
