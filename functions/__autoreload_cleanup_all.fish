function __autoreload_cleanup_all
    for fn in (functions --all --names | string match '__autoreload_*')
        functions -e $fn
    end
    functions -e autoreload
    for var in (set --global --names | string match '__autoreload_*')
        set -e $var
    end
    for var in autoreload_enabled autoreload_quiet autoreload_exclude autoreload_debug autoreload_cleanup
        set -eg $var
        set -eU $var
    end
end
