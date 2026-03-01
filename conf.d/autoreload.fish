# autoreload.fish — Auto-reload fish config files on change
# https://github.com/h13/autoreload.fish

if not status is-interactive
    exit
end

set -g __autoreload_version 1.8.0
set -g __autoreload_self (builtin realpath (status filename))
if test -z "$__autoreload_self"
    exit
end

# initialize tracking state
set -g __autoreload_tracked_keys

# take initial snapshot (triggers autoload of __autoreload_snapshot)
__autoreload_snapshot

# Event-bound functions — must be in conf.d (fish does not autoload event handlers)
function __autoreload_check --on-event fish_prompt
    __autoreload_run_check
end

# Fisher lifecycle events
function _autoreload_uninstall --on-event autoreload_uninstall
    __autoreload_cleanup_all
    functions -e _autoreload_uninstall
end
