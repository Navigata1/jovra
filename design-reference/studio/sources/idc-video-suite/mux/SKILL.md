# mux

One YouTube file.

```
0–8s     hook video, silence
8s–end   last frame of the hook, frozen
8s–end   listen-along or voice master
```

ffmpeg pattern (durations from ffprobe, do not hardcode):

```
[hook_v]fps=2,format=yuv420p,tpad=stop_mode=clone:stop_duration=AUDIO_DUR[v]
[audio]adelay=HOOK_MS|HOOK_MS[a]
libx264 + aac, yuv420p, +faststart
```

Do not overlay speech on the motion.
Do not upload the long file to X.
YouTube: AI-generated tag on when the audio or picture is generated.

## Output
`WAREHOUSE.mp4` — the only file that goes to Island Dev Crew YouTube.
