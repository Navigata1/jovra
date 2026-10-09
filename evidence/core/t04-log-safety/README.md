# Cyclic future correction anchor safety

A schema-valid event shape can insert before a future correction whose supersede chain cycles between two future events. The original public scoring fold followed that chain forever. A bounded subprocess control reproduced the timeout before the fix.

Track visited anchor IDs while following unplaced supersede links; stop on repetition. A cycle has no earlier placed anchor, so the existing `insertTargetMissing` refusal applies. No new error code, point interpretation or correction semantics are introduced. E18 independently specifies this refusal and the public subprocess test must finish within two seconds.

After reconciling current main's rally fix, the full reference validator passes 106 scoring fixtures and all 99 Python test methods pass. All 152 previous fixture/contract files remain byte-identical. Native port adds the matching traversal guard and separately refuses negative checkpoint indices before any array lookup. This prerequisite does not close T04.
