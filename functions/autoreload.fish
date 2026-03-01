function autoreload -a cmd -d "autoreload.fish utility command"
    switch "$cmd"
        case status
            echo "autoreload v$__autoreload_version"
            set -l flags
            if set -q autoreload_enabled; and test "$autoreload_enabled" = 0
                set -a flags disabled
            end
            if __autoreload_is_quiet
                set -a flags quiet
            end
            if __autoreload_is_debug
                set -a flags debug
            end
            if __autoreload_cleanup_enabled
                set -a flags cleanup
            end
            if test (count $flags) -gt 0
                echo "flags: "(string join ", " $flags)
            end
            if set -q autoreload_exclude
                echo "excluding: $autoreload_exclude"
            end
            echo "tracking "(count $__autoreload_files)" files:"
            for file in $__autoreload_files
                echo "  "(__autoreload_basename $file)
            end
            if __autoreload_cleanup_enabled; and test (count $__autoreload_tracked_keys) -gt 0
                echo "cleanup tracking "(count $__autoreload_tracked_keys)" files:"
                for key in $__autoreload_tracked_keys
                    set -l _details
                    for _cat in vars funcs abbrs paths
                        set -l _track __autoreload_added_{$_cat}_$key
                        set -l _count (count $$_track)
                        if test $_count -gt 0
                            set -a _details "$_cat=$_count"
                        end
                    end
                    echo "  "(string unescape --style=var $key)": "(string join ", " $_details)
                end
            end
        case reset
            __autoreload_snapshot
            if not __autoreload_is_quiet
                echo "autoreload: snapshot refreshed ("(count $__autoreload_files)" files)"
            end
        case enable
            set -e autoreload_enabled
            if not __autoreload_is_quiet
                echo "autoreload: enabled"
            end
        case disable
            set -g autoreload_enabled 0
            if not __autoreload_is_quiet
                echo "autoreload: disabled"
            end
        case version
            echo $__autoreload_version
        case help ''
            echo "autoreload v$__autoreload_version — auto-reload fish config files on change"
            echo
            echo "Commands:"
            echo "  status   Show tracked files and configuration"
            echo "  reset    Refresh file tracking snapshot"
            echo "  enable   Enable file change detection"
            echo "  disable  Disable file change detection"
            echo "  version  Print version number"
            echo "  help     Show this help message"
            echo
            echo "Variables:"
            echo "  autoreload_enabled   Set to 0 to disable (default: enabled)"
            echo "  autoreload_quiet     Set to 1 to suppress messages"
            echo "  autoreload_exclude   List of basenames to skip"
            echo "  autoreload_debug     Set to 1 for debug output"
            echo "  autoreload_cleanup   Set to 1 to enable state cleanup on re-source"
        case '*'
            echo "autoreload: unknown command '$cmd'" >&2
            echo "Run 'autoreload help' for usage." >&2
            return 1
    end
end
