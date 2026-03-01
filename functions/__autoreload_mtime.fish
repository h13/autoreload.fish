if command stat -c %Y /dev/null &>/dev/null
    function __autoreload_mtime -a file
        command stat -c %Y $file 2>/dev/null
    end
else
    # Use absolute path to avoid conflicts with GNU coreutils stat in PATH
    function __autoreload_mtime -a file
        /usr/bin/stat -f %m $file 2>/dev/null
    end
end
