# No paywall, ads or tracking in v1; the own-your-footage contract

v1 ships with every feature free and local: no StoreKit, no paywall, no ads, no third-party analytics or tracking SDKs
(target App Privacy "Data Not Collected"), no JOVRA server and no account required for any feature. The
**own-your-footage contract** holds regardless of any future business model: recordings made on your phone are never
capped by hours, hidden by age, watermarked, shown with ads or locked behind a login or plan; "Save original to Photos
or Files" and the full data export (JSON and CSV) are always available. Diagnostics leave the phone only when the user
taps to send them. Pricing (backlog P1-25) is Jon's decision and is deferred.

Recording limits, ads on personal video and lapsed-plan lockouts are among the most-cited complaints about the
incumbents (competitive-analysis), so leaving them out is part of the product, not a missing feature.

## Consequences

Adding pricing later needs a new ADR, and nothing it adds may restrict access to footage or data that already exists on
a user's phone.

Status: amended by ADR-0019 (Studio cloud boundary only)
