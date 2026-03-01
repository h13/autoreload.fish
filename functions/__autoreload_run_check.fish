function __autoreload_run_check
    if set -q autoreload_enabled; and test "$autoreload_enabled" = 0
        return
    end
    if __autoreload_is_debug
        __autoreload_debug "checking "(count $__autoreload_files)" files"
    end

    set -l _changed
    set -l _deleted

    # check tracked files for changes or deletion
    for i in (seq (count $__autoreload_files))
        set -l file $__autoreload_files[$i]
        if not test -f $file
            set -a _deleted $file
            continue
        end
        set -l current (__autoreload_mtime $file)
        if test -z "$current"
            continue
        end
        if test "$current" != "$__autoreload_mtimes[$i]"
            __autoreload_debug "changed: "(__autoreload_basename $file)
            set -a _changed $file
        end
    end

    # detect config.fish creation (not in conf.d, needs separate check)
    set -l config_file $__fish_config_dir/config.fish
    if test -f $config_file; and not __autoreload_is_excluded $config_file; and not contains -- $config_file $__autoreload_files
        __autoreload_debug "new: config.fish"
        set -a _changed $config_file
    end

    # detect new files in conf.d only when directory mtime changed
    set -l current_conf_d_mtime (__autoreload_mtime $__fish_config_dir/conf.d)
    if test "$current_conf_d_mtime" != "$__autoreload_conf_d_mtime"
        set -g __autoreload_conf_d_mtime $current_conf_d_mtime
        __autoreload_conf_files
        for file in $__autoreload_discovered_files
            if test "$file" = "$config_file"
                continue
            end
            if not contains -- $file $__autoreload_files
                __autoreload_debug "new: "(__autoreload_basename $file)
                set -a _changed $file
            end
        end
    end

    if test (count $_deleted) -eq 0; and test (count $_changed) -eq 0
        return
    end
    if test (count $_deleted) -gt 0
        __autoreload_handle_deleted $_deleted
    end
    if test (count $_changed) -gt 0
        __autoreload_handle_changed $_changed
    end
    __autoreload_snapshot
end
