"""Validate only the emitted capture record using the complete repository validator."""
from pathlib import Path
import shutil
import subprocess
root = Path(__file__).resolve().parents[3]
probe = root / 'spec/fixtures/records/session.capture-probe.json'
if probe.exists():
    raise RuntimeError('refusing to overwrite existing reference probe')
try:
    shutil.copyfile(Path(__file__).with_name('sample-session.json'), probe)
    subprocess.run(['python3', 'scripts/spec/validate.py'], cwd=root, check=True)
finally:
    probe.unlink(missing_ok=True)
