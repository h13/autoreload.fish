function __autoreload_handle_deleted
    set -l deleted $argv
    __autoreload_debug "deleted: "(string join " " (__autoreload_basename $deleted))
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
