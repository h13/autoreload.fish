function __autoreload_source_file -a file
    # Defensive cleanup of pre-state from interrupted previous runs
    __autoreload_clear_pre_state

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
    end

    # Always compute tracking — even if source returned non-zero.
    # Fish's source returns the exit status of the LAST command in the file,
    # not whether sourcing itself succeeded.  Skipping record_diff here would
    # leave side effects permanently untracked.
    if test $do_cleanup = 1
        __autoreload_record_diff $key
    end

    return $source_status
end
