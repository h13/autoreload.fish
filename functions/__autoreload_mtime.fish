if command stat -c %Y /dev/null &>/dev/null
    function __autoreload_mtime
        command stat -c %Y $argv 2>/dev/null
    end
else
    # Use absolute path to avoid conflicts with GNU coreutils stat in PATH
    function __autoreload_mtime
        /usr/bin/stat -f %m $argv 2>/dev/null
    end
end
