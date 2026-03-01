function __autoreload_is_disabled
    set -q autoreload_enabled; and test "$autoreload_enabled" = 0
end
