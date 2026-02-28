# autoreload.fish

> Auto-reload fish config files when they change.

Fish shell only reads `config.fish` and `conf.d/*.fish` at startup. This [Fisher](https://github.com/jorgebucaran/fisher) plugin watches those files and automatically re-sources any that have been modified, so changes take effect in all open shells without restarting.

## Install

```fish
fisher install h13/autoreload.fish
```

## How it works

1. On load, records the modification time of `config.fish` and every file in `conf.d/`.
2. On each prompt (`fish_prompt` event), compares current mtimes against the snapshot.
3. If a file has changed — or a new file has appeared in `conf.d/` — it is `source`d and a message is printed:

```
autoreload: sourced aliases.fish paths.fish
```

The plugin excludes itself from monitoring to prevent recursive sourcing.

## Configuration

| Variable             | Default | Description                    |
|----------------------|---------|--------------------------------|
| `autoreload_enabled` | `1`     | Set to `0` to disable checking |

```fish
# disable autoreload
set -g autoreload_enabled 0
```

## Compatibility

Works on macOS (BSD stat) and Linux (GNU stat) via automatic fallback.

## License

[MIT](LICENSE)
