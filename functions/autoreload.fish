function autoreload -a cmd -d "autoreload.fish utility command"
    switch "$cmd"
        case status
            __autoreload_show_status
        case reset
            __autoreload_snapshot
            if not __autoreload_is_quiet
                echo "autoreload: snapshot refreshed ("(count $__autoreload_files)" files)"
            end
        case enable
            set -eg autoreload_enabled
            set -eU autoreload_enabled
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
        case help '' -h --help
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
