function __autoreload_is_debug
    set -q autoreload_debug; and test "$autoreload_debug" = 1
end
