# assemble

One YouTube warehouse file. Optional grade using lock palette only (no BuildLoop LUT).

```
0–HOOK     hook video, silence
HOOK–end   last frame frozen
HOOK–end   audio_master (listen-along or voice cut)
```

```
[hook_v]fps=2,format=yuv420p,tpad=stop_mode=clone:stop_duration=AUDIO_DUR[v]
[audio]adelay=HOOK_MS|HOOK_MS[a]
libx264 + aac, yuv420p, +faststart
```

Probe durations. Do not hardcode 8.064.
Do not overlay speech on the motion.
Do not upload this file to X.

YouTube: AI-generated tag on when picture or audio is generated.

## Output
`WAREHOUSE.mp4`
