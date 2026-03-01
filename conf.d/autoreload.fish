# autoreload.fish — Auto-reload fish config files on change
# https://github.com/h13/autoreload.fish

if not status is-interactive
    exit
end

set -g __autoreload_version 1.2.5
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
    if set -q autoreload_enabled; and test "$autoreload_enabled" = 0
        return
    end

    __autoreload_debug "checking "(count $__autoreload_files)" files"

    set -l changed
    set -l deleted
    __autoreload_detect_changes

    if test (count $deleted) -eq 0; and test (count $changed) -eq 0
        return
    end

    if test (count $deleted) -gt 0
        __autoreload_handle_deleted $deleted
    end

    if test (count $changed) -gt 0
        __autoreload_handle_changed $changed
    end

    __autoreload_snapshot
end

# Fisher lifecycle events
function _autoreload_uninstall --on-event autoreload_uninstall
    for fn in (functions --all --names | string match '__autoreload_*')
        functions -e $fn
    end
    functions -e autoreload
    functions -e _autoreload_uninstall
    for var in (set --global --names | string match '__autoreload_*')
        set -e $var
    end
    set -e autoreload_enabled
    set -e autoreload_quiet
    set -e autoreload_exclude
    set -e autoreload_debug
    set -e autoreload_cleanup
end
