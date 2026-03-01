function __autoreload_show_status
    echo "autoreload v$__autoreload_version"
    set -l flags
    if __autoreload_is_disabled
        set -a flags disabled
    end
    if __autoreload_is_quiet
        set -a flags quiet
    end
    if __autoreload_is_debug
        set -a flags debug
    end
    if __autoreload_cleanup_enabled
        set -a flags cleanup
    end
    if test (count $flags) -gt 0
        echo "flags: "(string join ", " $flags)
    end
    if set -q autoreload_exclude
        echo "excluding: $autoreload_exclude"
    end
    echo "tracking "(count $__autoreload_files)" files:"
    for file in $__autoreload_files
        echo "  "(__autoreload_basename $file)
    end
    if __autoreload_cleanup_enabled; and test (count $__autoreload_tracked_keys) -gt 0
        echo "cleanup tracking "(count $__autoreload_tracked_keys)" files:"
        for key in $__autoreload_tracked_keys
            set -l _details
            for _cat in vars funcs abbrs paths
                set -l _track __autoreload_added_{$_cat}_$key
                set -l _count (count $$_track)
                if test $_count -gt 0
                    set -a _details "$_cat=$_count"
                end
            end
            echo "  "(string unescape --style=var $key)": "(string join ", " $_details)
        end
    end
end
