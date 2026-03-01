function __autoreload_run_check
    if set -q autoreload_enabled; and test "$autoreload_enabled" = 0
        return
    end
    if __autoreload_is_debug
        __autoreload_debug "checking "(count $__autoreload_files)" files"
    end
    __autoreload_detect_changes
    if test (count $__autoreload_last_deleted) -eq 0; and test (count $__autoreload_last_changed) -eq 0
        return
    end
    if test (count $__autoreload_last_deleted) -gt 0
        __autoreload_handle_deleted $__autoreload_last_deleted
    end
    if test (count $__autoreload_last_changed) -gt 0
        __autoreload_handle_changed $__autoreload_last_changed
    end
    __autoreload_snapshot
end
