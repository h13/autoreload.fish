function __autoreload_clear_tracking -a key
    for _cat in vars funcs abbrs paths
        set -e __autoreload_added_{$_cat}_$key
    end
    if set -l idx (contains -i -- $key $__autoreload_tracked_keys)
        set -e __autoreload_tracked_keys[$idx]
    end
end
