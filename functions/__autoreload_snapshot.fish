function __autoreload_snapshot
    set -g __autoreload_files
    set -g __autoreload_mtimes
    set -l _discovered (__autoreload_conf_files)
    set -l _conf_d_dir $__fish_config_dir/conf.d
    if set -q _discovered[1]
        # Single stat call for discovered files + conf.d directory mtime
        set -l _all_mtimes (__autoreload_mtime $_discovered $_conf_d_dir)
        set -l _expected (math (count $_discovered) + 1)
        if test (count $_all_mtimes) -eq $_expected
            set -g __autoreload_files $_discovered
            set -g __autoreload_mtimes $_all_mtimes[1..-2]
            set -g __autoreload_conf_d_mtime $_all_mtimes[-1]
        else
            # Race condition fallback: per-file stat
            for file in $_discovered
                set -l mt (__autoreload_mtime $file)
                if test -n "$mt"
                    set -a __autoreload_files $file
                    set -a __autoreload_mtimes $mt
                end
            end
            set -g __autoreload_conf_d_mtime (__autoreload_mtime $_conf_d_dir)
        end
    else
        set -g __autoreload_conf_d_mtime (__autoreload_mtime $_conf_d_dir)
    end
end
