"""The synthetic multi-angle generator (S58, multicam-sync research 8.1).

A scene (the first two minutes of T11's Jon vs Alex sample play: racket contacts and bounces at known light times and
court positions) is recorded by a rig of up to six phones at the club-fence placements. Each camera has its own clock
(offset, drift, restarts with or without a capture journal, a late start), frame rate (CFR at 24-240 fps or VFR),
orientation (rotated), colour (HLG-tagged 10-bit HEVC), view (a knocked-tripod shake stretch, or a covered lens for
audio only) and microphone (present or muted). Every camera is rendered twice: a coded variant whose frames carry the
S08 frame barcode, and a clean variant without it; both carry the 1 kHz hit sound at its true arrival time.

Modules: ``rig`` (placements, camera specs and their clocks), ``scene`` (the events), ``profiles`` (the named rigs),
``clips`` (painters and StudioClips for the S08 pipeline) and ``truth`` (the ground-truth documents).
"""
