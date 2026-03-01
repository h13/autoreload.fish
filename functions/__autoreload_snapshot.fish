function __autoreload_snapshot
    set -g __autoreload_files
    set -g __autoreload_mtimes
    set -l _discovered (__autoreload_conf_files)
    if set -q _discovered[1]
        set -l _mtimes (__autoreload_mtime $_discovered)
        if test (count $_mtimes) -eq (count $_discovered)
            set -g __autoreload_files $_discovered
            set -g __autoreload_mtimes $_mtimes
        else
            # Race condition fallback: per-file stat
            for file in $_discovered
                set -l mt (__autoreload_mtime $file)
                if test -n "$mt"
                    set -a __autoreload_files $file
                    set -a __autoreload_mtimes $mt
                end
            end
        end
    end

    # cache conf.d directory mtime for new-file-scan optimization
    set -g __autoreload_conf_d_mtime (__autoreload_mtime $__fish_config_dir/conf.d)
end
