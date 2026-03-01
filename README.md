# autoreload.fish

[![CI](https://github.com/h13/autoreload.fish/actions/workflows/ci.yml/badge.svg)](https://github.com/h13/autoreload.fish/actions/workflows/ci.yml)
[![Fish Shell](https://img.shields.io/badge/fish-3.1%2B-blue?logo=gnubash&logoColor=white)](https://fishshell.com/)
[![Fisher](https://img.shields.io/badge/fisher-plugin-007ec6?logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAxNiAxNiI+PHRleHQgeD0iMiIgeT0iMTMiIGZvbnQtc2l6ZT0iMTIiPvCfkKA8L3RleHQ+PC9zdmc+)](https://github.com/jorgebucaran/fisher)
[![GitHub release](https://img.shields.io/github/v/release/h13/autoreload.fish?color=green)](https://github.com/h13/autoreload.fish/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-yellow)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey)]()

> Auto-reload fish config files when they change.

Fish shell only reads `config.fish` and `conf.d/*.fish` at startup. This [Fisher](https://github.com/jorgebucaran/fisher) plugin watches those files and automatically re-sources any that have been modified, so changes take effect in all open shells without restarting.

## Requirements

- [Fish shell](https://fishshell.com/) 3.1.0 or later (requires `builtin realpath`, `string escape --style=var`)
- [Fisher](https://github.com/jorgebucaran/fisher) plugin manager

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

| Variable              | Default | Description                                       |
|-----------------------|---------|---------------------------------------------------|
| `autoreload_enabled`  | (unset) | Set to `0` to disable checking                    |
| `autoreload_quiet`    | (unset) | Set to `1` to suppress sourced/removed messages    |
| `autoreload_exclude`  | (unset) | List of basenames to skip from monitoring          |
| `autoreload_debug`    | (unset) | Set to `1` to print debug diagnostics              |
| `autoreload_cleanup`  | (unset) | Set to `1` to enable state cleanup on re-source    |

```fish
# disable autoreload
set -g autoreload_enabled 0

# silent mode — still reloads, but no messages
set -g autoreload_quiet 1

# exclude specific files from monitoring
set -g autoreload_exclude my_heavy_plugin.fish another.fish

# enable debug output
set -g autoreload_debug 1

# enable state cleanup — undo previous side effects before re-sourcing
set -g autoreload_cleanup 1
```

## Commands

```fish
autoreload status   # show tracked files and configuration
autoreload version  # print version number
autoreload reset    # refresh file tracking snapshot
autoreload enable   # enable file change detection
autoreload disable  # disable file change detection
autoreload help     # show help message
```

## State cleanup

By default, autoreload only re-sources changed files — it does not remove side effects from the previous version. For example, if you remove a `fish_add_path` call from `paths.fish`, the old PATH entry persists until the shell is restarted.

Enable state cleanup to automatically undo previous side effects before re-sourcing:

```fish
set -U autoreload_cleanup 1
```

When enabled, autoreload tracks four categories of side effects per file:

| Category       | Tracked via           | Undo method                                       |
|----------------|-----------------------|---------------------------------------------------|
| PATH entries   | `$PATH`               | Remove from `$fish_user_paths`, then `$PATH`       |
| Global vars    | `set --global --names` | `set -eg`                                          |
| Functions      | `functions --all --names` | `functions -e`                                  |
| Abbreviations  | `abbr --list`          | `abbr --erase`                                     |

On each re-source, the plugin takes a snapshot before and after `source`, computes the diff, and stores the additions. On the next change, it undoes those additions before re-sourcing.

When a tracked file is deleted, its side effects are also cleaned up.

### Teardown hooks

For side effects that cannot be automatically tracked (event handlers, keybindings, modifications to existing variables), define a teardown function in your conf.d file:

```fish
# In conf.d/aliases.fish
function __aliases_teardown
    bind --erase \cg
end
```

The function must be named `__<basename_without_extension>_teardown`. It is called before the automatic undo, both on re-source and file deletion.

### Limitations of cleanup

- The first re-source has no baseline — side effects from the initial load are not tracked. Full cleanup starts from the second change onward.
- Changes to existing variable values are not tracked (only new variables). Use a teardown hook if needed.
- Event handlers and keybindings are not automatically tracked. Use teardown hooks.
- Adds ~20ms overhead per changed file (two snapshots + diff). No overhead on unchanged prompts.

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
- If a sourced file has a syntax error, a warning is printed and the file is reported as failed.

## Compatibility

Works on macOS (BSD stat) and Linux (GNU stat) via automatic fallback. CI tests run on Fish 3.x and 4.x across both platforms.

## License

[MIT](LICENSE)
