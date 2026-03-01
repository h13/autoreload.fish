function __autoreload_handle_changed
    set -l changed $argv
    set -l sourced
    set -l failed
    for file in $changed
        if __autoreload_source_file $file
            set -a sourced $file
        else
            set -a failed $file
        end
    end
    if set -q sourced[1]; and not __autoreload_is_quiet
        set -l names (__autoreload_basename $sourced)
        echo "autoreload: "(set_color green)"sourced"(set_color normal)" $names"
    end
    if set -q failed[1]; and not __autoreload_is_quiet
        set -l names (__autoreload_basename $failed)
        echo "autoreload: "(set_color red)"failed"(set_color normal)" $names"
    end
end
