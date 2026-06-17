# Examples

Drop-in examples for the per-root `.lanes/config/` configuration surface. See
[../CONFIGURATION.md](../CONFIGURATION.md) for the full reference.

## `script-items/repository/10---Open GitHub Actions---checkmark.seal.sh`

A per-repository action that opens the repo's **GitHub Actions** page for the
current branch — the script-item replacement for the former built-in "Open CI"
action. It reads `origin`, derives the host/owner/repo and branch, and opens the
URL in your default browser.

Install it into your configured lanes root:

```sh
mkdir -p "<root>/.lanes/config/script-items/repository"
cp "examples/script-items/repository/10---Open GitHub Actions---checkmark.seal.sh" \
   "<root>/.lanes/config/script-items/repository/"
chmod +x "<root>/.lanes/config/script-items/repository/10---Open GitHub Actions---checkmark.seal.sh"
```

The filename follows the `<order>---<name>---<icon>.<ext>` convention, so it
shows up as **Open GitHub Actions** with the `checkmark.seal` icon, inside each
repository in a lane.
