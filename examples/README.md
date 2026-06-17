# Examples

Drop-in examples for the per-root `.lanes/config/` configuration surface. See
[../CONFIGURATION.md](../CONFIGURATION.md) for the full reference.

Filenames follow the `<order>---<name>---<icon>.<ext>` convention, so each shows
up with the given name and SF Symbol icon.

## Per-repository actions — `script-items/repository/`

Shown inside each discovered repo, run with the repository folder as the working
directory (`$REPO_DIR`).

| File | Action |
| ---- | ------ |
| `10---Open GitHub Actions---checkmark.seal.sh` | Open the repo's GitHub Actions page for the current branch (replaces the former built-in "Open CI"). |
| `20---Open in Fork---arrow.triangle.branch.sh` | Open the repo in Fork. |
| `30---Open in Android Studio---hammer.sh` | Open the repo in Android Studio. |
| `40---Open in VS Code---chevron.left.slash.chevron.right.sh` | Open the repo in VS Code. |
| `50---Open in Finder---folder.sh` | Reveal the repo in Finder. |

The four launchers (Fork / Android Studio / VS Code / Finder) are the
script-item replacements for the former built-in repo actions — edit them to fit
your own toolchain (e.g. swap VS Code for `zed`, Fork for Tower).

## Lane-level actions — `script-items/`

Shown inside every lane, run with the lane folder as the working directory
(`$LANE_DIR`).

| File | Action |
| ---- | ------ |
| `20---Open in Finder---folder.sh` | Reveal the lane folder in Finder (replaces the former built-in). |

## Installing

Copy the files you want into your configured lanes root and keep them
executable:

```sh
ROOT=~/lanes   # your configured root
mkdir -p "$ROOT/.lanes/config/script-items/repository"
cp examples/script-items/repository/*.sh "$ROOT/.lanes/config/script-items/repository/"
cp examples/script-items/*.sh            "$ROOT/.lanes/config/script-items/"
chmod +x "$ROOT/.lanes/config/script-items/repository/"*.sh \
         "$ROOT/.lanes/config/script-items/"*.sh
```
