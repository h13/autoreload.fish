function __autoreload_cleanup_all
    for fn in (string match '__autoreload_*' (functions --all --names))
        functions -e $fn
    end
    functions -e autoreload
    for var in (string match '__autoreload_*' (set --global --names))
        set -e $var
    end
    for var in autoreload_enabled autoreload_quiet autoreload_exclude autoreload_debug autoreload_cleanup
        set -eg $var
        set -eU $var
    end
end
