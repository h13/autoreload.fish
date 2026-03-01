function __autoreload_undo -a key
    # undo PATH entries (try fish_user_paths first, then PATH directly)
    set -l varname __autoreload_added_paths_$key
    for p in $$varname
        if set -l idx (contains -i -- $p $fish_user_paths)
            set -e fish_user_paths[$idx]
        else if set -l idx (contains -i -- $p $PATH)
            set -e PATH[$idx]
        end
    end

    # undo abbreviations
    set -l varname __autoreload_added_abbrs_$key
    for name in $$varname
        abbr --erase $name 2>/dev/null
    end

    # undo functions
    set -l varname __autoreload_added_funcs_$key
    for name in $$varname
        functions -e $name 2>/dev/null
    end

    # undo global variables
    set -l varname __autoreload_added_vars_$key
    for name in $$varname
        set -eg $name
    end

    __autoreload_clear_tracking $key
end
