# Lanes

A keyboard-first macOS launcher for switching between parallel work **lanes**.
Each lane is a folder; inside it live repos and linked tickets, and every
item exposes actions that **focus an existing window or launch a new one**.

## What it does

- **⌥Space** toggles a floating launcher panel (menu-bar accessory app, no Dock
  icon).
- **Level 0** lists your lanes (every visible folder under the configured root),
  each showing its description large with the folder name beneath. `↵` opens a
  lane, `→` reveals its management menu (Rename / Archive / Delete…), `⌘N`
  creates one, `⌘⇧A` toggles archived lanes, `⌘R` refreshes descriptions. Search
  matches both the name and the description. A description can embed a status
  badge with `{{color:text}}` (e.g. `{{green:Ready to ship}}`). If
  `<root>/.lanes/config/hooks/update-lane-description` exists, its output is used
  as a lane's description on creation and on ⌘R.
- **Inside a lane**, providers contribute actions:
  - **Tickets** — focus an open ticket tab or open it in Chrome; link new
    tickets (by key like `PROJ-123` or by pasting a URL). A base URL set in
    Settings turns keys into links.
  - **Repositories** — per repo: Open PR (host-aware) and Open Terminal here
    (tagged iTerm session). The editor/Finder/CI launchers (Fork, Android
    Studio, VS Code, Finder, GitHub Actions) ship as ready-to-use example
    script-items in [`examples/`](examples/) rather than built-ins.
  - **Folder** — Open Terminal here at the lane root (a Finder launcher is an
    example script-item).
  - **Agents** — Claude / opencode in a tagged iTerm session at the lane root.
  - **Scripts** — drop an executable file in `<root>/.lanes/config/script-items/`
    to add a custom lane action (run with the lane dir as cwd); files under
    `script-items/repository/` become per-repo actions (run in the repo dir).
    Scripts run silently with `LANE_DIR`/`LANE_NAME`/`LANE_ID`,
    `TICKET_KEY`/`TICKET_URL` for the lane's primary linked ticket (and
    `REPO_DIR`/`REPO_NAME` for repo scripts) in the environment; stderr from a
    failing script is
    shown as a toast. See [`examples/`](examples/) for drop-in scripts.
- **Search** is fuzzy and subtree-wide: typing filters the current level, and a
  non-empty query surfaces nested actions with their breadcrumb
  (`service-api › Open PR`).

## Configuration

Templates, custom actions (script-items), lane descriptions / status badges, and
lifecycle hooks are all configured by dropping files under `<root>/.lanes/`. See
**[CONFIGURATION.md](CONFIGURATION.md)** for the full reference.

## Architecture

Four layers (`Lane` → `Item` → `LaneProvider` → `Services`). Persistence is
folder-based: a lane is a directory and its metadata lives in `.lane/`. All
app-managed state for a root sits under `<root>/.lanes/`: archived lanes move to
`.lanes/archive/`, and an optional `.lanes/config/template/` folder seeds the
contents of every newly created (or externally adopted) lane.

## Build & run

Requires Xcode 26 / Swift 6, macOS 15+. The single SPM dependency
([KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts))
resolves automatically on first build.

**From Xcode (simplest):** open `Lanes.xcodeproj` and press **⌘R** to build and
run.

**From the command line:**

```sh
# Build
xcodebuild -project Lanes.xcodeproj -scheme Lanes -configuration Debug \
  -derivedDataPath ./.build build

# Launch the built app
open ./.build/Build/Products/Debug/Lanes.app
```

Lanes is a menu-bar accessory app: launching it adds a **menu-bar icon** and
registers the **⌥Space** hotkey — there is **no Dock icon and no window on
launch**. Press ⌥Space to open the launcher panel.

On first launch, choose a **root folder** in Settings (⌘, from the menu-bar
icon) — this is the directory whose subfolders become your lanes. For
development you can set `LANES_ROOT=/path/to/lanes` to skip the picker, and
`LANES_AUTOSHOW=1` to show the panel immediately:

```sh
LANES_ROOT=/path/to/lanes \
  ./.build/Build/Products/Debug/Lanes.app/Contents/MacOS/Lanes
```

The app is unsandboxed (it runs `git` and drives Chrome / iTerm via Apple
Events); the first such action triggers the macOS Automation permission prompt.
