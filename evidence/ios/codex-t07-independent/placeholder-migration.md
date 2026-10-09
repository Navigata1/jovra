# Migrating T07's transitional placeholder tests

T07's production routes and destination type names should stay stable as features become real. The current `AppRouterTests.placeholderFiles` check and `NavigationRoutesUITests.assertPlaceholder` deliberately assert scaffolding. They must not force finished features to retain fake UI.

## Smallest durable seam for the first feature replacement

1. Introduce a small `RouteScreenMetadata` protocol with an own-file static `isPlaceholder` flag. Scaffold types default to `true`; an implemented owning screen declares `false` in its own file.
2. Wire the catalog to those type properties once. Thereafter feature owners replace their own screen body and flag without editing AppRouter or route destinations. Do not move feature behavior into the catalog.
3. Give every routed screen a stable accessibility identifier (for example `screen.capture`), independent of its changing visible heading. Route identity, close action, selected tab, and payload serialization remain permanent router contracts.
4. Keep ticket-label/source-marker assertions only for placeholder screens. Real-screen navigation checks assert the stable screen identifier and back/close behavior; their owning ticket adds actual functionality tests.
5. Replace placeholder payload-text assertions (including the restoration probe) with meaningful real-screen state when their owning feature is implemented. For capture, verify the restored session-kind control and returning Record tab rather than a debug payload card.

Avoid a central growing list of exemptions and avoid weakening tests to accept a blank route. Actual capture/store/replay/scoring/export tests should prove each implemented screen does useful work. No migration was applied during this independent baseline review.
