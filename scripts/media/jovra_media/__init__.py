"""JOVRA media fixture renderer core (standard library + ffmpeg only).

The renderer draws every fixture frame itself, encodes it with ffmpeg, decodes it back and records a
decoder-independent signature of every decoded frame (see ``signature.py``). Only the ground truth and
those signatures are committed; the media lives in an ignored cache keyed by the renderer's own hash.
"""
