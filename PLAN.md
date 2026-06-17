# Lane — Implementation Plan

A keyboard-first macOS launcher for switching between parallel work *tracks*. Each track is a folder; inside it live repos and linked Jira tickets, and every item exposes actions that **focus an existing window or launch a new one**.

This document is the complete build spec. Every prior open question is resolved into a decision below; an agent should be able to implement it end to end without further design input. "Lane" is the working title — rename freely, but keep the iTerm session sentinel (below) stable once shipped.

---

## 1. Stack & project setup

- **Language:** Swift 6, strict concurrency on.
- **UI:** SwiftUI for content, AppKit (`NSPanel`, `NSVisualEffectView`, `NSHostingView`) for the window shell.
- **Minimum OS:** macOS 15 (Sequoia) or later. Use modern SwiftUI freely.
- **App type:** `LSUIElement = YES` (accessory app, no Dock icon). A menu-bar status item provides Settings and Quit.
- **Sandbox:** **Off.** The app runs `git`, drives other apps via Apple Events, and reads arbitrary folders. (Automation TCC prompts still apply — see §7.)
- **Dependencies (SPM):** exactly one — [`KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts) for the global hotkey + recorder UI. It uses Carbon hot-key registration, so **no Accessibility permission is required.** Everything else is first-party.
- **Info.plist keys:** `NSAppleEventsUsageDescription` ("Lane opens and focuses your browser, terminal, and editor windows."), `LSUIElement = true`.
- **Signing:** Developer ID or local "Sign to Run Locally" is fine for personal use. TCC Automation grants are tied to the signed bundle, so keep a stable bundle id (`com.<you>.lane`).

### Module layout
```
Lane/
  App/            LaneApp.swift, AppDelegate, StatusItem, hotkey wiring
  Window/         PanelController (NSPanel), PanelHostingView
  Model/          Track, TrackLibrary, TrackStore, Item, BasicItem
  Providers/      TrackProvider, ProviderRegistry, Jira/Repository/Folder/Agents providers
  Services/       Shell, GitInspector, HostAdapter(+impls), ChromeController, ITermController, AppLauncher, Permissions
  Search/         FuzzyMatcher, SubtreeIndex
  UI/             RootView, LevelView, RowView, Breadcrumb, Footer, Toast, InputView, Settings
  Design/         Tokens, Icons
```

---

## 2. Architecture (the settled model)

Four layers; nothing below couples to anything above it.

- **Track** — a self-contained folder. Identity, name, archived-state, and working dir are all derived from the folder's location/name; only a tiny meta file plus provider files are persisted, all inside `.track/`.
- **Item** — the one universal node. Optional `run` (leaf = action) and `children()` (container). Actions are just leaf items. A provider owns its entire subtree; there is **no cross-provider attachment** and **no capability system**.
- **TrackProvider** — app-wide, statically registered. Given a track + its store, produces that track's top-level items (and creation actions). The registry fans out providers only at the track's top level; below that, each item yields its own children.
- **Services** — every side effect (shell, git, browser, terminal, launchers) lives here and is injected into providers.

Navigation is a stack: level 0 is the Track list (special — a Track is the persistence unit, not an Item); level 1 is the merged provider output for the entered track; every deeper level is `selectedItem.children()`.

---

## 3. Persistence

### On-disk layout
```
<root>/                         ← configurable; the only global setting
  .archive/                     ← archived track folders are moved here
    old-feature/  .track/ …
  PROJ-123-login/               ← a track = a working-dir folder
    .track/                     ← metadata; never the user's code
      track.json                ← { "id": UUID, "createdAt": ISO8601, "lastOpenedAt": ISO8601? }
      jira.json                 ← provider-owned, written only if it persists
    service-api/   (.git)       ← repos discovered here
    web-client/    (.git)
```

**Decisions:**
- **Every visible (non-dot) folder in `root` is a track.** No marker required. `.track/` is created lazily on first write. This means dropping an existing project folder into `root` makes it a track instantly.
- **Archived = lives under `.archive/`.** Positional, not a stored flag. Archive = move folder into `.archive/`; unarchive = move back.
- **Name = folder name. Working dir = the folder itself.** Neither is stored.
- **`id` (UUID) is kept** in `track.json`. It survives renames and is the stable key for the iTerm session tag (§7) and `lastOpenedAt` ordering.
- Provider state is one JSON file per provider key inside `.track/` (e.g. `jira.json`). Self-contained: the whole track moves/renames/deletes as a unit.
- **Atomic writes:** serialize to a temp file in `.track/`, then `FileManager.replaceItemAt`. Pretty-printed, `.sortedKeys`.

### Types
```swift
struct Track: Identifiable, Hashable {
    let url: URL                 // the folder = working dir = the track
    var id: UUID
    var createdAt: Date
    var lastOpenedAt: Date?

    var name: String { url.lastPathComponent }                         // = folder name
    var isArchived: Bool { url.deletingLastPathComponent().lastPathComponent == ".archive" }
    var dotTrack: URL { url.appendingPathComponent(".track", isDirectory: true) }
}

final class TrackStore {                                   // central, scoped to ONE track
    let track: Track
    func value<T: Decodable>(_ type: T.Type, _ key: String) -> T?   // reads .track/<key>.json
    func setValue<T: Encodable>(_ value: T, _ key: String) throws    // atomic write; mkdirs .track
    func clear(_ key: String) throws                                 // removes .track/<key>.json
}

final class TrackLibrary: ObservableObject {
    var root: URL                                          // from UserDefaults; see Settings
    func tracks(includeArchived: Bool = false) -> [Track]  // list folders, load meta, sort by lastOpenedAt desc
    func create(name: String) throws -> Track              // mkdir root/<name>, write track.json (new UUID, createdAt now)
    func touch(_ track: Track)                             // set lastOpenedAt = now (called on enter)
    func archive(_ track: Track) throws                    // mv → root/.archive/<name>, suffix on collision
    func unarchive(_ track: Track) throws                  // mv → root/<name>, suffix on collision
    func rename(_ track: Track, to name: String) throws    // mv folder; id in track.json keeps identity
    func delete(_ track: Track) throws                     // remove folder
}
```

**Discovery rules:** track listing skips names beginning with `.` (so `.archive` is excluded; archived tracks are the contents of `.archive`). When loading a track, if `track.json` is missing, create it (new UUID, `createdAt = now`). Re-scan `root` every time the panel opens, so external renames/moves are picked up for free. Archive/unarchive collisions append `-2`, `-3`, … to the destination name.

---

## 4. Domain core

```swift
protocol Item: Identifiable {
    var id: String { get }                          // stable, namespaced: "repo:/abs/path", "jira:PROJ-123"
    var title: String { get }
    var subtitle: String? { get }
    var icon: IconToken { get }
    var keywords: [String] { get }
    var run: (() async throws -> RunOutcome)? { get }   // leaf action; nil = pure container
    func children() async -> [Item]                     // default: []
}

enum RunOutcome { case dismiss   // close the panel (most launch actions)
                  case stay      // keep panel open (e.g. after a refresh)
                  case pop }     // pop one level (e.g. after creating an item)

struct BasicItem: Item {                            // the one concrete type providers construct
    let id: String
    let title: String
    var subtitle: String? = nil
    var icon: IconToken = .generic
    var keywords: [String] = []
    var run: (() async throws -> RunOutcome)? = nil
    var childrenProvider: () async -> [Item] = { [] }
    func children() async -> [Item] { await childrenProvider() }
}

protocol TrackProvider {
    var section: Int { get }                        // ordering of top-level groups
    func items(for track: Track, store: TrackStore, services: Services) async -> [Item]
}

struct Services {                                   // injected once at launch
    let shell: Shell
    let git: GitInspector
    let hosts: HostResolver
    let chrome: ChromeController
    let iterm: ITermController
    let apps: AppLauncher
    let jiraBaseURL: () -> URL?                      // from settings
}
```

### Async streaming loader
When a track is entered, run all providers concurrently in a `TaskGroup`. Render items as each provider returns; sort by `(section, title)`. Apply a **3 s per-provider timeout** (cancel the task, drop that provider's contribution, surface a toast if it timed out). The slow path is git branch reads — read branches per-repo concurrently inside `RepositoryProvider`. Show a thin loading shimmer row until the first batch arrives; never block the UI.

---

## 5. Providers

Static registry order by `section`:

### `JiraProvider` — section 0
- Reads `[JiraLink]` from `store.value([JiraLink].self, "jira")`. `JiraLink { id: UUID, key: String, urlOverride: URL? }`.
- One item per link: `id = "jira:<key>"`, title = `key`, subtitle = `nil` (no summary in v1), icon `.jira`. `run` = `chrome.focusOrOpen(urlContaining: key, fallback: linkURL)` then `.dismiss`. `linkURL` = `urlOverride ?? jiraBaseURL + key`.
- Trailing creation action: `"Link Jira ticket…"` (icon `.add`) whose `run` pushes an **InputView** (§8) asking for a key or URL; on submit, parse the key (regex `[A-Z][A-Z0-9]+-\d+`), append a `JiraLink`, `setValue` it, return `.pop`.
- **No Jira auth in v1.** Storing the key + opening the browser needs none.

### `RepositoryProvider` — section 1
- `services.git.discoverRepos(in: track.url)` → for each repo a **container** item: `id = "repo:<path>"`, title = repo folder name, subtitle = current branch (e.g. `feature/login`), icon `.repo`. `run = nil`.
- `childrenProvider` builds the action list (all leaves unless noted), each `→ .dismiss`:
  - **Open PR** — only if host recognized → `chrome.openInChrome(prURL)` (§7).
  - **Open CI** — only if host recognized → `chrome.openInChrome(ciURL)`.
  - **Open in Fork** — `apps.open(app: "Fork", path: repo.path)`.
  - **Open in Android Studio** — `apps.open(app: "Android Studio", path: repo.path)`.
  - **Open in VS Code** — `apps.open(app: "Visual Studio Code", path: repo.path)`.
  - **Open Terminal here** — `iterm.openOrCreate(tag: "repo:<path>", cwd: repo.path, command: nil)`.
  - **Open in Finder** — `apps.reveal(repo.path)`.

### `FolderProvider` — section 2
- **Open in Finder** (track.url), **Open Terminal here** (`iterm.openOrCreate(tag: "shell", cwd: track.url, command: nil)`).

### `AgentsProvider` — section 3
Agents run **per track, at the track root, cross-repo** (the settled decision). Each is a find-or-create on a tagged iTerm session:
- **Claude** → `iterm.openOrCreate(tag: "claude", cwd: track.url, command: "claude")`, icon `.claude`.
- **opencode** → `iterm.openOrCreate(tag: "opencode", cwd: track.url, command: "opencode")`, icon `.code`.

### Track-management actions (inside a track, via "Manage track…")
Management lives *inside* the track: `TrackManagementProvider` (last section) appends a **"Manage track…"** container to the track's own page, drilling one level deeper into **Rename…** (InputView → `library.rename`), **Reveal in Finder**, **Archive** / **Unarchive** (depending on location), and **Delete** (with a confirm step). These call `TrackFS`/`TrackLibrary` directly. ("Open" is omitted — you're already in the track.)

Both `↵` and `→` on a track row in the list **enter** the track directly (no intermediate management menu). Creating a track lives at the list level as a **"New track…"** action (always last) → InputView → `library.create` → enter it.

---

## 6 & 7. Services (OS integration — the risky core; build the spike first)

### Shell
```swift
struct Shell {
    @discardableResult func run(_ launchPath: String, _ args: [String], cwd: URL? = nil) throws -> String
    func runAppleScript(_ source: String) throws -> String   // via NSAppleScript; maps errOSAStimeout / -1743 (not authorized)
}
```

### GitInspector
- `discoverRepos(in:)` — `FileManager` depth-limited walk (max depth 4) of the track folder; a directory containing `.git` is a repo; **skip** `.track`, `.git` contents, and any dot-folder; don't descend into a repo once found.
- `branch(of:)` — `git -C <repo> rev-parse --abbrev-ref HEAD` (returns `HEAD` when detached → show short SHA from `git -C <repo> rev-parse --short HEAD`).
- `remote(of:)` — `git -C <repo> remote get-url origin`, then parse:

```swift
struct GitRemote { let host: String; let owner: String; let slug: String
                   var webBase: URL { URL(string: "https://\(host)/\(owner)/\(slug)")! } }
// Parse both forms:
//   git@github.com:owner/repo.git           → host github.com, owner, repo
//   https://github.com/owner/repo(.git)     → same
//   ssh://git@host[:port]/owner/repo.git     → host, owner, repo
// Strip a trailing ".git". Owner may contain a subgroup for GitLab: keep the full path before the last segment.
```

### HostAdapter (URL builders) + HostResolver
v1 builds URLs only — **no `gh`/`glab` dependency.** The protocol leaves room to add a CLI-backed resolver later. PR/CI items only appear when a host is recognized.

```swift
protocol HostAdapter {
    func matches(_ r: GitRemote) -> Bool
    func prURL(_ r: GitRemote, branch: String) -> URL
    func ciURL(_ r: GitRemote, branch: String) -> URL
}
```
URL templates (percent-encode `branch`):
- **GitHub** (`matches`: host == github.com or `*.github.*` enterprise):
  - PR: `https://{host}/{owner}/{slug}/pulls?q=is%3Apr+head%3A{branch}`
  - CI: `https://{host}/{owner}/{slug}/actions?query=branch%3A{branch}`
- **GitLab** (host contains `gitlab`):
  - MR: `https://{host}/{owner}/{slug}/-/merge_requests?scope=all&state=opened&source_branch={branch}`
  - CI: `https://{host}/{owner}/{slug}/-/pipelines?ref={branch}`
- **Bitbucket** (host contains `bitbucket`):
  - PR: `https://bitbucket.org/{owner}/{slug}/pull-requests/?query={branch}`
  - CI: `https://bitbucket.org/{owner}/{slug}/pipelines`
- `HostResolver.adapter(for:)` returns the first matching adapter, else `nil` (→ no PR/CI items).

### ChromeController (verbatim AppleScript — don't let the agent guess)
`focusOrOpen(urlContaining substring:fallback:)` — focuses the first tab whose URL contains `substring`, else opens `fallback` in a new tab; then activates Chrome.
```applescript
tell application "Google Chrome"
    set wins to windows
    repeat with w in wins
        set idx to 0
        repeat with t in tabs of w
            set idx to idx + 1
            if (URL of t) contains "%@" then
                set active tab index of w to idx
                set index of w to 1
                activate
                return "focused"
            end if
        end repeat
    end repeat
    if (count of windows) = 0 then make new window
    tell front window to make new tab with properties {URL:"%@"}
    activate
    return "opened"
end tell
```
`openInChrome(url:)` — same but always: reuse an exact-URL tab if present, else new tab. (Use `focusOrOpen(urlContaining: url.absoluteString, fallback: url)`.) Decision: **Chrome is the target browser.** If Chrome isn't installed, the AppleScript errors → toast "Google Chrome isn't installed" and fall back to `NSWorkspace.shared.open(url)`.

### ITermController (verbatim AppleScript)
Session tag sentinel — keep stable: `«lane:<trackID>:<tag>»`. `openOrCreate(tag:cwd:command:)` finds a session whose name contains the sentinel and selects it; else creates a window, sets the name, `cd`s, and runs `command` (if any).
```applescript
-- SENTINEL = «lane:<uuid>:<tag>»
tell application "iTerm2"
    repeat with w in windows
        repeat with t in tabs of w
            repeat with s in sessions of t
                if name of s contains "%SENTINEL%" then
                    select w
                    tell t to select
                    tell s to select
                    activate
                    return "focused"
                end if
            end repeat
        end repeat
    end repeat
    set newWindow to (create window with default profile)
    tell current session of newWindow
        set name to "%SENTINEL%"
        write text "cd " & quoted form of "%CWD%"
        if "%COMMAND%" is not "" then write text "%COMMAND%"
    end tell
    activate
    return "created"
end tell
```
Note for the implementer: confirm the exact `select`/`create window` verbs against iTerm2's dictionary (Script Editor → Open Dictionary → iTerm2) on the build machine; the forms above are current but the dictionary is the source of truth. The `name`-as-tag approach is chosen because it's the most broadly supported across iTerm versions.

### AppLauncher
```swift
struct AppLauncher {
    func open(app: String, path: URL) // /usr/bin/open -a "<app>" "<path>" ; on failure toast "<app> isn't installed"
    func reveal(_ path: URL)          // NSWorkspace.shared.activateFileViewerSelecting([path])
}
```

### Permissions (TCC)
The first Apple Event to Chrome/iTerm triggers the macOS Automation prompt. Catch AppleScript error `-1743` (not authorized) and show a toast: "Lane needs permission to control Google Chrome. Grant it in System Settings → Privacy & Security → Automation." Provide a Settings button that deep-links there (`x-apple.systempreferences:com.apple.preference.security?Privacy_Automation`). No Accessibility permission is needed anywhere.

---

## 8. UI / UX

### Panel window
- `NSPanel`, styles: `.nonactivatingPanel`, `.borderless`; `level = .floating`; `hidesOnDeactivate = false`; `isMovableByWindowBackground = false`. Background = `NSVisualEffectView` material `.popover`, `state = .active`, corner radius 16, soft shadow.
- Hosts SwiftUI via `NSHostingView`. Fixed width **720**; height grows with content to a **max ~520**, then the list scrolls.
- Global hotkey (default **⌥Space**, user-recordable) toggles visibility. On show: center on the active screen, reset to level 0, clear the query, focus the search field. On hide: tear down transient state.
- Closes on Esc at level 0 and on resign-key (clicking away).

### Navigation & keys
State: `path: [Level]`, `selection: Int`, `query: String`. `Level` holds its items (loaded async) + a back reference.
- `↑`/`↓` move selection (wraps optionally; clamp is fine).
- `Return`: leaf → `await run()` then honor `RunOutcome` (`.dismiss` hides the panel; `.pop` pops; `.stay`). Container → push `children()`. Track row (level 0) → enter track (`library.touch`, push level 1).
- `→`: container → push children; track row → enter the track (same as `↵`).
- `←` / `Esc`: step back one level (`Esc` also cancels input / clears a typed query first); at level 0, `Esc` hides the panel. `Esc` only ever navigates back — it never closes from a deeper level.
- `⌘W`: close the panel from any depth (the explicit "dismiss", as opposed to `Esc`'s step-back).
- `⌘R`: reload the current level. `⌘,`: open Settings.
- Typing filters (see search).

### Search
- Level 0: fuzzy-filter track names.
- Inside a track: **subtree search.** On entering a track, lazily build a flat index of all items and their descendants (depth-first, capped) labeled with their breadcrumb. An empty query shows the current level only; a non-empty query searches the whole subtree so typing "PR" surfaces a nested repo action, shown with its path (e.g. `service-api › Open PR`). Selecting a deep result runs it directly.
- `FuzzyMatcher`: subsequence match over `title + keywords`, scoring contiguous runs and word-boundary hits higher; case-insensitive. Pure Swift, no dependency.

### Creation / input flows
`InputView` is a pushed level containing a single labeled text field + hint, submit on `Return`, cancel on `Esc`. Used by "Link Jira ticket…", "New track…", and "Rename…". Keep it visually identical to a list level (search field morphs into the input) so the keyboard flow never breaks.

### Feedback states
- **Toast:** transient bottom banner inside the panel for action results/errors. Errors are specific and don't apologize ("Google Chrome isn't installed", "Couldn't read this repo — it may have moved"). Auto-dismiss ~2.5 s.
- **Empty states** invite action: list with no tracks → "No tracks yet. Press ⌘N to create one." Track with no items → "Nothing here yet. Link a Jira ticket or drop a repo into this folder."
- **Loading:** shimmer rows until the first provider batch lands.

---

## 9. Visual design (modern, restrained)

Lean on native materials and SF Symbols; spend boldness in exactly one place. **Signature element:** a 2-pt accent **leading rail** on the selected row — a literal "lane." Everything else stays quiet. No gradients, no custom chrome beyond the panel, no decorative numbering.

### Tokens
```
Spacing      4 / 8 / 12 / 16 / 24
Radius       row 8 · panel 16
Row height   44 · Search field 52 · Footer 28
Type         SF Pro Text — title 15 (medium), subtitle 12 (regular, secondary)
             Search 22 (regular)
             SF Mono — branch names & Jira keys (the "data" face); 12, secondary
Color        semantic system colors + Color.accentColor; no hardcoded palette
Selection    background accentColor.opacity(0.14), rounded 8, + 2pt accentColor leading rail
Footer hint  11, tertiary: "↑↓ navigate · ↵ open · esc back"
```
- **Type pairing** is the deliberate choice: SF Pro for prose, SF Mono for anything that's data (branches, ticket keys). Restrained, native, not templated.
- **Breadcrumb** above the list, 12 secondary, `Track › Item › …`; truncates head-first.
- **Motion:** 0.12 s ease on selection movement; panel fades + scales 0.98→1 on show. Respect **Reduce Motion** (cross-fade only). Selection is always visibly the keyboard focus.
- **Dark/Light:** automatic via materials + semantic colors.
- **Copy:** sentence case, active verbs, one job per element, consistent vocabulary (the label that says "Open PR" produces a toast that says "Opened pull request" or a specific error — never vague).

### Icon mapping (`IconToken` → SF Symbol)
```
track folder  folder            jira          tag
repo          chevron.left.forwardslash.chevron.right
open PR       arrow.triangle.pull               CI    checkmark.seal
Fork          arrow.triangle.branch             editor  hammer
finder        folder                            terminal terminal
claude        sparkles                          code    chevron.left.slash.chevron.right
add           plus                              archive archivebox
```

---

## 10. Settings

A small standard window (`⌘,` or status-item menu):
- **Root folder** — folder picker; stored as a path string in `UserDefaults`. First launch with no root → prompt for it before showing the list.
- **Jira base URL** — text field (e.g. `https://yourco.atlassian.net/browse/`); used to build ticket URLs from keys.
- **Hotkey** — `KeyboardShortcuts.Recorder`.
- Link: "Open Automation settings" (deep-link from §7).

---

## 11. Build phases (each independently testable)

0. **Spike / de-risk (do first).** Two throwaway `osascript` files: focus an existing iTerm session by sentinel + create one running `claude`; focus an existing Chrome tab by substring + open a fallback. **Done when** both reliably focus-or-launch by hand.
1. **Scaffold.** Accessory app, Info.plist, no sandbox, SPM `KeyboardShortcuts`, status item (Settings/Quit), hotkey toggles a placeholder panel. **Done when** the hotkey shows/hides a floating panel.
2. **Panel.** `NSPanel` + material + `NSHostingView`, centered, autofocus search, Esc/blur hides. **Done when** it looks and behaves like a launcher shell.
3. **Persistence.** `TrackLibrary` + `TrackStore` + discovery + atomic writes. **Done when** create/list/rename/archive/delete are correct on disk and survive relaunch.
4. **Domain.** `Item`/`BasicItem`, `TrackProvider`, registry, `Services`, streaming loader with timeouts. **Done when** a dummy provider streams items into a level.
5. **Navigation + search UI.** Stack, key handling, fuzzy subtree search, breadcrumb, footer, loading/empty, toast. **Done when** keyboard-only drill-in/out and search across a nested subtree work.
6. **Services.** Shell, GitInspector, HostAdapter(+impls), ChromeController, ITermController, AppLauncher, permission error mapping. **Done when** each service works in isolation against a real repo/app.
7. **Providers.** Folder, Repository(+actions), Jira(+link flow), Agents; track-management actions; New track. **Done when** the acceptance flows below pass.
8. **Settings.** Root picker, Jira base URL, hotkey recorder, automation deep-link.
9. **Visual polish.** Tokens, accent-rail signature, motion + reduce-motion, icon map, copy review.
10. **Hardening.** Per-provider timeouts, atomic writes, external-rename rescan, archive collision suffixing, error toasts, empty states.

### Acceptance flows (definition of done)
- **Open Jira** focuses an already-open ticket tab (substring match), else opens the built URL in Chrome.
- **Claude** focuses the track's existing session, else creates one at the track root running `claude`.
- **Open PR** opens the correct host URL for the repo's current branch; PR/CI are hidden for unrecognized hosts.
- **Archive** moves the folder into `.archive/`; it disappears from the default list and reappears with "include archived."
- **Rename** moves the folder; the track keeps its `id` and `lastOpenedAt`.
- **Search** for a nested action label surfaces and runs it from the track's top level.
- Re-scanning on open reflects folders renamed/added in Finder while the app was idle.

---

## 12. Out of scope (v1)

Clone/checkout-repo action; Jira API auth & summary fetching; cross-provider / generic actions; browsers other than Chrome; runtime plugin loading; cloud sync; Windows/Linux. The architecture leaves room for all of these (new provider, CLI-backed `HostAdapter` resolver, etc.) without disturbing the model.
