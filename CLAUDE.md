# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Lane is a keyboard-first macOS launcher for switching between parallel work "tracks". See `README.md` for the user-facing feature set and `PLAN.md` for the complete design spec (every architectural decision is resolved there — consult it before changing behavior).

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
#   LANE_ROOT=/path/to/tracks   skip the Settings root picker
#   LANE_AUTOSHOW=1             show the panel immediately (headless smoke test)
LANE_ROOT=/tmp/tracks LANE_AUTOSHOW=1 ./.build/Build/Products/Debug/lane.app/Contents/MacOS/lane
```

`xcodebuild` needs the sandbox disabled (its daemon writes outside any allowed path). `.build/` is gitignored. The one SPM dependency (KeyboardShortcuts) resolves on first build.

## Testing

There is **no XCTest target.** Logic is verified with throwaway `swiftc` harnesses compiled against the relevant source files plus a temporary `main.swift`, run against real fixtures (temp dirs, real `git init` repos). Pattern:

```sh
# Multi-file compiles need top-level code in a file literally named main.swift.
# Add -parse-as-library when using @main, and -enable-bare-slash-regex if any
# compiled file uses /regex/ literals (Xcode enables this by default; swiftc
# does not).
swiftc -parse-as-library -enable-bare-slash-regex -o /tmp/t \
  lane/Model/*.swift lane/Design/Icons.swift lane/Services/*.swift \
  lane/Providers/*.swift lane/Search/*.swift lane/UI/LaneModel.swift \
  /tmp/main.swift && /tmp/t
```

This works because the model/service/provider layers are `nonisolated` and UI-free (`LaneModel` imports `Combine`, not `SwiftUI`). Drive end-to-end flows through `LaneModel` with the real `ProviderRegistry.default`; for async loads, poll `model.currentLevel?.isLoading == false` / `.indexBuilt == true`. The SwiftUI views, AppleScript controllers (Chrome/iTerm), and the global hotkey cannot be tested headlessly — verify those by running the app.

## Project structure mechanics

The Xcode target uses a `PBXFileSystemSynchronizedRootGroup`: **any `.swift` file added under `lane/` is automatically compiled — no `project.pbxproj` edits needed** for new sources. pbxproj surgery is only required for SPM packages or build-setting changes. Folders mirror the layers: `App/ Window/ Model/ Providers/ Services/ Search/ UI/ Design/`.

## Architecture

Four layers, nothing below couples to anything above (`PLAN.md` §2):

- **Track** (`Model/`) — a folder is a track. Identity/name/archived-state are derived from the folder's *location*; only `.track/track.json` (UUID + timestamps) + per-provider JSON persist. `TrackFS` holds all pure filesystem ops (create/rename/archive/delete/scan); `TrackLibrary` is the `@MainActor` observable wrapper over it. Archived = lives under `.archive/`.
- **Item** (`Model/Item.swift`) — the one universal node. `run` (leaf action) or `children()` (container); `BasicItem` is the only concrete type providers build.
- **TrackProvider** (`Providers/`) — statically registered in `ProviderRegistry.default`, ordered by `section`. Each owns its entire subtree. `ItemLoader` runs them concurrently in a `TaskGroup` with a per-provider 3s timeout, streaming results that `LaneModel` merges by `(section, title)`.
- **Services** (`Services/`) — every side effect (Shell, GitInspector, Host adapters, Chrome/iTerm AppleScript controllers, AppLauncher), injected into providers.

`LaneModel` (`UI/LaneModel.swift`) is the navigation brain: a `stack` of levels (level 0 = track list is implicit/empty stack), `query`, `selection`. `PanelController` installs a local `NSEvent` key monitor and routes keys into the model (so the search field keeps text input while ↑↓↵→← drive navigation). `AppCore.shared` is the single owner of library/model/panel, shared between `AppDelegate` and the SwiftUI `Settings` scene.

## Critical conventions

- **Actor isolation:** the project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so an unannotated type is implicitly `@MainActor`. Any model/service/provider type used across actor boundaries (everything providers touch) **must** be marked `nonisolated`, or accessing its members from a provider's off-main context becomes an `await`/isolation error. This is the most common build break when adding types here.
- **`RunOutcome` is the action→navigation vocabulary.** A `run` closure returns `.dismiss/.stay/.pop/.popToRoot/.enter(Track)/.pushInput(InputRequest)/.pushItems(...)`; `LaneModel.honor(_:)` interprets it. This is how creation (New track, Link Jira) and management (Rename/Archive/Delete) flows stay inside the uniform Item model instead of needing special-case UI. Creation/management closures call the `Sendable` `TrackFS` layer (not `TrackLibrary`) so they remain `@Sendable`.
- **AppleScript is verbatim from `PLAN.md` §7** (`ChromeController`, `ITermController`) with escaped placeholders — don't paraphrase the scripts. iTerm sessions are tagged by name with the sentinel `«lane:<trackID>:<tag>»`; keep it stable. Error `-1743` maps to `AutomationError.notAuthorized`.
- **No sandbox** (`ENABLE_APP_SANDBOX = NO`) — the app runs `git` and drives other apps via Apple Events. Bundle id `at.xa1.lane` must stay stable (TCC Automation grants are tied to it).
