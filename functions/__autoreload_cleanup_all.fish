function __autoreload_cleanup_all
    for fn in (functions --all --names | string match '__autoreload_*')
        functions -e $fn
    end
    functions -e autoreload
    for var in (set --global --names | string match '__autoreload_*')
        set -e $var
    end
    set -e autoreload_enabled
    set -e autoreload_quiet
    set -e autoreload_exclude
    set -e autoreload_debug
    set -e autoreload_cleanup
end
