function __autoreload_cleanup_enabled
    set -q autoreload_cleanup; and test "$autoreload_cleanup" = 1
end
