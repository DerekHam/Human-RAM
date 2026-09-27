# Roadmap: iPhone App + Cross-Device Sync

**Status: IN PROGRESS.** Resumed. Phases 0 (Core split) and 1 (sync metadata + soft deletes) complete; Phases 2–3 next.

Phase 0 notes / deviations from the original plan:
- `HumanRAMShared` is kept as a tiny leaf (widget snapshot only); `HumanRAMCore` depends on it, so the widget never links the whole app.
- Portable UI moved into `HumanRAMCore`. `Shortcuts.swift` keeps its AppKit code behind `#if os(macOS)`.
- `SettingsView` stays in the macOS target for now (it uses `SMAppService` and Carbon `HotKeyDescriptor`); moved to Core in Phase 4 alongside the iOS tab UI.
- Navigation is abstracted through `AppRouter.shared` (closures the macOS app installs at launch) so Core never imports AppKit.

Phase 1 notes:
- `Item.updatedAt` is distinct from `touchedAt` (the latter still only drives decay).
- `ItemStore.delete` is a soft delete; `items` now contains tombstones and every UI query filters `deleted`.
- `ItemStore.dirtyItems` / `markSynced(ids:)` are the push-queue API for Phase 3; `purgeDeleted()` is internal and only for tests.
- The existing database migrates in place on next launch (additive; rows queued dirty for the first sync).
- Time-based store rules (`applyDecay`, `applyTimeWindow`, `fillWorkingSet`, `Item.freshness`) accept an injected `now`, and `NumericDateParser` is a pure, unit-tested helper, so behaviour is deterministic in tests.

Goal: run Human RAM on iPhone and sync tasks/notes across the user's Mac and phone.

---

## Decisions (locked)

| Topic | Decision |
|---|---|
| Apple Developer account | **Free Apple ID** for now (iOS installs expire every 7 days; re-run from Xcode to re-sign) |
| Sync backend | **Supabase** (Postgres). Backend abstracted behind an interface so Firebase is a cheap swap |
| Auth | **Email OTP code** (6-digit), same account on both devices. Avoids magic-link/deep-link plumbing |
| Sync transport | **Foreground + periodic** (on launch/foreground, after edits debounced, every few minutes). No realtime websocket for v1 |
| iOS project generation | **XcodeGen** (`Apps/HumanRAM-iOS/project.yml`, checked in) |
| Working set across devices | **Sync everything, soft capacity**: item state syncs; capacity enforced locally per device |
| iPhone v1 scope | **Core app**: capture, RAM/backlog, notes inbox, notifications, daily scan, journal, settings |
| Conflict resolution | **Last-writer-wins** on server-stamped `updated_at` |
| Deletes | **Soft-delete tombstones** (`deleted` flag) so removals propagate |

Cost note: both Supabase Free and Firebase Spark are $0 at this scale. Supabase Free projects **pause after 7 days of inactivity**; daily use avoids it.

---

## Architecture / repo restructure

Split the SwiftPM package so portable code is shared by both apps:

```
Package.swift            HumanRAMCore (no deps) + HumanRAMSync + tests
Sources/HumanRAMCore/    Models, Store (SQLite), Core, shared UI
Sources/HumanRAMSync/    Auth + SyncEngine + backend mapping (deps: Core, supabase-swift)
Sources/HumanRAM/        macOS app (deps: Core, Sync)
Apps/HumanRAM-iOS/       iOS app + project.yml (deps: Core, Sync)
```

### Moves as-is into `HumanRAMCore`
`Models/Item.swift`, `Models/AppSettings.swift`, `Store/Database.swift`, `Store/ItemStore.swift`, `System/Notifications.swift`, and views `CaptureView`, `DateTimeField`, `DiaryView`, `DigestView`, `JournalView`, `NotesReviewView`, `EditItemView`.

### Stays macOS-only in `Sources/HumanRAM`
`HumanRAMApp`, `AppDelegate`, `MenuBarView`, `HotKey`, `CapturePanel`, `WindowManager`.

### Needs platform abstraction
- `Scheduler` — currently imports AppKit to open windows. Move to Core with an injected `presenter` (macOS: open window; iOS: notify only / set flag to present on next foreground).
- `EditItemView` — `NSApp.keyWindow?.close()` becomes a dismiss callback.
- `SettingsView` — wrap `SMAppService` (launch-at-login) in `#if os(macOS)`.

