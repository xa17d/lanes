# Examples

Drop-in examples for the per-root `.lanes/config/` configuration surface.
See [../CONFIGURATION.md](../CONFIGURATION.md) for the full reference.

Filenames follow the `<order>---<icon>---<name>.<ext>` convention, so each shows up with the given SF Symbol icon and name.

## Per-repository actions — `script/repository/`

Shown inside each discovered repo, run with the repository folder as the working directory (`$REPO_DIR`).

| File | Action |
| ---- | ------ |
| `05---arrow.triangle.pull---Open PR.sh` | Focus the Chrome tab for this branch's pull/merge request page (GitHub/GitLab/Bitbucket), or open it. Replaces the former built-in "Open PR". |
| `10---checkmark.seal---Open GitHub Actions.sh` | Open the repo's GitHub Actions page for the current branch (replaces the former built-in "Open CI"). |
| `15---terminal---Open Terminal here.sh` | Focus this repo's tagged iTerm2 session (cwd = repo dir), or create one. Replaces the former built-in per-repo "Open Terminal here". |
| `20---arrow.triangle.branch---Open in Fork.sh` | Open the repo in Fork. |
| `30---hammer---Open in Android Studio.sh` | Open the repo in Android Studio. |
| `40---chevron.left.slash.chevron.right---Open in VS Code.sh` | Open the repo in VS Code. |
| `50---folder---Open in Finder.sh` | Reveal the repo in Finder. |

These are the script replacements for the former built-in repo actions — edit them to fit your own toolchain (e.g. swap VS Code for `zed`, Fork for Tower).

## Lane-level actions — `script/`

Shown inside every lane, run with the lane folder as the working directory (`$LANE_DIR`).

| File | Action |
| ---- | ------ |
| `10---terminal---Open Terminal here.sh` | Focus this lane's tagged iTerm2 session (cwd = lane dir), or create one. Replaces the former built-in "Open Terminal here". |
| `20---folder---Open in Finder.sh` | Reveal the lane folder in Finder (replaces the former built-in). |
| `30---sparkles---Claude.sh` | Run the Claude agent in this lane's tagged iTerm2 session at the lane root. Replaces the former built-in Agents › Claude. |
| `40---chevron.left.slash.chevron.right---opencode.sh` | Run the opencode agent in this lane's tagged iTerm2 session at the lane root. Replaces the former built-in Agents › opencode. |

*Open PR*, *Open Terminal here*, *Claude*, and *opencode* drive Chrome/iTerm2 via `osascript`; because Lanes spawns the script, those Apple Events reuse Lanes' Automation permission (no extra prompt).

## Lifecycle hooks — `hook/`

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
mkdir -p "$ROOT/.lanes/config/script/repository" "$ROOT/.lanes/config/hook"
cp examples/script/repository/*.sh "$ROOT/.lanes/config/script/repository/"
cp examples/script/*.sh            "$ROOT/.lanes/config/script/"
cp examples/hook/*                 "$ROOT/.lanes/config/hook/"
chmod +x "$ROOT/.lanes/config/script/repository/"*.sh \
         "$ROOT/.lanes/config/script/"*.sh \
         "$ROOT/.lanes/config/hook/"*
```
