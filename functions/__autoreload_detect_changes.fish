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

    # detect new files (not yet in tracked list)
    for file in (__autoreload_conf_files)
        if not contains -- $file $__autoreload_files
            __autoreload_debug "new: "(__autoreload_basename $file)
            set -a __autoreload_last_changed $file
        end
    end
end
