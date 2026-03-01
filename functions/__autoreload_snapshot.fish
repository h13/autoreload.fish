function __autoreload_snapshot
    set -g __autoreload_files
    set -g __autoreload_mtimes
    __autoreload_conf_files
    for file in $__autoreload_discovered_files
        set -l mt (__autoreload_mtime $file)
        if test -n "$mt"
            set -a __autoreload_files $file
            set -a __autoreload_mtimes $mt
        end
    end

    # cache conf.d directory mtime for new-file-scan optimization
    set -g __autoreload_conf_d_mtime (__autoreload_mtime $__fish_config_dir/conf.d)
end
