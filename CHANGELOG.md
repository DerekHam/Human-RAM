# Changelog

All notable changes to Human RAM are documented here. This project uses
[Semantic Versioning](https://semver.org/).

## [0.3.2] - 2026-10-01

### Changed

- **RAM is arranged by date, then priority.** Tasks are grouped by their
  calendar day (start, else due; time of day ignored) and, within a day, the
  higher priority wins. Undated tasks follow dated ones; pinned tasks stay on
  top.
- **Start-less tasks enter RAM by priority.** A task without a start date now
  loads ahead of its due date by priority — **3 days** for high, **2** for
  normal, **1** for low, and on the due day for no priority. The auto-arrange
  window still governs tasks that carry an explicit start date.

### Fixed

- **Menu-bar count updates.** The menu-bar item now observes the store directly,
  so its count refreshes. It shows the loaded task count, a red dot when a task
  is due, and an orange dot when the notes inbox is full.

## [0.3.1] - 2026-10-01

### Fixed

- **Near-date entry no longer jumps to next year.** A typed `MMDD` is treated as
  next year's occurrence only when it is more than three days before today, so
  dates around today land in the current year.
- The entry year no longer drifts after a rolled-forward date, so a later entry
  in the same session is not silently shifted into next year.

## [0.3.0] - 2026-09-29

### Added

- **Calendar sync (one-way).** Optionally mirror tasks with a start or due time
  into a calendar as events with alarms, so reminders also reach your phone via
  iCloud/Google/Outlook. A dedicated **Human RAM** calendar is created by
  default; any writable calendar can be chosen instead. Settings → Calendar.
- **Notification status in Settings**, with a test notification and a shortcut
  to System Settings, so it's clear when macOS has blocked alerts.
- **Optional release signing.** `build_share.sh` / `release.sh` sign with
  `HRAM_SIGN_ID` when set (required for macOS notifications); the Release
  workflow can import a certificate from repo secrets.

## [0.2.2] - 2026-09-29

### Added

- **Theme setting.** Appearance can follow macOS or be forced to **Light** or
  **Dark** for Human RAM only (Settings → Appearance). The app already followed
  the system; this adds an explicit override.
- Opaque, light/dark screenshots in the README.

## [0.2.1] - 2026-09-29

### Added

- **Data safety.** Human RAM snapshots the database before every schema
  migration, so an upgrade can always be rolled back by hand.
- **Export and import.** Settings can export everything to a JSON archive and
  merge one back; imports keep the newest edit per item and never clobber newer
  local changes.
- **Backups in Settings.** Back up the database with one click, or reveal the
  database and backups folder in Finder.
- **Damaged-database recovery.** An unreadable database is moved aside and the
  app starts fresh instead of crashing on launch; Settings points to the file.
- **Update check.** Human RAM checks the public GitHub Releases list (one
  anonymous request, opt out in Settings) and shows a banner in the menu bar
  when a newer version is available.
- **Universal build.** Release builds now run on both Apple Silicon and Intel
  Macs.
- **Homebrew.** `brew install --cask human-ram` is the recommended install; the
  cask clears the quarantine flag so there is no "unidentified developer"
  warning.
- **Release tooling.** `Scripts/release.sh` builds a universal app and produces
  a DMG and zip with checksums; GitHub Actions runs tests on every push and can
  publish a release from a tag.

## [0.2.0] - 2026-09-28

### Added

- Menu-bar quick composer: write a **Task** or **Note** with optional start/due
  dates and priority without opening the overlay; press **Tab** to switch modes.
- Inline hotkey hints in the menu bar, plus footer shortcuts: Scan (`⌘D`),
  Diary (`⌘Y`), Journal (`⌘J`), Settings (`⌘,`), Quit (`⌘Q`).
- **Open review on launch** setting (default off) so the nightly review no longer
  pops up when the app opens.
- Compact numeric date fields in the menu-bar composer.
- Welcome guide on launch in the shareable build.

### Changed

- Menu bar: loaded tasks are always visible; the hard-drive backlog and pending
  notes share a short scroll area, with notes as a compact two-column list.
- The item editor window is rebuilt on each open so its draft always starts from
  the current item.
- Date entry: the year defaults to the current year each launch, and a date on
  **today** no longer jumps forward a whole year.
- Auto-arrange no longer undoes a deliberate spill or a decayed task; pinned
  tasks are never auto-spilled; a freshly captured or loaded task is no longer
  evicted immediately to make room.
- Changing a schedule setting no longer re-runs that day's Daily Scan.
- Due reminders fire to the second; the nightly review alert is scheduled only
  when notes are actually waiting.

### Fixed

- Pinned tasks could be auto-spilled when RAM was over capacity.
- Decay appeared to do nothing because the time-window fill immediately reloaded
  spilled tasks and refreshed them.
- Editing a task to a time beyond the window did not spill it until the next tick.
- Diary and Journal search showed the first-run empty copy when there were simply
  no matches.
- The guide's "Got it" button could close the wrong window.
- Impossible dates (`0230`) are rejected rather than silently rolled over.

## [0.1.0] - 2026-09-23

- Initial preview release: global-hotkey capture, bounded working set with spill
  to a hard-drive backlog, decay, Daily Scan, nightly note review, Diary,
  Journal, and a widget.
