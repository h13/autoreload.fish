function __autoreload_run_check
    if set -q autoreload_enabled; and test "$autoreload_enabled" = 0
        return
    end
    if __autoreload_is_debug
        __autoreload_debug "checking "(count $__autoreload_files)" files"
    end

    set -l _changed
    set -l _deleted

    # Phase 1: separate existing vs deleted files (builtins only, zero forks)
    set -l _existing
    set -l _saved
    for i in (seq (count $__autoreload_files))
        if test -f $__autoreload_files[$i]
            set -a _existing $__autoreload_files[$i]
            set -a _saved $__autoreload_mtimes[$i]
        else
            set -a _deleted $__autoreload_files[$i]
        end
    end

    # Phase 2: batch mtime check (single fork for all files)
    if set -q _existing[1]
        set -l _current (__autoreload_mtime $_existing)
        if test (count $_current) -eq (count $_existing)
            for i in (seq (count $_existing))
                if test "$_current[$i]" != "$_saved[$i]"
                    __autoreload_debug "changed: "(__autoreload_basename $_existing[$i])
                    set -a _changed $_existing[$i]
                end
            end
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

    if not set -q _deleted[1]; and not set -q _changed[1]
        return
    end
    if set -q _deleted[1]
        __autoreload_handle_deleted $_deleted
    end
    if set -q _changed[1]
        __autoreload_handle_changed $_changed
    end
    __autoreload_snapshot
end
