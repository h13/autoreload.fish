function __autoreload_run_check
    if __autoreload_is_disabled
        return
    end
    __autoreload_debug "checking "(count $__autoreload_files)" files"

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

    # Phase 2: batch mtime check — single fork for tracked files + conf.d directory
    set -l _conf_d_dir $__fish_config_dir/conf.d
    set -l _all_mtimes (__autoreload_mtime $_existing $_conf_d_dir)
    set -l _existing_count (count $_existing)
    set -l _expected (math $_existing_count + 1)
    set -l current_conf_d_mtime

    if test (count $_all_mtimes) -eq $_expected
        for i in (seq $_existing_count)
            if test "$_all_mtimes[$i]" != "$_saved[$i]"
                if __autoreload_is_excluded $_existing[$i]
                    continue
                end
                __autoreload_debug "changed: "(__autoreload_basename $_existing[$i])
                set -a _changed $_existing[$i]
            end
        end
        set current_conf_d_mtime $_all_mtimes[-1]
    else
        # Race condition fallback: file vanished between test -f and stat
        __autoreload_debug "stat count mismatch, falling back to per-file check"
        for i in (seq $_existing_count)
            set -l _mt (__autoreload_mtime $_existing[$i])
            if test -n "$_mt"; and test "$_mt" != "$_saved[$i]"
                if __autoreload_is_excluded $_existing[$i]
                    continue
                end
                __autoreload_debug "changed: "(__autoreload_basename $_existing[$i])
                set -a _changed $_existing[$i]
            end
        end
        set current_conf_d_mtime (__autoreload_mtime $_conf_d_dir)
    end

    # detect config.fish creation (not in conf.d, needs separate check)
    set -l config_file $__fish_config_dir/config.fish
    if test -f $config_file; and not __autoreload_is_excluded $config_file; and not contains -- $config_file $__autoreload_files
        __autoreload_debug "new: config.fish"
        set -a _changed $config_file
    end

    # detect new files in conf.d only when directory mtime changed
    if test "$current_conf_d_mtime" != "$__autoreload_conf_d_mtime"
        set -g __autoreload_conf_d_mtime $current_conf_d_mtime
        set -l _discovered (__autoreload_conf_files)
        for file in $_discovered
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
