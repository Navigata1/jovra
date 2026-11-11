# S88 parity table (2026-11-08T09:28Z, node v26.8.2, commit base f9db4c8)

| vector file | case | op | reference result | expect sha256 | port sha256 | parity |
|---|---|---|---|---|---|---|
| director | context-sample-court-day | context | context | 0a0ecd2fd5daca85 | 0a0ecd2fd5daca85 | base context |
| director | full-coach-cut | brief | brief | 19d90fca1271faf5 | 19d90fca1271faf5 | identical |
| director | full-match-broadcast | brief | brief | 9e609e6f65962942 | 9e609e6f65962942 | identical |
| director | full-rally-pulse | brief | brief | 2d6f048cb5a12233 | 2d6f048cb5a12233 | identical |
| director | full-progress-story | brief | brief | 7e70df92e40ea308 | 7e70df92e40ea308 | identical |
| director | full-court-memories | brief | brief | 7ab11936db37e086 | 7ab11936db37e086 | identical |
| director | default-length-coach-cut | brief | brief | 4cbc9d378897a801 | 4cbc9d378897a801 | identical |
| director | default-length-rally-pulse | brief | brief | bd8e0d9d174809c3 | bd8e0d9d174809c3 | identical |
| director | court-memories-defaults | brief | brief | c3f94d8922ae32b2 | c3f94d8922ae32b2 | identical |
| director | refuse-match-broadcast-3min | brief | refusal | 95f54430bdf6e2c0 | 95f54430bdf6e2c0 | identical |
| director | refuse-rally-pulse-5min | brief | refusal | 55617fac8ebe8234 | 55617fac8ebe8234 | identical |
| director | short-recording-5min | brief | refusal | 2c1ba04b2fa63a08 | 2c1ba04b2fa63a08 | identical |
| director | short-recording-full | brief | brief | 81dc561219c78403 | 81dc561219c78403 | identical |
| director | short-recording-broadcast-full | brief | refusal | 95f54430bdf6e2c0 | 95f54430bdf6e2c0 | identical |
| director | no-keepers-coach-cut | brief | refusal | 63376b61e5b918ee | 63376b61e5b918ee | identical |
| director | no-keepers-match-broadcast | brief | refusal | 63376b61e5b918ee | 63376b61e5b918ee | identical |
| director | no-keepers-rally-pulse | brief | refusal | 63376b61e5b918ee | 63376b61e5b918ee | identical |
| director | no-keepers-progress-story | brief | refusal | 63376b61e5b918ee | 63376b61e5b918ee | identical |
| director | no-keepers-court-memories | brief | refusal | 63376b61e5b918ee | 63376b61e5b918ee | identical |
| director | portrait-letterboxed | brief | brief | 5b98e588eeb3b2e8 | 5b98e588eeb3b2e8 | identical |
| director | junior-mode-no-audio | brief | brief | 6d0d1686382f18e4 | 6d0d1686382f18e4 | identical |
| director | silent-source-no-audio | brief | brief | c85b397cbef1a92d | c85b397cbef1a92d | identical |
| director | rally-pulse-medium-effects | brief | brief | 922efe4141b34c23 | 922efe4141b34c23 | identical |
| director | rally-pulse-high-effects | brief | reject | 3975868f99e75448 | 3975868f99e75448 | identical |
| director | effects-on-coach-cut | brief | reject | 3975868f99e75448 | 3975868f99e75448 | identical |
| director | shake-stays-off | brief | reject | 3975868f99e75448 | 3975868f99e75448 | identical |
| director | rallies-stay-whole | brief | reject | 3975868f99e75448 | 3975868f99e75448 | identical |
| director | music-on-coach-cut | brief | reject | 3975868f99e75448 | 3975868f99e75448 | identical |
| director | court-memories-licensed-music | brief | brief | d43f4920cd581e83 | d43f4920cd581e83 | identical |
| director | narration-with-consent | brief | brief | 331ce8e1345a792d | 331ce8e1345a792d | identical |
| director | narration-on-broadcast | brief | reject | 3975868f99e75448 | 3975868f99e75448 | identical |
| director | narration-without-consent | brief | reject | aa574d312f27324c | aa574d312f27324c | identical |
| director | caption-and-venue | brief | brief | 59b4bf18e6081d3f | 59b4bf18e6081d3f | identical |
| director | caption-must-be-a-caption | brief | reject | b6541c5ed8b82138 | b6541c5ed8b82138 | identical |
| director | unknown-option | brief | reject | 8d9fb8a5fec5832b | 8d9fb8a5fec5832b | identical |
| director | unknown-profile | brief | reject | 89c9e3a314d10698 | 89c9e3a314d10698 | identical |
| director | card-templates | templates | templates | ca9192bf30da4957 | ca9192bf30da4957 | identical |
| director | sample-court-memories-brief | lint | findings | 9d0f2143c61cfbb6 | 9d0f2143c61cfbb6 | identical |
| director | sample-progress-brief-replay-first | lint | findings | e7c86eb7292aaab8 | e7c86eb7292aaab8 | identical |
| director | planned-coach-cut-clean | lint | findings | 9d0f2143c61cfbb6 | 9d0f2143c61cfbb6 | identical |
| director | replay-at-one-eighth | lint | findings | b991372d7dd88890 | b991372d7dd88890 | identical |
| director | replay-before-its-live | lint | findings | e7c86eb7292aaab8 | e7c86eb7292aaab8 | identical |
| director | estimated-cue-as-instruction | lint | findings | 275cec62235d1a03 | 275cec62235d1a03 | identical |
| director | music-in-coach-cut | lint | findings | 7661db4ba7289bae | 7661db4ba7289bae | identical |
| director | medium-effects-in-coach-cut | lint | findings | f02fe1cb32197426 | f02fe1cb32197426 | identical |
| director | instruction-without-reviewed-cue | lint | findings | 52716260157917e1 | 52716260157917e1 | identical |
| director | broadcast-off-the-wide-angle | lint | findings | 4f88451e04cad4f0 | 4f88451e04cad4f0 | identical |
| director | broadcast-out-of-order | lint | findings | c5d33f565ea2c724 | c5d33f565ea2c724 | identical |
| director | broadcast-replay-after-the-next-point | lint | findings | 6a79fe8d2d44e0b8 | 6a79fe8d2d44e0b8 | identical |
| director | final-score-on-incomplete-coverage | lint | findings | 679bf4f90192e1a6 | 679bf4f90192e1a6 | identical |
| director | narration-in-broadcast | lint | findings | b1c1c3672f0822d1 | b1c1c3672f0822d1 | identical |
| director | rally-pulse-five-minutes | lint | findings | df157a292a106a31 | df157a292a106a31 | identical |
| director | freeze-in-rally-pulse | lint | findings | ea6660753d139d76 | ea6660753d139d76 | identical |
| director | goal-card-in-rally-pulse | lint | findings | 96139d49da983bd0 | 96139d49da983bd0 | identical |
| director | percent-improvement | lint | findings | 665edc3255981790 | 665edc3255981790 | identical |
| director | change-claim-from-manual-counts | lint | findings | 665edc3255981790 | 665edc3255981790 | identical |
| director | broll-not-from-this-match | lint | findings | 53ef22fdd1400f17 | 53ef22fdd1400f17 | identical |
| director | broll-reveals-hidden-venue | lint | findings | e80ded46df2d7dd9 | e80ded46df2d7dd9 | identical |
| director | same-moment-twice | lint | findings | 2146ec230c185028 | 2146ec230c185028 | identical |
| planner | context-sample-court-day | context | context | 0a0ecd2fd5daca85 | 0a0ecd2fd5daca85 | base context |
| planner | coach-cut-3min | plan | plan | 98655c7d8776ddbd | 98655c7d8776ddbd | identical |
| planner | coach-cut-5min | plan | plan | 0746368ee9630c8d | 0746368ee9630c8d | identical |
| planner | coach-cut-full | plan | plan | 18179b1a4991475b | 18179b1a4991475b | identical |
| planner | match-broadcast-3min | plan | refusal | 7337c74d77a73a34 | 7337c74d77a73a34 | identical |
| planner | rally-pulse-5min | plan | refusal | ce19a6f02c49c090 | ce19a6f02c49c090 | identical |
| planner | match-broadcast-5min | plan | plan | 87b24d6e18b9d686 | 87b24d6e18b9d686 | identical |
| planner | match-broadcast-full | plan | plan | 53b0e140003ab076 | 53b0e140003ab076 | identical |
| planner | rally-pulse-3min | plan | plan | cd92db0e1942fb54 | cd92db0e1942fb54 | identical |
| planner | rally-pulse-full | plan | plan | 69e3f72e87286c7f | 69e3f72e87286c7f | identical |
| planner | progress-story-3min | plan | plan | 20c2bb77eca8574d | 20c2bb77eca8574d | identical |
| planner | progress-story-5min | plan | plan | 7bdcb7141c27076a | 7bdcb7141c27076a | identical |
| planner | progress-story-full | plan | plan | 5089f0797e024df5 | 5089f0797e024df5 | identical |
| planner | court-memories-3min | plan | plan | 12217cb41da00948 | 12217cb41da00948 | identical |
| planner | court-memories-5min | plan | plan | dbec7738da04188d | dbec7738da04188d | identical |
| planner | court-memories-full | plan | plan | d9abdb4a98241005 | d9abdb4a98241005 | identical |
| planner | coach-cut-your-examples | plan | plan | ef02e9f36eba573e | ef02e9f36eba573e | identical |
| planner | match-broadcast-one-angle | plan | plan | 717240c6d96bf40e | 717240c6d96bf40e | identical |
| planner | progress-story-method-change | plan | plan | 31e72c0bbdc32526 | 31e72c0bbdc32526 | identical |
| planner | court-memories-no-broll | plan | plan | ee08fc69bb39879a | ee08fc69bb39879a | identical |
| planner | court-memories-broll-shows-venue | plan | plan | a5b8437dd426d564 | a5b8437dd426d564 | identical |
| planner | court-memories-broll-shows-venue-opted-in | plan | plan | 235b60088c486c11 | 235b60088c486c11 | identical |
| planner | court-memories-broll-not-this-match | plan | plan | 4cb59d52715154c3 | 4cb59d52715154c3 | identical |
| planner | court-memories-no-broll-reasons | plan | plan | ee08fc69bb39879a | ee08fc69bb39879a | identical |
| planner | rally-pulse-court-sound | plan | plan | ce8dbdfca6ec03ba | ce8dbdfca6ec03ba | identical |
| planner | rally-pulse-licensed-music | plan | plan | 1d2a8017f7ce6d18 | 1d2a8017f7ce6d18 | identical |
| planner | no-keepers | plan | refusal | d1497f42131b93ba | d1497f42131b93ba | identical |
| planner | check-coach-cut-3min | check | check | 17be8b6c7f48e4a4 | 17be8b6c7f48e4a4 | identical |
| planner | unknown-keeper | check | reject | b6541c5ed8b82138 | b6541c5ed8b82138 | identical |
| planner | card-with-free-text | check | reject | 8d9fb8a5fec5832b | 8d9fb8a5fec5832b | identical |
| planner | unknown-card-template | check | reject | b6541c5ed8b82138 | b6541c5ed8b82138 | identical |
| planner | card-note-of-the-wrong-use | check | reject | bbd475a6a0411cdc | bbd475a6a0411cdc | identical |
| planner | card-without-its-note | check | reject | bbd475a6a0411cdc | bbd475a6a0411cdc | identical |
| planner | angle-with-no-view | check | reject | b6541c5ed8b82138 | b6541c5ed8b82138 | identical |
| planner | overlay-not-stored | check | reject | b6541c5ed8b82138 | b6541c5ed8b82138 | identical |
| planner | card-showing-a-keeper | check | reject | f40289b98b61a097 | f40289b98b61a097 | identical |
| planner | stale-event-revision | check | reject | 9f8955d3073f27ba | 9f8955d3073f27ba | identical |
| planner | other-project | check | reject | 5a4d9116e8ddea43 | 5a4d9116e8ddea43 | identical |
| planner | music-without-rights | check | reject | b6541c5ed8b82138 | b6541c5ed8b82138 | identical |
| planner | check-progress-story-3min | check | check | d26de9a0504b6366 | d26de9a0504b6366 | identical |
| planner | fabricated-comparison | check | reject | b6541c5ed8b82138 | b6541c5ed8b82138 | identical |
| planner | fabricated-comparison-delta | check | reject | b6541c5ed8b82138 | b6541c5ed8b82138 | identical |
| planner | comparison-with-free-text | check | reject | 8d9fb8a5fec5832b | 8d9fb8a5fec5832b | identical |
| planner | comparison-without-stored-progress | check | reject | b6541c5ed8b82138 | b6541c5ed8b82138 | identical |
| planner | comparison-across-method-change | check | reject | b6541c5ed8b82138 | b6541c5ed8b82138 | identical |
| planner | check-sample-court-memories-brief | check | check | 7944c007a102ecf9 | 7944c007a102ecf9 | identical |
| planner | check-sample-progress-brief | check | check | d26de9a0504b6366 | d26de9a0504b6366 | identical |
| compile | context-sample-court-day | context | context | 10feea4924c817da | 10feea4924c817da | base context |
| compile | context-one-camera-60 | context | context | f3148c2184b8b6da | f3148c2184b8b6da | base context |
| compile | context-one-camera-30 | context | context | f67f3ad77f59bbe7 | f67f3ad77f59bbe7 | base context |
| compile | context-one-camera-720p | context | context | 33b1e853a32644e4 | 33b1e853a32644e4 | base context |
| compile | context-one-camera-restart | context | context | c42ce12a3aa15b2e | c42ce12a3aa15b2e | base context |
| compile | coach-cut-3min | compile | edl | 584a0655462e5ae1 | 584a0655462e5ae1 | identical |
| compile | coach-cut-5min | compile | edl | fe13d3d82e292f42 | fe13d3d82e292f42 | identical |
| compile | coach-cut-full | compile | edl | cd1da3e6e9ca34d6 | cd1da3e6e9ca34d6 | identical |
| compile | match-broadcast-5min | compile | edl | a13a8c7eef3bdd75 | a13a8c7eef3bdd75 | identical |
| compile | match-broadcast-full | compile | edl | 0a1ef848e4e0494f | 0a1ef848e4e0494f | identical |
| compile | rally-pulse-3min | compile | edl | 3efee9cebd27fa6b | 3efee9cebd27fa6b | identical |
| compile | rally-pulse-full | compile | edl | d92b8df154dd4e8f | d92b8df154dd4e8f | identical |
| compile | progress-story-3min | compile | edl | 70cb4f0d56542dea | 70cb4f0d56542dea | identical |
| compile | progress-story-5min | compile | edl | 9210f61844e4207e | 9210f61844e4207e | identical |
| compile | progress-story-full | compile | edl | cfdb059c9b94ead6 | cfdb059c9b94ead6 | identical |
| compile | court-memories-3min | compile | edl | 16d844c1eb5b5484 | 16d844c1eb5b5484 | identical |
| compile | court-memories-5min | compile | edl | 750debf34f94bbd4 | 750debf34f94bbd4 | identical |
| compile | court-memories-full | compile | edl | 1490099067709f55 | 1490099067709f55 | identical |
| compile | coach-cut-3min-stage-s1 | compile | edl | 584a0655462e5ae1 | 584a0655462e5ae1 | identical |
| compile | match-broadcast-5min-stage-s1 | compile | refusal | ba98465681dce4dc | ba98465681dce4dc | identical |
| compile | coach-cut-3min-default-clock | compile | refusal | f33a0ac56ff88ce4 | f33a0ac56ff88ce4 | identical |
| compile | court-memories-3min-default-clock | compile | edl | 16d844c1eb5b5484 | 16d844c1eb5b5484 | identical |
| compile | fps-above-source | compile | refusal | fb72c40f4c9198f9 | fb72c40f4c9198f9 | identical |
| compile | fps-above-broll | compile | refusal | 10387d1d8345b772 | 10387d1d8345b772 | identical |
| compile | half-speed-replay-30fps-source | compile | edl | 3594e0c91fa68bbf | 3594e0c91fa68bbf | identical |
| compile | half-speed-replay-60fps-source | compile | edl | 4f681c141d56b6db | 4f681c141d56b6db | identical |
| compile | hold-bed-not-over-kept-play | compile | edl | 2a9bf470fba8d25a | 2a9bf470fba8d25a | identical |
| compile | upscale-refused | compile | refusal | 55343b7cd17ba506 | 55343b7cd17ba506 | identical |
| compile | default-output-720p | compile | edl | 250f4873997e4f14 | 250f4873997e4f14 | identical |
| compile | one-camera-restart | compile | edl | 6fef0be00ed4b2e7 | 6fef0be00ed4b2e7 | identical |
| compile | one-camera-no-restart | compile | edl | 564dc09f803dfa2d | 564dc09f803dfa2d | identical |
| compile | titles-not-in-this-build | compile | edl | af6bab03ef4134ad | af6bab03ef4134ad | identical |
| compile | replays-not-in-this-build | compile | edl | 3a426f90c0ff8ad1 | 3a426f90c0ff8ad1 | identical |
| compile | overlays-not-in-this-build | compile | edl | fceb8c0254ac9130 | fceb8c0254ac9130 | identical |
| compile | hold-bed-not-in-this-build | compile | edl | 14bb4b489ed81ef1 | 14bb4b489ed81ef1 | identical |
| compile | renderer-without-live | compile | refusal | c84cca59ad75d3ce | c84cca59ad75d3ce | identical |
| compile | junior-mode-silent | compile | edl | cc5920c478f345e9 | cc5920c478f345e9 | identical |
| compile | court-memories-final-film | compile | edl | b634bc703079c65c | b634bc703079c65c | identical |
| compile | court-memories-final-film-stage-s1 | compile | edl | e47f03fcc814044b | e47f03fcc814044b | identical |
| compile | trim-outside-window | compile | reject | 165631bdb65fdf7d | 165631bdb65fdf7d | identical |
| compile | unknown-keeper | compile | reject | b6541c5ed8b82138 | b6541c5ed8b82138 | identical |
| compile | stale-event-revision | compile | reject | 9f8955d3073f27ba | 9f8955d3073f27ba | identical |
| compile | window-across-gap | compile | reject | c8c7f5c8ef422226 | c8c7f5c8ef422226 | identical |
| compile | unknown-request-field | compile | reject | 8d9fb8a5fec5832b | 8d9fb8a5fec5832b | identical |

director (spec/studio/fixtures/vectors/director.json): 58/58 byte-identical, plus 1 base context case(s); results {"brief":16,"refusal":9,"reject":10,"templates":1,"findings":22}
planner (spec/studio/fixtures/vectors/planner.json): 46/46 byte-identical, plus 1 base context case(s); results {"plan":23,"refusal":3,"check":4,"reject":16}
compile (spec/studio/fixtures/vectors/compile.json): 39/39 byte-identical, plus 5 base context case(s); results {"edl":28,"refusal":6,"reject":5}
TOTAL: 143/143 reference vectors reproduced byte for byte (canonical JSON).