---

## Data model changes (local SQLite)

Additive migration to `items`:
- `updated_at REAL` — set on every mutation.
- `deleted INTEGER DEFAULT 0` — tombstone; all queries filter `deleted = 0`.
- `dirty INTEGER DEFAULT 0` — needs push.

Rules:
- Every mutation sets `updated_at = now` and `dirty = 1`.
- `delete(id:)` becomes a soft delete (set `deleted = 1`, `dirty = 1`), keeping the row for sync.
- Working-set capacity stays a soft, per-device rule.

---

## Supabase backend

```sql
create table public.items (
  id uuid primary key,                    -- client-generated UUID
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  kind text not null default 'task',
  text text not null,
  detail text,
  due_at timestamptz,
  state text not null,
  priority int not null default 2,
  created_at timestamptz not null,
  loaded_at timestamptz,
  touched_at timestamptz not null,
  completed_at timestamptz,
  pinned boolean not null default false,
  deleted boolean not null default false,
  updated_at timestamptz not null default now()
);

alter table public.items enable row level security;
create policy items_owner on public.items
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create index items_user_updated_idx on public.items (user_id, updated_at);
```

- Ship only the **anon key** in the app (safe; RLS enforces isolation). Never ship the service-role key.
- Server stamps `updated_at` so device clock skew cannot corrupt ordering.

---

## Sync engine (`HumanRAMSync`)

Offline-first, backend-abstracted:
- **Push:** batch-upsert `dirty` rows (including tombstones).
- **Pull:** fetch rows with `updated_at > cursor`, merge last-writer-wins.
- **Cursor** stored per account (UserDefaults).
- **Triggers:** launch/foreground, after edits (debounced), and every few minutes.
- Works with no account signed in → behaves exactly like today (local-only).
- UI: sign-in sheet + "Sync" section in Settings with last-synced status.

---

## iOS app (Core scope)

XcodeGen-generated project. Tab layout — **RAM, Notes, Diary, Journal, Settings** — reusing Core views. Capture via prominent "+". Local notifications for due items, daily scan, nightly review. No background windows on iOS: review happens on open. User selects **Personal Team** in Xcode for signing.

Later (not v1): Home Screen widget, Share Sheet, Shortcuts action, realtime sync.

---

## Phases / checklist

- [x] **Phase 0** — Restructure into `HumanRAMCore`; macOS still builds; `swift test` green.
- [x] **Phase 1** — Add `updated_at` / `deleted` / `dirty`; soft deletes; queries filter deleted.
- [ ] **Phase 2** — Supabase project + schema + RLS; email OTP auth in `HumanRAMSync`; sign-in UI (both platforms).
- [ ] **Phase 3** — `SyncEngine` (push/pull, LWW, cursor, tombstones); foreground + periodic triggers; Mac integration.
- [ ] **Phase 4** — iOS app via XcodeGen; tab UI; capture; notification parity.
- [ ] **Phase 5** — Docs + tests (merge/LWW against a mock backend; keep the existing store/decay/date-parsing tests green).

---

## Prerequisites (user tasks)

1. Create a free **Supabase project**; run the schema SQL; copy **Project URL + anon key**.
2. In Xcode, select your **Personal Team** to sign the iOS app.
3. Install **XcodeGen** (`brew install xcodegen`).

---

## Risks / caveats

- Free-account iOS builds **expire every 7 days** (re-run from Xcode). Sync unaffected.
- Free Supabase **pauses after 7 days idle**; backend is swappable if annoying.
- Synced due items notify on **both** devices (expected; suppression is a later option).
- First sync is a one-time import of existing SQLite rows to the server.
- Adding a third-party dependency (`supabase-swift`); README "no dependencies" stance must be updated.

---

## Reference: current macOS coupling

macOS-specific files (exclude from Core): `HumanRAMApp.swift`, `System/AppDelegate.swift`, `System/HotKey.swift`, `System/CapturePanel.swift`, `System/WindowManager.swift`, `UI/MenuBarView.swift`. Weak coupling to clean up: `Core/Scheduler.swift`, `UI/EditItemView.swift`, `UI/SettingsView.swift`.
