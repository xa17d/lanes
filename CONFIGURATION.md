# Configuring Lanes

Everything Lanes stores or reads for a root lives under a single hidden
`.lanes/` folder inside that root. Drop files in the right place and they take
effect immediately — there's no settings file to edit and no restart needed.

```
<root>/
├── my-feature/              ← a lane (any visible folder)
│   └── .lane/lane.json      ← per-lane metadata (id, timestamps, description)
├── another-lane/
└── .lanes/                  ← all Lanes-managed state for this root (hidden)
    ├── archive/             ← archived lanes move here
    │   └── old-lane/
    └── config/              ← user configuration (everything below is optional)
        ├── template/        ← seeds the contents of every new lane
        ├── script-items/    ← custom actions
        │   ├── deploy.sh        … a lane-level action
        │   └── repository/      … per-repository actions
        │       └── sync.sh
        └── hooks/           ← lifecycle hooks
            └── update-lane-description
```

A lane is just a folder. Its identity, name, and archived state come from where
the folder lives; the only persisted metadata is `.lane/lane.json` (a UUID,
timestamps, and the optional description). Archived lanes live under
`.lanes/archive/` (the `.lanes` parent already hides them, so the inner folder
is plain `archive`, no dot).

---

## New-lane templates

Anything you put in `.lanes/config/template/` is copied into a lane the first
time it becomes a lane — both when you create one with `⌘N` and when Lanes
adopts a folder you created outside the app (on the next scan). Existing files
are never overwritten.

Use it for files every lane should start with, e.g. a `.gitignore`, a `TODO.md`,
or a `.envrc`.

```
.lanes/config/template/
├── .gitignore
├── TODO.md
└── scratch/
    └── .keep
```

---

## Custom actions (script-items)

Make a file executable and drop it in `script-items/` to add a custom action to
the launcher.

- **`script-items/*`** — lane-level actions, shown in a **Scripts** section
  inside every lane. Run with the **lane folder** as the working directory.
- **`script-items/repository/*`** — per-repository actions, shown inside each
  discovered repo (next to *Open PR*, *Open in VS Code*, …). Run once per repo
  with that **repository's folder** as the working directory.

### Rules

- Only files with the **executable bit** are shown
  (`chmod +x script-items/deploy.sh`). The file is executed directly, so its
  **shebang** chooses the interpreter — bash, zsh, Python, Node, anything.
- Dotfiles and `README*` are ignored.
- The action's **title** is the prettified filename: the `[icon]` token (see
  below) and extension are dropped, a leading ordering prefix is stripped, and
  `-`/`_` become spaces. So `10-deploy-prod.sh` shows as **deploy prod** (and the
  `10-` keeps it ordered).
- The action's **icon** defaults to a scroll. To choose your own, put an
  [SF Symbol](https://developer.apple.com/sf-symbols/) name in square brackets
  anywhere in the filename: `deploy[bolt.fill].sh` shows as **deploy** with the
  `bolt.fill` icon. The brackets delimit the symbol unambiguously (SF Symbol
  names contain dots), so it works with or without a file extension. An invalid
  symbol name falls back to the scroll.
- Scripts run **silently**. On success the panel just closes; on a **non-zero
  exit** the script's stderr is shown as an error toast. (Use a script that
  opens a terminal/app itself if you want to watch long-running output.)

### Environment

Scripts inherit your environment (so `PATH` etc. are intact) plus:

| Variable     | In lane scripts | In `repository/` scripts |
| ------------ | --------------- | ------------------------ |
| `LANE_DIR`   | ✅ lane folder path | ✅ |
| `LANE_NAME`  | ✅ folder name      | ✅ |
| `LANE_ID`    | ✅ lane UUID        | ✅ |
| `REPO_DIR`   | —               | ✅ repository folder path |
| `REPO_NAME`  | —               | ✅ repository folder name  |

### Example

`.lanes/config/script-items/open-jira[link].sh` (shows as **open jira** with the
`link` icon):

```sh
#!/usr/bin/env bash
set -euo pipefail
open "https://jira.example.com/browse/$(basename "$LANE_DIR")"
```

`.lanes/config/script-items/repository/fetch[arrow.triangle.2.circlepath].sh`
(shows as **fetch** inside each repo):

```sh
#!/usr/bin/env bash
set -euo pipefail
git -C "$REPO_DIR" fetch --all --prune
```

```sh
chmod +x ".lanes/config/script-items/open-jira[link].sh"
chmod +x ".lanes/config/script-items/repository/fetch[arrow.triangle.2.circlepath].sh"
```

---

## Lane descriptions and status badges

Each lane can carry a one-line description, stored in `lane.json`. In the lane
list it's shown **large**, with the folder name smaller beneath it; the search
field matches the description as well as the folder name.

Set or edit it from inside a lane: **Manage lane… → Set description…**.

### Status badge

A description may embed a status badge using the syntax `{{color:text}}`. The
first marker becomes a colored pill on the lane row, and every marker is
stripped from the displayed (and searched) description text.

```
{{green:Ready to ship}} Implements the new auth flow
```

renders as a green **Ready to ship** badge with *Implements the new auth flow*
as the description.

- **Colors:** `gray`, `blue`, `green`, `yellow`, `orange`, `red`, `purple`,
  `pink`. An unrecognized color falls back to gray.
- An empty label (`{{green:}}`) renders as a bare colored dot.

---

## Hooks

Executable scripts in `.lanes/config/hooks/` run at specific moments.

### `update-lane-description`

If this hook is executable, its **stdout** becomes the lane's description. It
runs:

- when a lane is **created**, and
- whenever you press **⌘R** (refreshes every listed lane at the lane list, or
  just the open lane). Folders adopted from outside the app pick up their
  description on the next ⌘R.

It runs with the **lane folder** as the working directory and the same
`LANE_DIR` / `LANE_NAME` / `LANE_ID` variables as script-items. Trimmed, empty
output leaves the existing description unchanged. Because the output *is* the
description, it can include a `{{color:text}}` status badge.

`.lanes/config/hooks/update-lane-description`:

```sh
#!/usr/bin/env bash
set -euo pipefail
cd "$LANE_DIR"
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "no-git")
if git diff --quiet 2>/dev/null; then
  echo "{{green:clean}} on $branch"
else
  echo "{{orange:uncommitted changes}} on $branch"
fi
```

```sh
chmod +x .lanes/config/hooks/update-lane-description
```
