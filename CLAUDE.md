# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Lanes is a keyboard-first macOS launcher for switching between parallel work "lanes".
See `README.md` for the user-facing feature set, and `CONFIGURATION.md` for the user-facing reference on the `<root>/.lanes/` config surface (templates, scripts, descriptions/status badges, hooks, catalogs) — keep that doc in sync when changing any of those behaviors.

Note: the app/product is named **Lanes** (`PRODUCT_NAME = Lanes`), so the built bundle is `Lanes.app` and the binary is `Lanes`.
The Xcode target, scheme, project file (`Lanes.xcodeproj`) and source folder (`Lanes/`) all use the name `Lanes`, and the bundle id is `at.xa1.lanes`.
(The `Lane` type, the `.lane/lane.json` per-lane metadata folder, and the `LANE_DIR`/`LANE_NAME`/`LANE_ID` script env vars refer to the *lane entity*, not the app, and keep the singular `lane`/`LANE_` naming.)

## Documentation conventions

Markdown files use **one sentence per line**: every sentence sits on its own line, and no sentence is wrapped across multiple lines (no mid-sentence line breaks).
This keeps diffs sentence-scoped and easy to review.
Don't reflow prose to a fixed column width.
Code blocks, tables, and the directory diagrams are exempt — leave them as-is.

## Way of working

The user drives this repo by sending tasks.
Process them like this:

- Tasks arrive one at a time, but the user may send several at once — **queue them and process one after the other.**
- For each task: implement → review your own changes → test (build + `swiftc` harness for logic; run the app for UI/AppleScript/hotkey behavior) → iterate until the implementation both looks right and works.
- Then **commit and push directly on `main`** (no PR/branch needed) before moving to the next task.
  End commit messages with the `Co-Authored-By` trailer.

## Build & run

```sh
# Build. The -derivedDataPath is REQUIRED: xcodebuild's build daemon cannot
# write to the default ~/Library/Developer/Xcode/DerivedData location under the
# command sandbox (fails even in $TMPDIR), so point it into the repo.
xcodebuild -project Lanes.xcodeproj -scheme Lanes -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath ./.build \
  -clonedSourcePackagesDirPath ./.build/spm build

# Run the built app (it's an LSUIElement accessory: NO Dock icon, NO window on
# launch — it adds a menu-bar item + the ⌥Space hotkey). Useful env overrides:
#   LANES_ROOT=/path/to/lanes  skip the Settings root picker
#   LANES_AUTOSHOW=1            show the panel immediately (headless smoke test)
LANES_ROOT=/tmp/lanes LANES_AUTOSHOW=1 ./.build/Build/Products/Debug/Lanes.app/Contents/MacOS/Lanes
```

`xcodebuild` needs the sandbox disabled (its daemon writes outside any allowed path).
`.build/` is gitignored.
The one SPM dependency (KeyboardShortcuts) resolves on first build.
Wrappers: `build-and-run.sh` (Debug + launch), `install.sh` (Release → `~/Applications`).

## Testing

There is **no XCTest target.**
Logic is verified with throwaway `swiftc` harnesses compiled against the relevant source files plus a temporary `main.swift`, run against real fixtures (temp dirs, real `git init` repos).
Pattern:

```sh
# Build INTO ./.build (not /tmp): under the command sandbox the linker can't
# write /tmp/t ("Operation not permitted"). With @main, put top-level code in a
# file literally named main.swift and pass -parse-as-library; add
# -enable-bare-slash-regex if any compiled file uses /regex/ literals (Xcode
# enables this by default; swiftc does not).
cp /tmp/main.swift ./.build/main.swift
swiftc -parse-as-library -enable-bare-slash-regex -o ./.build/t \
  Lanes/Model/*.swift Lanes/Design/Icons.swift Lanes/Services/*.swift \
  Lanes/Providers/*.swift Lanes/Search/*.swift Lanes/UI/LaneModel.swift \
  ./.build/main.swift && ./.build/t
```

Tests that touch the filesystem (the usual case — `LaneFS.create`, real `git init` fixtures) must **run with the sandbox disabled**; the harness writes lane folders + `.lane/lane.json` into a temp dir.
Note `$TMPDIR` resolves differently inside vs outside the sandbox, so compile and run the binary in the same disabled-sandbox step and keep the output in `./.build/`.

