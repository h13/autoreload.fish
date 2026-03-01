# Platform-specific mtime implementation (defined once at autoload time)
if command stat -c %Y /dev/null &>/dev/null
    # GNU stat (Linux)
    function __autoreload_mtime
        command stat -c %Y $argv 2>/dev/null
    end
else
    # BSD stat (macOS) — absolute path avoids conflicts with GNU coreutils in PATH
    function __autoreload_mtime
        /usr/bin/stat -f %m $argv 2>/dev/null
    end
end
