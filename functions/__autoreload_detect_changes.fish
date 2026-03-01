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

    # detect config.fish creation (not in conf.d, needs separate check)
    set -l config_file $__fish_config_dir/config.fish
    if test -f $config_file; and not __autoreload_is_excluded $config_file; and not contains -- $config_file $__autoreload_files
        __autoreload_debug "new: config.fish"
        set -a __autoreload_last_changed $config_file
    end

    # detect new files in conf.d only when directory mtime changed
    set -l current_conf_d_mtime (__autoreload_mtime $__fish_config_dir/conf.d)
    if test "$current_conf_d_mtime" != "$__autoreload_conf_d_mtime"
        for file in (__autoreload_conf_files)
            if test "$file" = "$config_file"
                continue
            end
            if not contains -- $file $__autoreload_files
                __autoreload_debug "new: "(__autoreload_basename $file)
                set -a __autoreload_last_changed $file
            end
        end
    end
end
