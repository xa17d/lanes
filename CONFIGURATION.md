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
        └── hooks/           ← lifecycle hooks (run in a fixed order)
            ├── extract-ticket          … 1. link a ticket from the folder name
            └── update-lane-description … 2. set the description
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
- The filename follows a fixed three-field format, separated by `---`:

  ```
  <order>---<name>---<icon>.<ext>
  ```

  - **`order`** is a sort key (e.g. `10`, `20`) — it's stripped from the
    displayed name and only controls the order actions appear in.
  - **`name`** is shown **verbatim** — ordinary dashes and spaces are kept, no
    transformation. (`deploy to prod` stays *deploy to prod*.)
  - **`icon`** is an [SF Symbol](https://developer.apple.com/sf-symbols/) name
    (e.g. `bolt.fill`) used as the action's icon. An invalid name falls back to
    the default scroll glyph.

  So `10---deploy to prod---bolt.fill.sh` shows as **deploy to prod** with the
  `bolt.fill` icon, ordered by `10`. A file that doesn't use the format (no
  `---`) just shows its whole base name with the scroll icon.

  > The file extension is removed before parsing, so always include one
  > (`.sh`, `.py`, …) when your icon name contains dots — otherwise the icon's
  > last `.segment` is mistaken for the extension. A script with no extension can
  > still use a single-word icon (`hammer`).
- Scripts run **silently**. On success the panel just closes; on a **non-zero
  exit** the script's stderr is shown as an error toast. (Use a script that
  opens a terminal/app itself if you want to watch long-running output.)

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

`TICKET_KEY`/`TICKET_URL` describe the lane's **first** linked ticket and are
**unset** when the lane has none (guard with `${TICKET_KEY:-}`). `TICKET_URL` is
empty if the ticket has no explicit URL and no base URL is configured in
Settings.

### Example

`.lanes/config/script-items/10---open ticket---link.sh` (shows as **open
ticket** with the `link` icon):

```sh
#!/usr/bin/env bash
set -euo pipefail
open "${TICKET_URL:?No ticket linked to this lane}"
```

`.lanes/config/script-items/repository/10---fetch---arrow.triangle.2.circlepath.sh`
(shows as **fetch** inside each repo):

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

Executable scripts in `.lanes/config/hooks/` run at specific moments. Both hooks
below fire **when a lane is created** and **whenever you press ⌘R** (at the lane
list this refreshes every listed lane; inside a lane, just the open one — folders
adopted from outside the app catch up on the next ⌘R). Each runs with the **lane
folder** as the working directory and the `LANE_DIR` / `LANE_NAME` / `LANE_ID`
variables exported.

When both are present they run in a **fixed order**, so a later hook can build on
an earlier one:

1. **`extract-ticket`** — links a ticket to the lane.
2. **`update-lane-description`** — sets the description, and additionally gets
   `TICKET_KEY` / `TICKET_URL` for the lane's primary ticket (so the description
   can mention the ticket the first hook just linked).

A hook that's missing, not executable, or prints nothing (after trimming) is a
no-op and leaves the existing state untouched.

### `extract-ticket`

Its **stdout** (trimmed) is treated as a ticket key and linked to the lane — the
same as typing it into **Link ticket…**. Linking is idempotent by key, so
running on every ⌘R never creates duplicates, and manually linked tickets are
left alone. The linked ticket shows in the lane's **Tickets** section and is
exported to script-items as `$TICKET_KEY` / `$TICKET_URL`.

This example links a leading issue key derived from the folder name — 2+
uppercase letters, a dash, then digits (e.g. `ABC-1234-add-login` → `ABC-1234`):

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

Its **stdout** becomes the lane's description. Because the output *is* the
description, it can include a `{{color:text}}` status badge. As noted above, it
also receives `$TICKET_KEY` / `$TICKET_URL` for the ticket `extract-ticket`
linked.

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
