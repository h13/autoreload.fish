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
        command stat -c %Y $file 2>/dev/null | string trim
    end
else
    function __autoreload_mtime -a file
        /usr/bin/stat -f %m $file 2>/dev/null | string trim
    end
end

function __autoreload_debug -a msg
    if set -q autoreload_debug; and test "$autoreload_debug" = 1
        echo "autoreload: [debug] $msg" >&2
    end
end

function __autoreload_snapshot
    set -g __autoreload_files
    set -g __autoreload_mtimes
    set -g __autoreload_self_glob ""

    set -l config_file $__fish_config_dir/config.fish
    if test -f $config_file
        set -a __autoreload_files $config_file
        set -a __autoreload_mtimes (__autoreload_mtime $config_file)
    end

    for file in $__fish_config_dir/conf.d/*.fish
        # exclude self to prevent recursive sourcing
        set -l resolved (builtin realpath $file 2>/dev/null)
        if test "$resolved" = "$__autoreload_self"
            set __autoreload_self_glob $file
            continue
        end
        # skip user-excluded files
        if set -q autoreload_exclude
            set -l basename (string replace -r '.*/' '' $file)
            if contains -- $basename $autoreload_exclude
                continue
            end
        end
        set -a __autoreload_files $file
        set -a __autoreload_mtimes (__autoreload_mtime $file)
    end
end

function autoreload -a cmd -d "autoreload.fish utility command"
    switch "$cmd"
        case status
            echo "autoreload v$__autoreload_version"
            if set -q autoreload_exclude
                echo "excluding: $autoreload_exclude"
            end
            echo "tracking "(count $__autoreload_files)" files:"
            for file in $__autoreload_files
                echo "  "(string replace -r '.*/' '' $file)
            end
        case version
            echo $__autoreload_version
        case '*'
            echo "usage: autoreload <status|version>" >&2
            return 1
    end
end

function __autoreload_check --on-event fish_prompt
    if set -q autoreload_enabled; and test "$autoreload_enabled" = 0
        return
    end

    __autoreload_debug "checking "(count $__autoreload_files)" files"

    set -l changed
    set -l deleted

    # check tracked files for changes or deletion
    for i in (seq (count $__autoreload_files))
        set -l file $__autoreload_files[$i]
        if not test -f $file
            set -a deleted $file
            continue
        end
        set -l current (__autoreload_mtime $file)
        if test "$current" != "$__autoreload_mtimes[$i]"
            set -a changed $file
        end
    end

    # report deleted files and refresh snapshot
    if test (count $deleted) -gt 0
        if not set -q autoreload_quiet; or test "$autoreload_quiet" != 1
            set -l names (string replace -r '.*/' '' $deleted)
            echo "autoreload: "(set_color yellow)"removed"(set_color normal)" $names"
        end
        __autoreload_snapshot
    end

    # detect new files in conf.d
    for file in $__fish_config_dir/conf.d/*.fish
        if test "$file" = "$__autoreload_self_glob"
            continue
        end
        if set -q autoreload_exclude
            set -l basename (string replace -r '.*/' '' $file)
            if contains -- $basename $autoreload_exclude
                continue
            end
        end
        if not contains -- $file $__autoreload_files
            set -a changed $file
        end
    end

    if test (count $changed) -eq 0
        return
    end

    set -l sourced
    for file in $changed
        if source $file 2>/dev/null
            set -a sourced $file
        else
            echo "autoreload: "(set_color red)"error"(set_color normal)" sourcing "(string replace -r '.*/' '' $file) >&2
        end
    end

    if test (count $sourced) -gt 0
        if not set -q autoreload_quiet; or test "$autoreload_quiet" != 1
            set -l names (string replace -r '.*/' '' $sourced)
            echo "autoreload: "(set_color green)"sourced"(set_color normal)" $names"
        end
    end

    __autoreload_snapshot
end

# take initial snapshot
__autoreload_snapshot

# Fisher lifecycle events
function _autoreload_install --on-event autoreload_install
end

function _autoreload_uninstall --on-event autoreload_uninstall
    functions -e __autoreload_mtime
    functions -e __autoreload_debug
    functions -e __autoreload_snapshot
    functions -e autoreload
    functions -e __autoreload_check
    functions -e _autoreload_install
    functions -e _autoreload_uninstall
    set -e __autoreload_version
    set -e __autoreload_self
    set -e __autoreload_self_glob
    set -e __autoreload_files
    set -e __autoreload_mtimes
    set -e autoreload_enabled
    set -e autoreload_quiet
    set -e autoreload_exclude
    set -e autoreload_debug
end
