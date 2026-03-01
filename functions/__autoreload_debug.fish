function __autoreload_debug -a msg
    if __autoreload_is_debug
        echo "autoreload: [debug] $msg" >&2
    end
end
