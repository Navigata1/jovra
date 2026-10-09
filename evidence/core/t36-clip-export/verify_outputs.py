"""Independently decode retained Apple exports with ffmpeg and inspect their tracks with ffprobe."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(root / "scripts/media"))
from jovra_media.encode import decoded_signatures
from jovra_media.sets.frame_counter import clips

folder = Path(sys.argv[1])
expected = {"frameCounter-fc-060.mp4", "frameCounter-fc-240.mp4", "audio-on.mp4", "audio-off.mp4",
            "captured-offset-source.mp4", "captured-offset-clip.mp4"}
assert {p.name for p in folder.iterdir()} == expected

def tracks(path):
    result = subprocess.run(["ffprobe", "-v", "error", "-count_frames", "-show_entries",
        "stream=codec_type,start_time,duration,nb_read_frames,r_frame_rate", "-of", "json", str(path)],
        check=True, capture_output=True, text=True)
    return json.loads(result.stdout)["streams"]

manifest = []
for path in sorted(folder.iterdir()):
    # A successful complete decode is separate from declarations in a mux header.
    subprocess.run(["ffmpeg", "-v", "error", "-xerror", "-i", str(path), "-f", "null", "-"],
                   check=True, capture_output=True)
    info = tracks(path)
    video = next(t for t in info if t["codec_type"] == "video")
    audio = [t for t in info if t["codec_type"] == "audio"]
    if path.name.startswith("frameCounter-"):
        identifier = path.stem.removeprefix("frameCounter-")
        fixture = next(c for c in clips() if c.id == identifier)
        codes = []
        for levels in decoded_signatures(fixture, path):
            code = 0
            for level in levels[:16]:
                code = (code << 1) | (level >= 2)
            codes.append(code)
        assert codes == list(range(17, 47)), (path.name, codes)
        assert not audio
        print(path.name, "ffmpeg burned counters17...46,30frames PASS")
    elif path.name in {"audio-on.mp4", "audio-off.mp4"}:
        assert bool(audio) == (path.name == "audio-on.mp4")
        print(path.name, "independent audio track policy PASS")
    elif path.name == "captured-offset-source.mp4":
        assert float(video["start_time"]) > 0 and int(video["nb_read_frames"]) == 60
        print(path.name, "raw mux offset", video["start_time"], "60 decoded frames PASS")
    else:
        assert int(video["nb_read_frames"]) == 30 and not audio
        assert float(video["start_time"]) == 0 and abs(float(video["duration"]) - 1) < 1 / 30
        print(path.name, "normalized0...1second30decodedframes PASS")
    manifest.append(dict(file=path.name, bytes=path.stat().st_size,
                         sha256=hashlib.sha256(path.read_bytes()).hexdigest(), tracks=info))
Path(sys.argv[2]).write_text(json.dumps(manifest, indent=2) + "\n")
print("Independent full-decode/counter/track inspection PASS:6retainedfiles")
