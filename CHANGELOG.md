# Changelog

All notable changes to Human RAM are documented here. This project uses
[Semantic Versioning](https://semver.org/).

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
