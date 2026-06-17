# Lanes

A keyboard-first macOS launcher for switching between parallel work **lanes**.
Each lane is a folder; inside it live repos and linked Jira tickets, and every
item exposes actions that **focus an existing window or launch a new one**.

## What it does

- **⌥Space** toggles a floating launcher panel (menu-bar accessory app, no Dock
  icon).
- **Level 0** lists your lanes (every visible folder under the configured root).
  `↵` opens a lane, `→` reveals its management menu (Rename / Archive / Delete…),
  `⌘N` creates one, `⌘⇧A` toggles archived lanes.
- **Inside a lane**, providers contribute actions:
  - **Jira** — focus an open ticket tab or open it in Chrome; link new tickets.
  - **Repositories** — per repo: Open PR/CI (host-aware), Fork, Android Studio,
    VS Code, Terminal here, Finder.
  - **Folder** — Finder / Terminal at the lane root.
  - **Agents** — Claude / opencode in a tagged iTerm session at the lane root.
- **Search** is fuzzy and subtree-wide: typing filters the current level, and a
  non-empty query surfaces nested actions with their breadcrumb
  (`service-api › Open PR`).

## Architecture

Four layers (`Lane` → `Item` → `LaneProvider` → `Services`). Persistence is
folder-based: a lane is a directory and its metadata lives in `.lane/`. All
app-managed state for a root sits under `<root>/.lanes/`: archived lanes move to
`.lanes/archive/`, and an optional `.lanes/config/template/` folder seeds the
contents of every newly created (or externally adopted) lane.

## Build & run

```sh
xcodebuild -project lane.xcodeproj -scheme lane -configuration Debug build
```

Requires Xcode 26 / Swift 6, macOS 15+. The single SPM dependency
([KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts))
resolves on first build. The app is unsandboxed (it runs `git` and drives Chrome
/ iTerm via Apple Events); the first such action triggers the macOS Automation
prompt.

On first launch, choose a **root folder** in Settings (⌘,). For development you
can set `LANE_ROOT=/path/to/lanes` to skip the picker.