This works because the model/service/provider layers are `nonisolated` and UI-free (`LaneModel` imports `Combine`, not `SwiftUI`).
Drive end-to-end flows through `LaneModel` with the real `ProviderRegistry.default`.
**Async-load timing trap:** an item's `run` closure executes in a detached `Task`, so state doesn't change synchronously after `activateSelected()`/`confirm()`/`drillRight()` — poll before asserting (`model.isInputMode`, `currentLevel?.isLoading == false`, `.indexBuilt == true`, or `breadcrumb.last == <title> && currentLevel?.isLoading == false` for a drill-in).
The SwiftUI views, AppleScript controllers (Chrome/iTerm), the global hotkey, and the draggable/positioned panel cannot be tested headlessly — verify those by running the app.

## Project structure mechanics

The Xcode target uses a `PBXFileSystemSynchronizedRootGroup`: **any `.swift` file added under `Lanes/` is automatically compiled — no `project.pbxproj` edits needed** for new sources.
pbxproj surgery is only required for SPM packages or build-setting changes.
Folders mirror the layers: `App/ Window/ Model/ Providers/ Services/ Search/ UI/ Design/`.

## Architecture

Four layers, nothing below couples to anything above:

- **Lane** (`Model/`) — a folder is a lane.
  Identity/name/archived-state are derived from the folder's *location*; only `.lane/lane.json` (UUID + timestamps) + per-provider JSON persist.
  `LaneFS` holds all pure filesystem ops (create/rename/archive/delete/scan); `LaneLibrary` is the `@MainActor` observable wrapper over it.
  All of Lanes' own per-root state lives under a single `<root>/.lanes/` dotfolder: archived lanes move to `<root>/.lanes/archive/<name>` (note: no leading dot on `archive` — its `.lanes` parent already hides it), `<root>/.lanes/catalog/<id>/` holds subscribed catalogs (see below), and `<root>/.lanes/config/` holds optional user config: `template/` (contents seed every new lane), `script/*` (each executable file is a custom lane-level action) and `script/repository/*` (custom per-repo actions), plus `hook/` (lifecycle scripts, currently `update-lane-description`).
  Custom-action filenames use the three-field format `<order>---<icon>---<name>.<ext>` (parsed by `ScriptItems.parse`): icon before name, extension mandatory, so a dotted SF Symbol name can't be confused with the extension.
  Template seeding happens in `LaneFS.loadOrCreateMeta` — the single point where a folder first becomes a lane — so it fires identically whether Lanes created the folder or adopted an externally-made one on scan.
  `LaneFS` exposes the well-known `<root>/.lanes/…` paths (`templateDir`, `templatePointer`, `scriptDir`, `repoScriptDir`, `hookDir`, `catalogDir`, `catalogCheckout`).
