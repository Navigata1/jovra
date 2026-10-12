# Studio UI tests

JOVRA Studio's XCUITest suites live in this folder, inside the existing `JovraUITests` target. There is no separate
Studio test target or scheme: the spec's `JovraStudioUITests` scheme is replaced by `-only-testing` class filters.

- One class per screen family or flow, named `Studio<Thing>UITests` (for example `StudioHomeUITests`), so a ticket
  runs exactly its own classes:
  `SIMULATOR_ID=<your simulator> DERIVED_DATA=<worktree>/.derivedData scripts/ios/ui-test.sh -only-testing JovraUITests/StudioHomeUITests studio/<ticket>`
- Reuse the shared helpers in `../Support` (`launchJovra`, the accessibility audit) and the launch-argument contract in
  `ios/Jovra/Platform/LaunchConfiguration`. Every screen test runs `performAccessibilityAudit()`, light and dark, and
  one accessibility text size.
- The target links `JovraStudioCore` and `JovraStudioMedia`, so tests can read Studio Sample content and fixtures
  without a project edit.
- Named screenshots are exported to `evidence/ios/studio/<ticket>/`.

See `docs/studio/DEVELOPING.md` for packages, commands and the evidence layout.
