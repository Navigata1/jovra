#!/usr/bin/env bash
# W03 (#280), G-W-SIMUI. Worktree-local custody prevents adopting or deleting a watch by name.
set -euo pipefail
exec python3 "$(dirname "$0")/watch_sim.py" "$@"