- **Catalogs** (`Services/Catalogs.swift`) — git repos of shared config a root subscribes to (managed in Settings).
  Each lives at `<root>/.lanes/catalog/<id>/` as `catalog.json` (`{url, ref, pin, lastFetchedAt, latest}` — `pin` is the applied commit, `latest != pin` means an update is available) plus a `checkout/` git clone (a rebuildable cache; the descriptor is truth).
  Each catalog **item is a folder** holding a payload + a `lanes-item.json` companion (`ItemMeta`: default name/icon + description); hooks nest one level deeper as `hook/<role>/<variant>/` so a catalog can ship multiple variants of a hook.
  Local config references an item folder through a thin `.catalog` **pointer** file (`{catalog, item}`) whose *own* filename supplies the display order/icon/name (seeded from the companion when added via the editor); the pure (no-Shell) resolvers map a pointer to its item folder (`resolveItemFolder`) or the executable inside (`resolveExecutable` — the one exec-bit file that isn't the companion). The payload is "everything in the item folder except `lanes-item.json`".
  Scripts merge plain executables + resolved pointers via `ScriptItems.effectiveScripts`; for the singletons (`hook/<name>`, `template`) a `<name>.catalog` / `template.catalog` **pointer wins** over a local file.
  The git lifecycle (`add`/`fetch`/`apply`/`remove`) is split from resolution so non-Shell callers (template seeding) can still resolve pointers; **fetch never changes the checkout** — only the explicit `apply` advances `pin`; `remove` also deletes every `.catalog` pointer referencing the catalog.
  `add` requires the cloned repo to carry a `lanes-catalog.json` (`{name}`) manifest at its root — the human name shown in Settings instead of the folder id.
  `AppDelegate` fetches stale catalogs in the background (~daily + hourly timer) and shows a menu-bar dot when `Catalogs.anyUpdatesAvailable`; the lane list shows a tappable "Catalog updates available" banner (`LaneModel.catalogUpdatesAvailable`) that opens Settings on the Catalogs pane (`SettingsNavigation` jumps the reused window's pane).
  New users are **auto-subscribed** to the official default catalog (`Catalogs.defaultURL`) the first time a root is configured (`CatalogsModel.seedDefaultIfNeeded`, gated per-root in UserDefaults so removal isn't undone; skipped under `LANES_ROOT`), which also enables a curated starter set via `ConfigEdits.enableStarterSet`; the Catalogs pane's empty state has an "Add the default catalog" button (`CatalogsModel.addDefault`) as the explicit fallback.
- **Script items** (`Providers/ScriptItems.swift`) — turns executable files (and resolved `.catalog` pointers) under `script/` into `BasicItem` actions via `ScriptItems.effectiveScripts`.
  Only files with the executable bit are shown (exec'd directly so the shebang picks the interpreter); dotfiles/`README*` are skipped; a `.catalog` pointer is resolved to (and runs) its catalog target while its *local* filename drives the display.
  Filenames use a fixed three-field format `<order>---<icon>---<name>.<ext>` (parsed by `ScriptItems.parse`): the extension is stripped, then the base is split on `---` — `order` is a sort key (dropped from display), `icon` (before `name`) is an SF Symbol name → `IconToken.custom(...)` (else `.script`), `name` is shown verbatim; icon-before-name + mandatory extension stops a dotted symbol like `bolt.fill` being read as the extension.
  Files not matching the format fall back to the whole base name + scroll icon.
  `RowView` validates a custom symbol via `NSImage(systemSymbolName:)` and falls back to the scroll glyph if it's invalid.
  Scripts run **silently** via `Shell.run` with the lane (or repo) dir as cwd and `LANE_DIR`/`LANE_NAME`/`LANE_ID` (+ `TICKET_KEY`/`TICKET_URL` for the lane's first linked ticket, resolved via `TicketProvider.primaryEnv` and omitted when none is linked; + `REPO_DIR`/`REPO_NAME` for repo scripts) in the environment; a nonzero exit throws and surfaces stderr as an error toast.
  `ScriptItemsProvider` (section 4) contributes the lane-level ones; `RepositoryProvider` appends the `repository/` ones to each repo's actions.
  The launchers — Open PR (Chrome tab-focus), Open Terminal here, the agents (Claude/opencode), and the editor/Finder/CI tools (Fork, Android Studio, VS Code, Finder, GitHub Actions) — are **not** built-in; they ship in the default catalog (`lanes-catalog-default`) as drop-in scripts that reproduce the tagged-iTerm reuse / Chrome tab-focus in plain `osascript` (the Apple Event is sent by a Lanes-spawned child, so it inherits Lanes' Automation grant).
  `RepositoryProvider` therefore contributes only the repo containers (subtitle = branch) whose children are the `repository/` scripts; there is no longer a `FolderProvider` or `AgentsProvider`.
  `AppLauncher.open(app:path:)` is consequently unused by the UI but kept as service API (`reveal` is still used by lane management); `ITermController`/`HostResolver` are likewise unused by providers now but kept as services.
- **Lane description + status** — a lane's `summary` (in `lane.json`) is shown as the big line in the lane list, with the folder name beneath; search matches the description body + badge text too.
  Descriptions carry uniform `{{name:args}}` directives, parsed by the pure `DescriptionMarkup.parse` (which returns `badge` / `refresh` / cleaned `body`): `{{badge:color:text}}` renders as a colored `StatusBadge` (`StatusBadgeView` draws it, in lane-list rows and the in-lane header `RootView.laneSummary`), and `{{refresh:<30s|30m|2h|1d>}}` sets a re-run interval for `update-lane-description`.
  All directives are stripped from the displayed/searched text.
  The `LaneHooks` service runs the `<root>/.lanes/config/hook/` scripts (cwd = lane dir, `LANE_*` env) on lane creation (`LaneActions.newLaneRequest`) and on **⌘R** (`LaneModel.refresh()` → `runLaneHooks()`, off-main for the listed lanes / the open lane); externally-adopted folders catch up on the next ⌘R.
  A single `LaneHooks.apply(to:root:)` runs the hooks in a **fixed order**: (1) `extract-ticket` — its stdout is a ticket key linked to the lane via `TicketProvider.link` (idempotent upsert by key); (2) `update-lane-description` — its stdout becomes the description, run with `TICKET_KEY`/`TICKET_URL` (the lane's primary ticket via `TicketProvider.primaryEnv`) also exported so a description can reference the just-extracted ticket.
  `LaneHooks` carries the ticket `baseURL` (from `services.ticketBaseURL`) to resolve `TICKET_URL`.
  **Auto-refresh:** when a lane's description declares `{{refresh:…}}`, showing it (lane list via `reloadLanes`, an opened lane via `enter`/`reopen`) calls `LaneModel.kickStaleRefresh`, which off-main runs `LaneHooks.refreshIfStale` — it re-runs `update-lane-description` only once the interval has elapsed since the persisted `lastRunAt` (a `RefreshState` under the `description-refresh` store key, written even on empty/failed output to avoid re-run storms).
  An in-memory `refreshingLaneIDs` set guards against duplicate concurrent runs.
- **Item** (`Model/Item.swift`) — the one universal node.
  `run` (leaf action) or `children()` (container); `BasicItem` is the only concrete type providers build.
- **LaneProvider** (`Providers/`) — statically registered in `ProviderRegistry.default`, ordered by `section`.
  Each owns its entire subtree.
  `ItemLoader` runs them concurrently in a `TaskGroup` with a per-provider 3s timeout, streaming results that `LaneModel` merges by `(section, title)`.
- **Services** (`Services/`) — every side effect (Shell, GitInspector, Host adapters, Chrome/iTerm AppleScript controllers, AppLauncher), injected into providers.
  `KeepAwake` (also in `Services/`, so `LaneModel` stays harness-compilable) is a `@MainActor ObservableObject` wrapping a `ProcessInfo` activity (`.idleSystemSleepDisabled`) that prevents idle *system* sleep while active (display may still sleep); owned by `AppCore`, off at launch. Toggled from the menu bar ("Keep system awake", which checks the item + adds a small monochrome `bolt.fill` badge to the status icon) and **⌘K while the panel is open** (`PanelController` → `LaneModel.toggleKeepAwake`); while active, `RootView` shows an informational banner (with a "Turn Off") at any depth. `LaneModel` observes `KeepAwake` so the banner reflects toggles from any source.

`LaneModel` (`UI/LaneModel.swift`) is the navigation brain: a `stack` of levels (level 0 = lane list is implicit/empty stack), `query`, `selection`.
`PanelController` installs a local `NSEvent` key monitor and routes keys into the model (so the search field keeps text input while ↑↓↵→← drive navigation).
`AppCore.shared` is the single owner of library/model/panel, shared between `AppDelegate` and the SwiftUI `Settings` scene.

## Critical conventions

- **Actor isolation:** the project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so an unannotated type is implicitly `@MainActor`.
  Any model/service/provider type used across actor boundaries (everything providers touch) **must** be marked `nonisolated`, or accessing its members from a provider's off-main context becomes an `await`/isolation error.
  This is the most common build break when adding types here.
- **`RunOutcome` is the action→navigation vocabulary.**
  A `run` closure returns `.dismiss/.stay/.pop/.popToRoot/.enter(Lane)/.pushInput(InputRequest)/.pushItems(...)`; `LaneModel.honor(_:)` interprets it.
  This is how creation (New lane, Link ticket) and management (Rename/Archive/Delete/Set description) flows stay inside the uniform Item model instead of needing special-case UI.
  Creation/management closures call the `Sendable` `LaneFS` layer (not `LaneLibrary`) so they remain `@Sendable`.
  To reflect an edit to the open lane's own metadata (e.g. the description), return `.enter(updatedLane)` so the header re-reads it — `stack.first.lane` is a value captured at enter time and won't otherwise update.
- **`Item.isSecondary`** demotes "meta" actions (`Link ticket…`, `Manage lane…`) below genuine content in `SubtreeIndex.search`, which sorts primary matches first then secondary, each by fuzzy score.
  Set it on add/manage-style items so a query like "ticket" surfaces real tickets before the link action.
- **Panel show uses `reopen()`, not `reset()`.**
  `reset()` hard-resets to the lane list; `reopen()` keeps the in-memory navigation stack so the ⌥Space hotkey returns you where you left off (a process restart starts empty = root).
  `reopen()` refreshes the root list and falls back to `reset()` if the lane you were in vanished on disk.
- **AppleScript lives only in `ChromeController` / `ITermController`** as escaped string templates — treat those scripts as load-bearing and don't paraphrase them.
  iTerm sessions are tagged by name with the sentinel `«lane:<laneID>:<tag>»`; keep it stable.
  Error `-1743` maps to `AutomationError.notAuthorized`.
- **No sandbox** (`ENABLE_APP_SANDBOX = NO`) — the app runs `git` and drives other apps via Apple Events.
  Bundle id `at.xa1.lanes` must stay stable (TCC Automation grants are tied to it).
