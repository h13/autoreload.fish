function __autoreload_snapshot
    set -g __autoreload_files
    set -g __autoreload_mtimes
    for file in (__autoreload_conf_files)
        set -l mt (__autoreload_mtime $file)
        if test -n "$mt"
            set -a __autoreload_files $file
            set -a __autoreload_mtimes $mt
        end
    end
end
