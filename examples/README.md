# Examples

Drop-in examples for the per-root `.lanes/config/` configuration surface.
See [../CONFIGURATION.md](../CONFIGURATION.md) for the full reference.

Filenames follow the `<order>---<name>---<icon>.<ext>` convention, so each shows up with the given name and SF Symbol icon.

## Per-repository actions — `script-items/repository/`

Shown inside each discovered repo, run with the repository folder as the working directory (`$REPO_DIR`).

| File | Action |
| ---- | ------ |
| `05---Open PR---arrow.triangle.pull.sh` | Focus the Chrome tab for this branch's pull/merge request page (GitHub/GitLab/Bitbucket), or open it. Replaces the former built-in "Open PR". |
| `10---Open GitHub Actions---checkmark.seal.sh` | Open the repo's GitHub Actions page for the current branch (replaces the former built-in "Open CI"). |
| `15---Open Terminal here---terminal.sh` | Focus this repo's tagged iTerm2 session (cwd = repo dir), or create one. Replaces the former built-in per-repo "Open Terminal here". |
| `20---Open in Fork---arrow.triangle.branch.sh` | Open the repo in Fork. |
| `30---Open in Android Studio---hammer.sh` | Open the repo in Android Studio. |
| `40---Open in VS Code---chevron.left.slash.chevron.right.sh` | Open the repo in VS Code. |
| `50---Open in Finder---folder.sh` | Reveal the repo in Finder. |

These are the script-item replacements for the former built-in repo actions — edit them to fit your own toolchain (e.g. swap VS Code for `zed`, Fork for Tower).

## Lane-level actions — `script-items/`

Shown inside every lane, run with the lane folder as the working directory (`$LANE_DIR`).

| File | Action |
| ---- | ------ |
| `10---Open Terminal here---terminal.sh` | Focus this lane's tagged iTerm2 session (cwd = lane dir), or create one. Replaces the former built-in "Open Terminal here". |
| `20---Open in Finder---folder.sh` | Reveal the lane folder in Finder (replaces the former built-in). |
| `30---Claude---sparkles.sh` | Run the Claude agent in this lane's tagged iTerm2 session at the lane root. Replaces the former built-in Agents › Claude. |
| `40---opencode---chevron.left.slash.chevron.right.sh` | Run the opencode agent in this lane's tagged iTerm2 session at the lane root. Replaces the former built-in Agents › opencode. |

*Open PR*, *Open Terminal here*, *Claude*, and *opencode* drive Chrome/iTerm2 via `osascript`; because Lanes spawns the script, those Apple Events reuse Lanes' Automation permission (no extra prompt).

## Lifecycle hooks — `hooks/`

Run when a lane is created and on ⌘R, with the lane folder as the working directory.
When both are present they fire in order — `extract-ticket` first, then `update-lane-description` (which then sees `$TICKET_KEY` / `$TICKET_URL`).
`update-lane-description` also re-runs on its own `{{refresh:…}}` interval.
See [../CONFIGURATION.md](../CONFIGURATION.md#hooks) for the full reference.

| File | Hook |
| ---- | ---- |
| `extract-ticket` | Link a ticket whose key is the leading `ABC-1234`-style prefix of the folder name (2+ uppercase letters, dash, digits). Prints nothing — links nothing — when the name doesn't match. |
| `update-lane-description` | Set the description to the lane's git working-tree status with a `{{badge:…}}` pill, and `{{refresh:10m}}` so it re-runs every 10 minutes when shown. |

## Installing

Copy the files you want into your configured lanes root and keep them executable:

```sh
ROOT=~/lanes   # your configured root
mkdir -p "$ROOT/.lanes/config/script-items/repository" "$ROOT/.lanes/config/hooks"
cp examples/script-items/repository/*.sh "$ROOT/.lanes/config/script-items/repository/"
cp examples/script-items/*.sh            "$ROOT/.lanes/config/script-items/"
cp examples/hooks/*                      "$ROOT/.lanes/config/hooks/"
chmod +x "$ROOT/.lanes/config/script-items/repository/"*.sh \
         "$ROOT/.lanes/config/script-items/"*.sh \
         "$ROOT/.lanes/config/hooks/"*
```
