# autoreload.fish — Auto-reload fish config files on change
# https://github.com/h13/autoreload.fish

if not status is-interactive
    exit
end

set -g __autoreload_version 1.2.0
set -g __autoreload_self (builtin realpath (status filename))
if test -z "$__autoreload_self"
    exit
end

if command stat -c %Y /dev/null &>/dev/null
    function __autoreload_mtime -a file
        command stat -c %Y $file 2>/dev/null | string trim
    end
else
    # Use absolute path to avoid conflicts with GNU coreutils stat in PATH
    function __autoreload_mtime -a file
        /usr/bin/stat -f %m $file 2>/dev/null | string trim
    end
end

function __autoreload_is_debug
    set -q autoreload_debug; and test "$autoreload_debug" = 1
end

function __autoreload_debug -a msg
    if __autoreload_is_debug
        echo "autoreload: [debug] $msg" >&2
    end
end

function __autoreload_basename
    string replace -r '.*/' '' $argv
end

function __autoreload_cleanup_enabled
    set -q autoreload_cleanup; and test "$autoreload_cleanup" = 1
end

function __autoreload_key -a file
    __autoreload_basename $file | string escape --style=var
end

function __autoreload_clear_tracking -a key
    set -e __autoreload_added_vars_$key
    set -e __autoreload_added_funcs_$key
    set -e __autoreload_added_abbrs_$key
    set -e __autoreload_added_paths_$key
    if set -l idx (contains -i -- $key $__autoreload_tracked_keys)
        set -e __autoreload_tracked_keys[$idx]
    end
end

function __autoreload_call_teardown -a file
    set -l basename (__autoreload_basename $file)
    set -l name (string replace -r '\.fish$' '' $basename)
    set -l teardown_fn __"$name"_teardown
    if functions -q $teardown_fn
        __autoreload_debug "calling $teardown_fn"
        $teardown_fn
    end
end

function __autoreload_undo -a key
    # undo PATH entries (try fish_user_paths first, then PATH directly)
    set -l varname __autoreload_added_paths_$key
    for p in $$varname
        if set -l idx (contains -i -- $p $fish_user_paths)
            set -e fish_user_paths[$idx]
        else if set -l idx (contains -i -- $p $PATH)
            set -e PATH[$idx]
        end
    end

    # undo abbreviations
    set -l varname __autoreload_added_abbrs_$key
    for name in $$varname
        abbr --erase $name 2>/dev/null
    end

    # undo functions
    set -l varname __autoreload_added_funcs_$key
    for name in $$varname
        functions -e $name 2>/dev/null
    end

    # undo global variables
    set -l varname __autoreload_added_vars_$key
    for name in $$varname
        set -eg $name
    end

    __autoreload_clear_tracking $key
end

function __autoreload_is_excluded -a file
    set -q autoreload_exclude; or return 1
    contains -- (__autoreload_basename $file) $autoreload_exclude
end

function __autoreload_is_quiet
    set -q autoreload_quiet; and test "$autoreload_quiet" = 1
end

