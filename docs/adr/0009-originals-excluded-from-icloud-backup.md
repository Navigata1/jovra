# Originals are excluded from iCloud device backup by default

Original media files are marked excluded from iCloud and Finder device backups by default. A Settings toggle, "Include
originals in iCloud device backup", turns them back in, with the trade-off stated next to it. Session documents,
marks, annotations and other small records stay in the device backup. Until a session has a verified backup (ADR-0008),
the library shows it prominently as "Only on this iPhone", and "Save original to Photos or Files" is always available.

Apple's guidance is to back up irreplaceable user content, so this default looks wrong without context. It is
deliberate: an hour of 1080p60 is about 5.4 GB and a two-hour 4K60 match about 48 GB, which can push a user past their
iCloud plan and make the **whole** device backup fail, a worse outcome than one unarchived video. The honest fix is to
say plainly where each original lives, not to let a silent backup failure stand in for durability.

## Consequences

After restoring a phone from an iCloud backup, sessions come back without their originals. The library must show them
as "Original not on this iPhone", offer restore from the archive when one exists, and keep every stat, mark and
annotation usable without the video.
