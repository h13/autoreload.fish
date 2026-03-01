function __autoreload_source_file -a file
    set -l key (__autoreload_key $file)
    set -l do_cleanup 0
    if __autoreload_cleanup_enabled
        set do_cleanup 1
    end

    if test $do_cleanup = 1
        __autoreload_call_teardown $file

        # undo previous tracked state BEFORE source
        if contains -- $key $__autoreload_tracked_keys
            __autoreload_debug "undoing previous state for $key"
            __autoreload_undo $key
        end

        # pre-source snapshot on clean state
        set -g __autoreload_pre_vars (set --global --names)
        set -g __autoreload_pre_funcs (functions --all --names)
        set -g __autoreload_pre_abbrs (abbr --list)
        set -g __autoreload_pre_paths $PATH
    end

    source $file
    set -l source_status $status
    if test $source_status -ne 0
        echo "autoreload: "(set_color yellow)"warning"(set_color normal)" sourcing "(__autoreload_basename $file)" exited with status $source_status" >&2
        set -e __autoreload_pre_vars
        set -e __autoreload_pre_funcs
        set -e __autoreload_pre_abbrs
        set -e __autoreload_pre_paths
        return $source_status
    end

    # source succeeded — compute new tracking
    if test $do_cleanup = 1
        __autoreload_record_diff $key
    end

    return 0
end