function __autoreload_source_file -a file
    set -l key (__autoreload_key $file)

    # undo previous side effects and capture pre-source state
    set -l pre_vars
    set -l pre_funcs
    set -l pre_abbrs
    set -l pre_paths
    if __autoreload_cleanup_enabled
        __autoreload_call_teardown $file
        if contains -- $key $__autoreload_tracked_keys
            __autoreload_debug "undoing previous state for $key"
            __autoreload_undo $key
        end
        set pre_vars (set --global --names)
        set pre_funcs (functions --all --names)
        set pre_abbrs (abbr --list)
        set pre_paths $PATH
    end

    source $file
    set -l source_status $status
    if test $source_status -ne 0
        echo "autoreload: "(set_color red)"error"(set_color normal)" sourcing "(__autoreload_basename $file) >&2
    end

    # compute diff and save tracking data
    if __autoreload_cleanup_enabled
        set -l post_vars (set --global --names)
        set -l post_funcs (functions --all --names)
        set -l post_abbrs (abbr --list)
        set -l post_paths $PATH

        # track new variables (exclude __autoreload_* to avoid self-pollution)
        set -g __autoreload_added_vars_$key
        for name in $post_vars
            if string match -q '__autoreload_*' $name
                continue
            end
            if not contains -- $name $pre_vars
                set -a __autoreload_added_vars_$key $name
            end
        end

        # track new functions
        set -g __autoreload_added_funcs_$key
        for name in $post_funcs
            if string match -q '__autoreload_*' $name
                continue
            end
            if not contains -- $name $pre_funcs
                set -a __autoreload_added_funcs_$key $name
            end
        end

        # track new abbreviations
        set -g __autoreload_added_abbrs_$key
        for name in $post_abbrs
            if not contains -- $name $pre_abbrs
                set -a __autoreload_added_abbrs_$key $name
            end
        end

        # track new PATH entries
        set -g __autoreload_added_paths_$key
        for p in $post_paths
            if not contains -- $p $pre_paths
                set -a __autoreload_added_paths_$key $p
            end
        end

        set -l _vn __autoreload_added_vars_$key
        set -l _fn __autoreload_added_funcs_$key
        set -l _an __autoreload_added_abbrs_$key
        set -l _pn __autoreload_added_paths_$key

        # register key only when there are tracked items
        set -l has_tracked (math (count $$_vn) + (count $$_fn) + (count $$_an) + (count $$_pn))
        if test $has_tracked -gt 0
            if not contains -- $key $__autoreload_tracked_keys
                set -a __autoreload_tracked_keys $key
            end
        end

        __autoreload_debug "tracking $key: vars="(count $$_vn)" funcs="(count $$_fn)" abbrs="(count $$_an)" paths="(count $$_pn)
    end

    return $source_status
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
        set -l resolved (builtin realpath $file 2>/dev/null)
        if test "$resolved" = "$__autoreload_self"
            continue
        end
        # skip user-excluded files
        if __autoreload_is_excluded $file
            __autoreload_debug "excluding: "(__autoreload_basename $file)
            continue
        end
        set -a __autoreload_files $file
        set -a __autoreload_mtimes (__autoreload_mtime $file)
    end
end

function autoreload -a cmd -d "autoreload.fish utility command"
    switch "$cmd"
        case status
            echo "autoreload v$__autoreload_version"
            set -l flags
            if set -q autoreload_enabled; and test "$autoreload_enabled" = 0
                set -a flags disabled
            end
            if __autoreload_is_quiet
                set -a flags quiet
            end
            if __autoreload_is_debug
                set -a flags debug
            end
            if __autoreload_cleanup_enabled
                set -a flags cleanup
            end
            if test (count $flags) -gt 0
                echo "flags: "(string join ", " $flags)
            end
            if set -q autoreload_exclude
                echo "excluding: $autoreload_exclude"
            end
            echo "tracking "(count $__autoreload_files)" files:"
            for file in $__autoreload_files
                echo "  "(__autoreload_basename $file)
            end
            if __autoreload_cleanup_enabled; and test (count $__autoreload_tracked_keys) -gt 0
                echo "cleanup tracking "(count $__autoreload_tracked_keys)" files"
            end
        case reset
            __autoreload_snapshot
            if not __autoreload_is_quiet
                echo "autoreload: snapshot refreshed ("(count $__autoreload_files)" files)"
            end
        case enable
            set -e autoreload_enabled
            if not __autoreload_is_quiet
                echo "autoreload: enabled"
            end
        case disable
            set -g autoreload_enabled 0
            if not __autoreload_is_quiet
                echo "autoreload: disabled"
            end
        case version
            echo $__autoreload_version
        case help ''
            echo "autoreload v$__autoreload_version — auto-reload fish config files on change"
            echo
            echo "Commands:"
            echo "  status   Show tracked files and configuration"
            echo "  reset    Refresh file tracking snapshot"
            echo "  enable   Enable file change detection"
            echo "  disable  Disable file change detection"
            echo "  version  Print version number"
            echo "  help     Show this help message"
            echo
            echo "Variables:"
            echo "  autoreload_enabled   Set to 0 to disable (default: enabled)"
            echo "  autoreload_quiet     Set to 1 to suppress messages"
            echo "  autoreload_exclude   List of basenames to skip"
            echo "  autoreload_debug     Set to 1 for debug output"
            echo "  autoreload_cleanup   Set to 1 to enable state cleanup on re-source"
        case '*'
            echo "autoreload: unknown command '$cmd'" >&2
            echo "Run 'autoreload help' for usage." >&2
            return 1
    end
