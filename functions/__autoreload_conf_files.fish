function __autoreload_conf_files
    set -l config_file $__fish_config_dir/config.fish
    if test -f $config_file; and not __autoreload_is_excluded $config_file
        echo $config_file
    end
    for file in $__fish_config_dir/conf.d/*.fish
        set -l resolved (builtin realpath $file 2>/dev/null)
        if test "$resolved" = "$__autoreload_self"
            continue
        end
        if __autoreload_is_excluded $file
            __autoreload_debug "excluding: "(__autoreload_basename $file)
            continue
        end
        echo $file
    end
end
