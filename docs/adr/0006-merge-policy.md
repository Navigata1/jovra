# One PR per ticket, merged by the agent after required checks pass

Each ticket is a GitHub issue, built on `ticket/<NN>-<slug>`, opened as a PR into `main` that closes the issue, and
squash-merged only after the required CI jobs are green. The repo is private on a plan without native auto-merge or
branch protection, so the "merge only when green" rule is **enforced by the merging agent, not by GitHub**: the merger
runs `gh pr checks --watch` and refuses to merge on any failure. Simulator UI suites and device tests run on the
build Mac, not CI (macOS runner minutes on a private repo would exhaust the free quota); their evidence is attached
to the PR instead.
