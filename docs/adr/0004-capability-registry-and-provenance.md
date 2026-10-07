# Every metric carries provenance from a capability registry

Each analysis capability (audio hit detection, rally segmentation, ball trajectory, bounce placement, serve speed,
2D pose, stroke type, …) is registered with a status: `manual`, `estimated`, `validated`, `unsupported` or
`disabled`, plus a method/model version. Every derived number records which capability produced it, its confidence,
its calibration dependency and its denominator. The UI labels values by provenance ("Estimated", "Reviewed",
"Manual") and a capability can only be promoted to `validated` by a recorded benchmark run on labelled footage.
This is how JOVRA ships useful automatic analysis without ever presenting a guess as a measurement.
