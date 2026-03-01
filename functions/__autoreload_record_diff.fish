function __autoreload_record_diff -a key
    # Post-source state snapshot
    set -l post_vars (set --global --names)
    set -l post_funcs (functions --all --names)
    set -l post_abbrs (abbr --list)
    set -l post_paths $PATH

    set -l _has_tracked 0
    set -l _debug_parts

    # Compute set-difference for each category (items in post but not in pre)
    for _cat in vars funcs abbrs paths
        set -l _pre __autoreload_pre_$_cat
        set -l _post post_$_cat
        set -l _track __autoreload_added_{$_cat}_$key
        set -g $_track

        if test $_cat = paths
            # PATH uses count-based diff to correctly detect duplicate entries.
            # Remove each pre-existing entry from a copy; anything left is new.
            set -l _remaining $$_pre
            for item in $$_post
                if set -l idx (contains -i -- $item $_remaining)
                    set -e _remaining[$idx]
                else
                    set -a $_track $item
                end
            end
        else
            for item in $$_post
                # Skip autoreload's own internal state
                if contains -- $_cat vars funcs
                    if string match -q '__autoreload_*' $item
                        continue
                    end
                end
                if not contains -- $item $$_pre
                    set -a $_track $item
                end
            end
        end

        set -l _count (count $$_track)
        set _has_tracked (math $_has_tracked + $_count)
        set -a _debug_parts "$_cat=$_count"
    end

    # Register or clean up tracking
    if test $_has_tracked -gt 0
        if not contains -- $key $__autoreload_tracked_keys
            set -a __autoreload_tracked_keys $key
        end
    else
        # No tracked items — remove empty tracking variables
        for _cat in vars funcs abbrs paths
            set -e __autoreload_added_{$_cat}_$key
        end
    end

    __autoreload_debug "tracking $key: "(string join " " $_debug_parts)
    __autoreload_clear_pre_state
end
