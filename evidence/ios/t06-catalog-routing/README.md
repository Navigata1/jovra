# Ticket catalog routing repair

Codex ticket branches were incorrectly treated as owning no localization table. Recognize only the additional anchored codex/tNN-slug prefix; table ownership and most-specific-area checks remain unchanged. Regression fails before the repair;32l10n public tests and the complete existing localization gate pass afterward. Tests retain wrong-owner, non-ticket, outside-folder and catalog-rename refusals.

This is a T06 maintenance repair needed by native feature PRs, not a new product feature or a ticket closure.
