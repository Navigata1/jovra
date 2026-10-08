"""Compare every generated Studio file that exists on origin/main with the worktree copy (sha256)."""
import hashlib
import subprocess
import sys

root = sys.argv[1]
paths = ["spec/studio/fixtures", "spec/studio/contracts", "spec/studio/modules/README.md"]
files = subprocess.run(["git", "-C", root, "ls-tree", "-r", "--name-only", "origin/main", *paths],
                       capture_output=True, text=True).stdout.split()
changed, same = [], 0
for f in files:
    old = subprocess.run(["git", "-C", root, "show", f"origin/main:{f}"], capture_output=True).stdout
    new = open(f"{root}/{f}", "rb").read()
    if hashlib.sha256(old).digest() == hashlib.sha256(new).digest():
        same += 1
    else:
        changed.append(f)
print(f"generated files on origin/main (the merge base): {len(files)}; byte-identical in this branch: {same}; changed: {changed}")