end

function __autoreload_detect_changes --no-scope-shadowing
    # check tracked files for changes or deletion
    for i in (seq (count $__autoreload_files))
        set -l file $__autoreload_files[$i]
        if not test -f $file
            set -a deleted $file
            continue
        end
        set -l current (__autoreload_mtime $file)
        if test "$current" != "$__autoreload_mtimes[$i]"
            __autoreload_debug "changed: "(__autoreload_basename $file)
            set -a changed $file
        end
    end

    # detect config.fish creation
    set -l config_file $__fish_config_dir/config.fish
    if test -f $config_file; and not contains -- $config_file $__autoreload_files
        __autoreload_debug "new: config.fish"
        set -a changed $config_file
    end

    # detect new files in conf.d
    for file in $__fish_config_dir/conf.d/*.fish
        set -l resolved (builtin realpath $file 2>/dev/null)
        if test "$resolved" = "$__autoreload_self"
            continue
        end
        if __autoreload_is_excluded $file
            __autoreload_debug "excluding: "(__autoreload_basename $file)" (new)"
            continue
        end
        if not contains -- $file $__autoreload_files
            __autoreload_debug "new: "(__autoreload_basename $file)
            set -a changed $file
        end
    end
end

function __autoreload_handle_deleted
    set -l deleted $argv
    __autoreload_debug "deleted: "(__autoreload_basename $deleted)
    if __autoreload_cleanup_enabled
        for file in $deleted
            __autoreload_call_teardown $file
            set -l key (__autoreload_key $file)
            if contains -- $key $__autoreload_tracked_keys
                __autoreload_debug "undoing state for deleted $key"
                __autoreload_undo $key
            end
        end
    end
    if not __autoreload_is_quiet
        set -l names (__autoreload_basename $deleted)
        echo "autoreload: "(set_color yellow)"removed"(set_color normal)" $names"
    end
end

function __autoreload_handle_changed
    set -l changed $argv
    set -l sourced
    for file in $changed
        if __autoreload_source_file $file
            set -a sourced $file
        end
    end
    if test (count $sourced) -gt 0; and not __autoreload_is_quiet
        set -l names (__autoreload_basename $sourced)
        echo "autoreload: "(set_color green)"sourced"(set_color normal)" $names"
    end
end

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

# initialize tracking state
set -g __autoreload_tracked_keys

# take initial snapshot
__autoreload_snapshot

# Fisher lifecycle events
function _autoreload_uninstall --on-event autoreload_uninstall
    # clean up per-file tracking variables
    for key in $__autoreload_tracked_keys
        __autoreload_clear_tracking $key
    end
    # remove all __autoreload_* functions dynamically
    for fn in (functions --all --names | string match '__autoreload_*')
        functions -e $fn
    end
    functions -e autoreload
    functions -e _autoreload_uninstall
    # remove all __autoreload_* variables dynamically
    for var in (set --global --names | string match '__autoreload_*')
        set -e $var
    end
    # remove user-facing configuration variables
    set -e autoreload_enabled
    set -e autoreload_quiet
    set -e autoreload_exclude
    set -e autoreload_debug
    set -e autoreload_cleanup
end
