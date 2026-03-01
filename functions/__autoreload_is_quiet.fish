function __autoreload_is_quiet
    set -q autoreload_quiet; and test "$autoreload_quiet" = 1
end
