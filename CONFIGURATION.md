# Configuring Lanes

Everything Lanes stores or reads for a root lives under a single hidden `.lanes/` folder inside that root.
Drop files in the right place and they take effect immediately — there's no settings file to edit and no restart needed.

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
        ├── script-items/    ← custom actions (named <order>---<name>---<icon>.<ext>)
        │   ├── 10---deploy---bolt.fill.sh         … a lane-level action
        │   └── repository/                        … per-repository actions
        │       └── 10---fetch---arrow.clockwise.sh
        └── hooks/           ← lifecycle hooks (fixed names, run in order)
            ├── extract-ticket          … 1. link a ticket from the folder name
            └── update-lane-description … 2. set the description
```

A lane is just a folder.
Its identity, name, and archived state come from where the folder lives; the only persisted metadata is `.lane/lane.json` (a UUID, timestamps, and the optional description).
Archived lanes live under `.lanes/archive/`.

---

## New-lane templates

Anything you put in `.lanes/config/template/` is copied into a lane the first time it becomes a lane — both when you create one with `⌘N` and when Lanes adopts a folder you created outside the app (on the next scan).
Existing files are never overwritten.

Use it for files every lane should start with, e.g. a lane-wide `CLAUDE.md`.

```
.lanes/config/template/
├── CLAUDE.md
└── scratch/
    └── …
