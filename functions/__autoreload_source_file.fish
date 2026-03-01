function __autoreload_source_file -a file
    set -l key (__autoreload_key $file)
    set -l do_cleanup 0
    if __autoreload_cleanup_enabled
        set do_cleanup 1
    end

    # capture pre-source state (before source, before undo)
    set -l pre_vars
    set -l pre_funcs
    set -l pre_abbrs
    set -l pre_paths
    if test $do_cleanup = 1
        __autoreload_call_teardown $file
        set pre_vars (set --global --names)
        set pre_funcs (functions --all --names)
        set pre_abbrs (abbr --list)
        set pre_paths $PATH
    end

    source $file
    set -l source_status $status
    if test $source_status -ne 0
        echo "autoreload: "(set_color yellow)"warning"(set_color normal)" sourcing "(__autoreload_basename $file)" exited with status $source_status" >&2
        return $source_status
    end

    # source succeeded — undo old state, then compute new tracking
    if test $do_cleanup = 1
        if contains -- $key $__autoreload_tracked_keys
            __autoreload_debug "undoing previous state for $key"
            __autoreload_undo $key
        end

        # post-undo snapshot captures only what source added
        set -l post_vars (set --global --names)
        set -l post_funcs (functions --all --names)
        set -l post_abbrs (abbr --list)
        set -l post_paths $PATH

        set -l _has_tracked 0
        set -l _debug_parts
        for _cat in vars funcs abbrs paths
            set -l _pre pre_$_cat
            set -l _post post_$_cat
            set -l _track __autoreload_added_{$_cat}_$key
            set -g $_track
            for item in $$_post
                # exclude autoreload internals from vars and funcs tracking
                if contains -- $_cat vars funcs
                    if string match -q '__autoreload_*' $item
                        continue
                    end
                end
                if not contains -- $item $$_pre
                    set -a $_track $item
                end
            end
            set -l _count (count $$_track)
            set _has_tracked (math $_has_tracked + $_count)
            set -a _debug_parts "$_cat=$_count"
        end

        # register key only when there are tracked items
        if test $_has_tracked -gt 0
            if not contains -- $key $__autoreload_tracked_keys
                set -a __autoreload_tracked_keys $key
            end
        else
            # clean up empty tracking variables to avoid orphans
            for _cat in vars funcs abbrs paths
                set -e __autoreload_added_{$_cat}_$key
            end
        end

        __autoreload_debug "tracking $key: "(string join " " $_debug_parts)
    end

    return 0
end
