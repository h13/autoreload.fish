function __autoreload_detect_changes
    set -g __autoreload_last_changed
    set -g __autoreload_last_deleted

    # check tracked files for changes or deletion
    for i in (seq (count $__autoreload_files))
        set -l file $__autoreload_files[$i]
        if not test -f $file
            set -a __autoreload_last_deleted $file
            continue
        end
        set -l current (__autoreload_mtime $file)
        if test -z "$current"
            continue
        end
        if test "$current" != "$__autoreload_mtimes[$i]"
            __autoreload_debug "changed: "(__autoreload_basename $file)
            set -a __autoreload_last_changed $file
        end
    end

    # detect config.fish creation
    set -l config_file $__fish_config_dir/config.fish
    if test -f $config_file; and not __autoreload_is_excluded $config_file; and not contains -- $config_file $__autoreload_files
        __autoreload_debug "new: config.fish"
        set -a __autoreload_last_changed $config_file
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
            set -a __autoreload_last_changed $file
        end
    end
end
