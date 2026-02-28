# autoreload.fish

[![CI](https://github.com/h13/autoreload.fish/actions/workflows/ci.yml/badge.svg)](https://github.com/h13/autoreload.fish/actions/workflows/ci.yml)

> Auto-reload fish config files when they change.

Fish shell only reads `config.fish` and `conf.d/*.fish` at startup. This [Fisher](https://github.com/jorgebucaran/fisher) plugin watches those files and automatically re-sources any that have been modified, so changes take effect in all open shells without restarting.

## Install

```fish
fisher install h13/autoreload.fish
```

## How it works

1. On load, records the modification time of `config.fish` and every file in `conf.d/`.
2. On each prompt (`fish_prompt` event), compares current mtimes against the snapshot.
3. If a file has changed, a new file has appeared in `conf.d/`, or `config.fish` has been created — it is `source`d and a message is printed:

```
autoreload: sourced aliases.fish paths.fish
```

The plugin excludes itself from monitoring to prevent recursive sourcing. Fisher installs plugins via symlinks, so the plugin resolves its real path with `builtin realpath` to correctly identify and skip itself regardless of the symlink name.

## Configuration

| Variable              | Default | Description                                    |
|-----------------------|---------|------------------------------------------------|
| `autoreload_enabled`  | `1`     | Set to `0` to disable checking                 |
| `autoreload_quiet`    | (unset) | Set to `1` to suppress sourced/removed messages |
| `autoreload_exclude`  | (unset) | List of basenames to skip from monitoring       |
| `autoreload_debug`    | (unset) | Set to `1` to print debug diagnostics           |

```fish
# disable autoreload
set -g autoreload_enabled 0

# silent mode — still reloads, but no messages
set -g autoreload_quiet 1

# exclude specific files from monitoring
set -g autoreload_exclude my_heavy_plugin.fish another.fish

# enable debug output
set -g autoreload_debug 1
```

## Commands

```fish
autoreload status   # show tracked files and configuration
autoreload version  # print version number
autoreload reset    # refresh file tracking snapshot
```

## Debug mode

When troubleshooting, enable debug mode to see what autoreload is doing:

```fish
set -g autoreload_debug 1
```

Each prompt will print tracking info to stderr:

```
autoreload: [debug] checking 5 files
autoreload: [debug] changed: aliases.fish
autoreload: [debug] new: newplugin.fish
autoreload: [debug] deleted: old.fish
```

Disable with `set -e autoreload_debug`.

## Uninstall

```fish
fisher remove h13/autoreload.fish
```

This removes all functions and variables via the `autoreload_uninstall` event.

## Limitations

- Detection runs on each prompt — changes are picked up after you press Enter, not in real time.
- Only monitors `config.fish` and `conf.d/*.fish`. Files sourced indirectly (e.g., from `functions/`) are not tracked.
- If a sourced file has a syntax error, an error message is printed but the file is skipped.

## Compatibility

Works on macOS (BSD stat) and Linux (GNU stat) via automatic fallback.

## License

[MIT](LICENSE)
