# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Lanes is a keyboard-first macOS launcher for switching between parallel work "lanes". See `README.md` for the user-facing feature set.

Note: the app/product is named **Lanes** (`PRODUCT_NAME = Lanes`), so the built bundle is `Lanes.app` and the binary is `Lanes`. The Xcode target, scheme, project file (`lane.xcodeproj`) and source folder (`lane/`) keep the internal name `lane`, and the bundle id stays `at.xa1.lane`.

## Build & run

```sh
# Build. The -derivedDataPath is REQUIRED: xcodebuild's build daemon cannot
# write to the default ~/Library/Developer/Xcode/DerivedData location under the
# command sandbox (fails even in $TMPDIR), so point it into the repo.
xcodebuild -project lane.xcodeproj -scheme lane -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath ./.build \
  -clonedSourcePackagesDirPath ./.build/spm build

# Run the built app (it's an LSUIElement accessory: NO Dock icon, NO window on
# launch — it adds a menu-bar item + the ⌥Space hotkey). Useful env overrides:
#   LANE_ROOT=/path/to/lanes   skip the Settings root picker
#   LANE_AUTOSHOW=1             show the panel immediately (headless smoke test)
LANE_ROOT=/tmp/lanes LANE_AUTOSHOW=1 ./.build/Build/Products/Debug/Lanes.app/Contents/MacOS/Lanes
```

`xcodebuild` needs the sandbox disabled (its daemon writes outside any allowed path). `.build/` is gitignored. The one SPM dependency (KeyboardShortcuts) resolves on first build.

A smoke run under the command sandbox is **safe for the user's prefs**: `UserDefaults` writes (including the `rootPath` that `LANE_ROOT` sets) get redirected into `~/Library/Containers/at.xa1.lane/…`, not the real `~/Library/Preferences/at.xa1.lane.plist`. So `LANE_ROOT` smoke tests never clobber the user's configured root — but it also means you can't read smoke-test prefs back from the real domain.

## Testing

There is **no XCTest target.** Logic is verified with throwaway `swiftc` harnesses compiled against the relevant source files plus a temporary `main.swift`, run against real fixtures (temp dirs, real `git init` repos). Pattern:

```sh
# Build INTO ./.build (not /tmp): under the command sandbox the linker can't
# write /tmp/t ("Operation not permitted"). With @main, put top-level code in a
# file literally named main.swift and pass -parse-as-library; add
# -enable-bare-slash-regex if any compiled file uses /regex/ literals (Xcode
# enables this by default; swiftc does not).
cp /tmp/main.swift ./.build/main.swift
swiftc -parse-as-library -enable-bare-slash-regex -o ./.build/t \
  lane/Model/*.swift lane/Design/Icons.swift lane/Services/*.swift \
  lane/Providers/*.swift lane/Search/*.swift lane/UI/LaneModel.swift \
  ./.build/main.swift && ./.build/t
```

Tests that touch the filesystem (the usual case — `LaneFS.create`, real `git init` fixtures) must **run with the sandbox disabled**; the harness writes lane folders + `.lane/lane.json` into a temp dir. Note `$TMPDIR` resolves differently inside vs outside the sandbox, so compile and run the binary in the same disabled-sandbox step and keep the output in `./.build/`.

This works because the model/service/provider layers are `nonisolated` and UI-free (`LaneModel` imports `Combine`, not `SwiftUI`). Drive end-to-end flows through `LaneModel` with the real `ProviderRegistry.default`. **Async-load timing trap:** an item's `run` closure executes in a detached `Task`, so state doesn't change synchronously after `activateSelected()`/`confirm()`/`drillRight()` — poll before asserting (`model.isInputMode`, `currentLevel?.isLoading == false`, `.indexBuilt == true`, or `breadcrumb.last == <title> && currentLevel?.isLoading == false` for a drill-in). The SwiftUI views, AppleScript controllers (Chrome/iTerm), the global hotkey, and the draggable/positioned panel cannot be tested headlessly — verify those by running the app.

## Project structure mechanics

The Xcode target uses a `PBXFileSystemSynchronizedRootGroup`: **any `.swift` file added under `lane/` is automatically compiled — no `project.pbxproj` edits needed** for new sources. pbxproj surgery is only required for SPM packages or build-setting changes. Folders mirror the layers: `App/ Window/ Model/ Providers/ Services/ Search/ UI/ Design/`.

