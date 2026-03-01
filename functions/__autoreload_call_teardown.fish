function __autoreload_call_teardown -a file
    set -l basename (__autoreload_basename $file)
    set -l name (string replace -r '\.fish$' '' $basename)
    set -l teardown_fn __"$name"_teardown
    if functions -q $teardown_fn
        __autoreload_debug "calling $teardown_fn"
        $teardown_fn
    end
end
