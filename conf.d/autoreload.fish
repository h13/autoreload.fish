# autoreload.fish — Auto-reload fish config files on change
# https://github.com/h13/autoreload.fish

if not status is-interactive
    exit
end

set -g __autoreload_version 1.0.0
set -g __autoreload_self (builtin realpath (status filename))
if test -z "$__autoreload_self"
    exit
end

if command stat -c %Y /dev/null &>/dev/null
    function __autoreload_mtime -a file
        command stat -c %Y $file 2>/dev/null
    end
else
    function __autoreload_mtime -a file
        /usr/bin/stat -f %m $file 2>/dev/null
    end
end

function __autoreload_snapshot
    set -g __autoreload_files
    set -g __autoreload_mtimes

    set -l config_file $__fish_config_dir/config.fish
    if test -f $config_file
        set -a __autoreload_files $config_file
        set -a __autoreload_mtimes (__autoreload_mtime $config_file)
    end

    for file in $__fish_config_dir/conf.d/*.fish
        # exclude self to prevent recursive sourcing
        if test (builtin realpath $file) = $__autoreload_self
            continue
        end
        set -a __autoreload_files $file
        set -a __autoreload_mtimes (__autoreload_mtime $file)
    end
end

function __autoreload_check --on-event fish_prompt
    if set -q autoreload_enabled; and test "$autoreload_enabled" = 0
        return
    end

    set -l changed

    # check tracked files for changes
    for i in (seq (count $__autoreload_files))
        set -l file $__autoreload_files[$i]
        if test -f $file
            set -l current (__autoreload_mtime $file)
            if test "$current" != "$__autoreload_mtimes[$i]"
                set -a changed $file
            end
        end
    end

    # detect new files in conf.d
    for file in $__fish_config_dir/conf.d/*.fish
        if test (builtin realpath $file) = $__autoreload_self
            continue
        end
        if not contains -- $file $__autoreload_files
            set -a changed $file
        end
    end

    if test (count $changed) -eq 0
        return
    end

    for file in $changed
        source $file
    end

    set -l names (string replace -r '.*/' '' $changed)
    echo "autoreload: sourced $names"

    __autoreload_snapshot
end

# take initial snapshot
__autoreload_snapshot

# Fisher lifecycle events
function _autoreload_install --on-event autoreload_install
end

function _autoreload_uninstall --on-event autoreload_uninstall
    functions -e __autoreload_mtime
    functions -e __autoreload_snapshot
    functions -e __autoreload_check
    functions -e _autoreload_install
    functions -e _autoreload_uninstall
    set -e __autoreload_version
    set -e __autoreload_self
    set -e __autoreload_files
    set -e __autoreload_mtimes
    set -e autoreload_enabled
end