## Architecture

Four layers, nothing below couples to anything above:

- **Lane** (`Model/`) — a folder is a lane. Identity/name/archived-state are derived from the folder's *location*; only `.lane/lane.json` (UUID + timestamps) + per-provider JSON persist. `LaneFS` holds all pure filesystem ops (create/rename/archive/delete/scan); `LaneLibrary` is the `@MainActor` observable wrapper over it. All of Lanes' own per-root state lives under a single `<root>/.lanes/` dotfolder: archived lanes move to `<root>/.lanes/archive/<name>` (note: no leading dot on `archive` — its `.lanes` parent already hides it), and `<root>/.lanes/config/template/` is an optional folder whose contents seed every new lane. Seeding happens in `LaneFS.loadOrCreateMeta` — the single point where a folder first becomes a lane — so it fires identically whether Lanes created the folder or adopted an externally-made one on scan.
- **Item** (`Model/Item.swift`) — the one universal node. `run` (leaf action) or `children()` (container); `BasicItem` is the only concrete type providers build.
- **LaneProvider** (`Providers/`) — statically registered in `ProviderRegistry.default`, ordered by `section`. Each owns its entire subtree. `ItemLoader` runs them concurrently in a `TaskGroup` with a per-provider 3s timeout, streaming results that `LaneModel` merges by `(section, title)`.
- **Services** (`Services/`) — every side effect (Shell, GitInspector, Host adapters, Chrome/iTerm AppleScript controllers, AppLauncher), injected into providers.

`LaneModel` (`UI/LaneModel.swift`) is the navigation brain: a `stack` of levels (level 0 = lane list is implicit/empty stack), `query`, `selection`. `PanelController` installs a local `NSEvent` key monitor and routes keys into the model (so the search field keeps text input while ↑↓↵→← drive navigation). `AppCore.shared` is the single owner of library/model/panel, shared between `AppDelegate` and the SwiftUI `Settings` scene.

## Critical conventions

- **Actor isolation:** the project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so an unannotated type is implicitly `@MainActor`. Any model/service/provider type used across actor boundaries (everything providers touch) **must** be marked `nonisolated`, or accessing its members from a provider's off-main context becomes an `await`/isolation error. This is the most common build break when adding types here.
- **`RunOutcome` is the action→navigation vocabulary.** A `run` closure returns `.dismiss/.stay/.pop/.popToRoot/.enter(Lane)/.pushInput(InputRequest)/.pushItems(...)`; `LaneModel.honor(_:)` interprets it. This is how creation (New lane, Link Jira) and management (Rename/Archive/Delete/Set description) flows stay inside the uniform Item model instead of needing special-case UI. Creation/management closures call the `Sendable` `LaneFS` layer (not `LaneLibrary`) so they remain `@Sendable`. To reflect an edit to the open lane's own metadata (e.g. the description), return `.enter(updatedLane)` so the header re-reads it — `stack.first.lane` is a value captured at enter time and won't otherwise update.
- **`Item.isSecondary`** demotes "meta" actions (`Link Jira ticket…`, `Manage lane…`) below genuine content in `SubtreeIndex.search`, which sorts primary matches first then secondary, each by fuzzy score. Set it on add/manage-style items so a query like "jira" surfaces real tickets before the link action.
- **Panel show uses `reopen()`, not `reset()`.** `reset()` hard-resets to the lane list; `reopen()` keeps the in-memory navigation stack so the ⌥Space hotkey returns you where you left off (a process restart starts empty = root). `reopen()` refreshes the root list and falls back to `reset()` if the lane you were in vanished on disk.
- **AppleScript lives only in `ChromeController` / `ITermController`** as escaped string templates — treat those scripts as load-bearing and don't paraphrase them. iTerm sessions are tagged by name with the sentinel `«lane:<laneID>:<tag>»`; keep it stable. Error `-1743` maps to `AutomationError.notAuthorized`.
- **No sandbox** (`ENABLE_APP_SANDBOX = NO`) — the app runs `git` and drives other apps via Apple Events. Bundle id `at.xa1.lane` must stay stable (TCC Automation grants are tied to it).