```

---

## Custom actions (script-items)

Make a file executable and drop it under `.lanes/config/script-items/` to add a custom action to the launcher.

- **`.lanes/config/script-items/*`** — lane-level actions, shown in a **Scripts** section inside every lane.
  Run with the **lane folder** as the working directory.
- **`.lanes/config/script-items/repository/*`** — per-repository actions, shown inside each discovered repo (next to *Open PR*, …).
  Run once per repo with that **repository's folder** as the working directory.

### Rules

- Only files with the **executable bit** are shown (`chmod +x <file>`).
  The file is executed directly, so its **shebang** picks the interpreter (bash, Python, Node, …).
  Dotfiles and `README*` are ignored.
- The filename follows a three-field format separated by `---`:

  ```
  <order>---<name>---<icon>.<ext>
  ```

  - **`order`** — sort key (e.g. `10`); stripped from the display.
  - **`name`** — shown **verbatim** (dashes/spaces kept).
  - **`icon`** — an [SF Symbol](https://developer.apple.com/sf-symbols/) name (e.g. `bolt.fill`); an invalid name falls back to the scroll glyph.

  So `10---deploy to prod---bolt.fill.sh` shows as **deploy to prod** with the `bolt.fill` icon.
  A file not matching the format shows its whole base name with the scroll icon.

  > Always include an extension (`.sh`, `.py`, …) when the icon name has dots, or the icon's last `.segment` is taken as the extension.
- Scripts run **silently**: on success the panel closes; a **non-zero exit** surfaces the script's stderr as an error toast.

### Environment

Scripts inherit your environment (so `PATH` etc. are intact) plus:

| Variable      | In lane scripts | In `repository/` scripts |
| ------------- | --------------- | ------------------------ |
| `LANE_DIR`    | ✅ lane folder path | ✅ |
| `LANE_NAME`   | ✅ folder name      | ✅ |
| `LANE_ID`     | ✅ lane UUID        | ✅ |
| `TICKET_KEY`  | ✅ primary linked ticket key (e.g. `PROJ-123`) | ✅ |
| `TICKET_URL`  | ✅ that ticket's URL | ✅ |
| `REPO_DIR`    | —               | ✅ repository folder path |
| `REPO_NAME`   | —               | ✅ repository folder name  |

`TICKET_KEY`/`TICKET_URL` describe the lane's **first** linked ticket and are **unset** when the lane has none (guard with `${TICKET_KEY:-}`).
`TICKET_URL` is empty if the ticket has no explicit URL and no base URL is configured in Settings.

### Example

`.lanes/config/script-items/10---open ticket---link.sh` (shows as **open ticket** with the `link` icon):

```sh
#!/usr/bin/env bash
set -euo pipefail
open "${TICKET_URL:?No ticket linked to this lane}"
```

`.lanes/config/script-items/repository/10---fetch---arrow.triangle.2.circlepath.sh` (shows as **fetch** inside each repo):

```sh
#!/usr/bin/env bash
set -euo pipefail
git -C "$REPO_DIR" fetch --all --prune
```

```sh
chmod +x ".lanes/config/script-items/10---open ticket---link.sh"
chmod +x ".lanes/config/script-items/repository/10---fetch---arrow.triangle.2.circlepath.sh"
```

---

## Lane descriptions and directives

Each lane can carry a one-line description, stored in `lane.json`.
In the lane list it's shown **large**, with the folder name smaller beneath it; the search field matches the description as well as the folder name.
Set or edit it from inside a lane (**Manage lane… → Set description…**) or generate it from the `update-lane-description` hook (see below).

A description may embed `{{name:args}}` **directives**.
The first of each kind wins, and every directive is stripped from the displayed (and searched) text.

### `{{badge:color:text}}` — status badge

Renders as a colored pill on the lane row and in the in-lane header.

```
{{badge:green:Ready to ship}} Implements the new auth flow
```

shows a green **Ready to ship** badge with *Implements the new auth flow* as the description.

- **Colors:** `gray`, `blue`, `green`, `yellow`, `orange`, `red`, `purple`, `pink`.
  An unrecognized color falls back to gray.
- Empty text (`{{badge:green:}}` or `{{badge:green}}`) renders as a bare dot.

### `{{refresh:duration}}` — auto-refresh

Marks how often the `update-lane-description` hook should re-run.
When a lane (in the list or open) is shown and that long has passed since the last run, Lanes re-runs the hook in the background and updates the description.
`duration` is `30s` / `30m` / `2h` / `1d` (bare number = seconds).
No-op without the hook; see [Hooks](#hooks).

---

## Hooks

Executable scripts in `.lanes/config/hooks/` run at specific moments.
Both hooks below fire **when a lane is created** and **whenever you press ⌘R** (at the lane list this refreshes every listed lane; inside a lane, just the open one — folders adopted from outside the app catch up on the next ⌘R).
`update-lane-description` also re-runs on its own when its description sets a [`{{refresh:…}}`](#refreshduration--auto-refresh) interval.
Each runs with the **lane folder** as the working directory and the `LANE_DIR` / `LANE_NAME` / `LANE_ID` variables exported.

When both are present they run in a **fixed order**, so a later hook can build on an earlier one:

1. **`extract-ticket`** — links a ticket to the lane.
2. **`update-lane-description`** — sets the description, and additionally gets `TICKET_KEY` / `TICKET_URL` for the lane's primary ticket (so the description can mention the ticket the first hook just linked).

A hook that's missing, not executable, or prints nothing (after trimming) is a no-op and leaves the existing state untouched.

### `extract-ticket`

Its **stdout** (trimmed) is treated as a ticket key and linked to the lane — the same as typing it into **Link ticket…**.
Linking is idempotent by key, so running on every ⌘R never creates duplicates, and manually linked tickets are left alone.
The linked ticket shows in the lane's **Tickets** section and is exported to script-items as `$TICKET_KEY` / `$TICKET_URL`.

This example links a leading issue key derived from the folder name — 2+ uppercase letters, a dash, then digits (e.g. `ABC-1234-add-login` → `ABC-1234`):

```sh
#!/usr/bin/env bash
set -euo pipefail
if [[ "$LANE_NAME" =~ ^[A-Z]{2,}-[0-9]+ ]]; then
  printf '%s' "$BASH_REMATCH"
fi
```

```sh
chmod +x .lanes/config/hooks/extract-ticket
```

### `update-lane-description`

Its **stdout** becomes the lane's description, so it can include any [directive](#lane-descriptions-and-directives) — a `{{badge:…}}` pill and/or a `{{refresh:…}}` interval to keep itself up to date.
It also receives `$TICKET_KEY` / `$TICKET_URL` for the ticket `extract-ticket` linked.

`.lanes/config/hooks/update-lane-description`:

```sh
#!/usr/bin/env bash
set -euo pipefail
cd "$LANE_DIR"
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "no-git")
if git diff --quiet 2>/dev/null; then
  echo "{{refresh:10m}} {{badge:green:clean}} on $branch"
else
  echo "{{refresh:10m}} {{badge:orange:uncommitted changes}} on $branch"
fi
```

```sh
chmod +x .lanes/config/hooks/update-lane-description
```
