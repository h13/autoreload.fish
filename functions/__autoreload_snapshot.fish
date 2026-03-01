function __autoreload_snapshot
    set -g __autoreload_files
    set -g __autoreload_mtimes

    set -l config_file $__fish_config_dir/config.fish
    if test -f $config_file; and not __autoreload_is_excluded $config_file
        set -l mt (__autoreload_mtime $config_file)
        if test -n "$mt"
            set -a __autoreload_files $config_file
            set -a __autoreload_mtimes $mt
        end
    end

    for file in $__fish_config_dir/conf.d/*.fish
        # exclude self to prevent recursive sourcing
        set -l resolved (builtin realpath $file 2>/dev/null)
        if test "$resolved" = "$__autoreload_self"
            continue
        end
        # skip user-excluded files
        if __autoreload_is_excluded $file
            __autoreload_debug "excluding: "(__autoreload_basename $file)
            continue
        end
        set -l mt (__autoreload_mtime $file)
        if test -n "$mt"
            set -a __autoreload_files $file
            set -a __autoreload_mtimes $mt
        end
    end
end
