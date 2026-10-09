# Bounded T12 core-flow components

Part of issue #14, not completion of the whole ticket. Parent authorized state/sample/provenance components needed by native recording-to-export flow; Studio, Android, tablets/foldables and watches remain held.

Initial base: main 1605f4fe8994f7b5c3fe235912f1b49e632e5b87. Isolated managed checkout: /Users/IDC2.5/.codex/worktrees/jovra-t12-core-states/jv, branch codex/t12-core-state-components. Sole dedicated UI simulator 4265ADFD-39A3-4E71-8482-1945DDB5F899. Native artifacts use only this checkout’s .derivedData.

Pre-agreed seams derive from issue #14 acceptance: gallery actions invoke caller closures; Sample/Fixture labels remain explicit visually and for VoiceOver; native component states pass accessibility audits in light/dark/AX5 with named screenshots. No private-view tests or duplicate source assertions.

Intended slice: StateCard (empty/error/permission/unsupported caller content and two actions), DemoBanner with caller-owned action title/callback (default Make it yours), Sample/Fixture badges and small/on-forest provenance presentation. A DEBUG-only opt-in gallery mounts real components through one AppRoot modifier; release builds expose no gallery route. Two production consumers (Capture and Library) will use these in later bounded flow slices; this slice proves the component interface rather than finished consumer integration.

Full-ticket work remains pending: fraction/scope/tap StatTile, progress StatusPill, SettingsRow variants, compact/on-forest buttons, FractionPopover and zero-denominator behavior, registry-driven capability detail/benchmark substitution, Motion/haptics, Toast/UndoBar announcements, BannerView/InfoCard/FocusedHeader/ToggleRow, ReadableColumn regular-width layout proof, all-component gallery and photographic-asset scan. No new colour role is planned; existing contrast tests remain the numeric gate. Runtime iOS18 and physical device results remain unverified.
