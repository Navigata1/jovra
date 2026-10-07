# cut

Turn raw A-roll or a listen-along source into keepers.

## Talking-head
Documentary, not a multi-take script. Keep the spine. Delete navigation silence and repeated explanations.
After keepers are clean, speed voice+picture **once** to 1.25× (`atempo=1.25,setpts=PTS/1.25`).
Do not speed again in mux or cutdowns.

Spine for a Garnet longform (delete beats that have no proof):
1. Two houses — father's shop / own house at night
2. DHH velocity + Rust rigor
3. What shipped — check · diff-caps · seal
4. One real terminal capture
5. Door that stays locked until evidence exists
6. CTA — garnet-lang.org · signed tag truth

## Listen-along
Do not cut the source essay audio except to remove host name-garble if Jon asks.
Keep the 8s hook *off* this file. Mux attaches it.

## Output
`keepers.json` with in/out, one-line why, and the spine beat it serves.
