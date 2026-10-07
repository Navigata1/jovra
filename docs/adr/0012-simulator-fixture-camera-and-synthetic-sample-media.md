# A simulator fixture camera and synthetic sample media

The iOS Simulator has no camera, so capture offers a **"Simulator fixture camera"** wherever no camera hardware exists:
it streams a fixture video through the same recording, segment and journal pipeline as a real camera (ADR-0010), so the
whole capture UI, interruption handling and recovery can be exercised in UI tests. It never appears where a real camera
is present. Demo content and analysis fixtures come from a **synthetic sample video** rendered by a repo script: a
perspective court, players as simple figures, a ball on physically plausible paths and hit clicks in the audio. It is
labelled "Sample video (synthetic)" and ships with exact ground truth (hit times, bounces, rally boundaries), which
makes it a benchmark fixture as well as demo content. The Jon vs Alex sample match is a separate, rules-coherent
124-point event fixture; any video shown with it is an illustrative clip.

## Considered Options

- Filmed real footage in the repo: hand labels instead of exact truth, likeness and consent questions, and large binary
  files. Stock or professional footage: licensing and the brand rule against pro likenesses.
- Hiding capture on the Simulator: leaves the most important flow without UI evidence until hardware.

## Consequences

Simulator capture evidence and synthetic benchmark results are reported as exactly that. A capability can fail on
synthetic media, but only a benchmark on real footage can promote it (ADR-0004); real capture is validated in the
hardware phase.
