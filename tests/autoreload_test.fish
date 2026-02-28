# Tests for autoreload.fish
# Requires: fishtape (fisher install jorgebucaran/fishtape)

# --- Setup ---

set -g __test_dir (mktemp -d)
set -g __test_conf_d $__test_dir/conf.d
mkdir -p $__test_conf_d

# Create a dummy self file so the plugin can resolve its own path
echo "# self" >$__test_conf_d/autoreload.fish

# Override __fish_config_dir to point at our temp directory
set -g __fish_config_dir $__test_dir

# Source the plugin — need to trick the interactive check and self-path
# We source only the function definitions, skipping the guards
# by defining the functions directly

# Platform-aware mtime
if command stat -c %Y /dev/null &>/dev/null
    function __autoreload_mtime -a file
        command stat -c %Y $file 2>/dev/null | string trim
    end
else
    function __autoreload_mtime -a file
        /usr/bin/stat -f %m $file 2>/dev/null | string trim
    end
end

function __autoreload_debug -a msg
    if set -q autoreload_debug; and test "$autoreload_debug" = 1
        echo "autoreload: [debug] $msg" >&2
    end
end

set -g __autoreload_self (builtin realpath $__test_conf_d/autoreload.fish)

function __autoreload_snapshot
    set -g __autoreload_files
    set -g __autoreload_mtimes

    set -l config_file $__fish_config_dir/config.fish
    if test -f $config_file
        set -a __autoreload_files $config_file
        set -a __autoreload_mtimes (__autoreload_mtime $config_file)
    end

    for file in $__fish_config_dir/conf.d/*.fish
        if test (builtin realpath $file) = $__autoreload_self
            continue
        end
        set -a __autoreload_files $file
        set -a __autoreload_mtimes (__autoreload_mtime $file)
    end
end

function __autoreload_check
    if set -q autoreload_enabled; and test "$autoreload_enabled" = 0
        return
    end

    __autoreload_debug "checking "(count $__autoreload_files)" files"

    set -l changed
    set -l deleted

    for i in (seq (count $__autoreload_files))
        set -l file $__autoreload_files[$i]
        if not test -f $file
            set -a deleted $file
            continue
        end
        set -l current (__autoreload_mtime $file)
        if test "$current" != "$__autoreload_mtimes[$i]"
            set -a changed $file
        end
    end

    if test (count $deleted) -gt 0
        set -l names (string replace -r '.*/' '' $deleted)
        echo "autoreload: "(set_color yellow)"removed"(set_color normal)" $names"
        __autoreload_snapshot
    end

    for file in $__fish_config_dir/conf.d/*.fish
        if test (builtin realpath $file) = $__autoreload_self
            continue
        end
        if not contains -- $file $__autoreload_files
            set -a changed $file
        end
    end

    if test (count $changed) -eq 0
        return
    end

    set -l sourced
    for file in $changed
        if source $file 2>/dev/null
            set -a sourced $file
        else
            echo "autoreload: "(set_color red)"error"(set_color normal)" sourcing "(string replace -r '.*/' '' $file) >&2
        end
    end

    if test (count $sourced) -gt 0
        set -l names (string replace -r '.*/' '' $sourced)
        echo "autoreload: "(set_color green)"sourced"(set_color normal)" $names"
    end

    __autoreload_snapshot
end

function _autoreload_uninstall
    functions -e __autoreload_mtime
    functions -e __autoreload_debug
    functions -e __autoreload_snapshot
    functions -e __autoreload_check
    functions -e _autoreload_install
    functions -e _autoreload_uninstall
    set -e __autoreload_version
    set -e __autoreload_self
    set -e __autoreload_files
    set -e __autoreload_mtimes
    set -e autoreload_enabled
    set -e autoreload_debug
end

# --- Test 1: __autoreload_mtime returns a timestamp ---

set -l test_file $__test_dir/mtime_test.fish
echo "# test" >$test_file
set -l mtime (__autoreload_mtime $test_file)
@test "mtime returns a numeric timestamp" (string match -qr '^\d+$' -- $mtime; and echo yes) = yes

# --- Test 2: __autoreload_snapshot tracks files ---

echo "# dummy" >$__test_conf_d/dummy.fish
__autoreload_snapshot
@test "snapshot tracks conf.d files" (contains -- $__test_conf_d/dummy.fish $__autoreload_files; and echo yes) = yes
@test "snapshot excludes self" (not contains -- $__test_conf_d/autoreload.fish $__autoreload_files; and echo yes) = yes

# --- Test 3: file change detection ---

# Touch the file with a future mtime to ensure change
sleep 1
touch $__test_conf_d/dummy.fish
set -l output (__autoreload_check)
@test "changed file is sourced" (string match -q '*sourced*dummy.fish*' -- $output; and echo yes) = yes

# --- Test 4: new file detection ---

__autoreload_snapshot
echo "set -g __test_new_file_var 42" >$__test_conf_d/newfile.fish
set -l output (__autoreload_check)
@test "new file is detected and sourced" (string match -q '*sourced*newfile.fish*' -- $output; and echo yes) = yes
@test "new file content is actually sourced" "$__test_new_file_var" = 42

# --- Test 5: deleted file detection ---

__autoreload_snapshot
set -l del_file $__test_conf_d/to_delete.fish
echo "# will be deleted" >$del_file
__autoreload_snapshot
command rm -f $del_file
set -l output (__autoreload_check)
@test "deleted file is reported" (string match -q '*removed*to_delete.fish*' -- $output; and echo yes) = yes

# --- Test 6: source failure shows error ---

__autoreload_snapshot
echo "if" >$__test_conf_d/broken.fish
set -l output (__autoreload_check 2>&1)
@test "source failure shows error message" (string match -q '*error*broken.fish*' -- $output; and echo yes) = yes
command rm -f $__test_conf_d/broken.fish
__autoreload_snapshot

# --- Test 7: autoreload_enabled=0 disables checking ---

__autoreload_snapshot
set -g autoreload_enabled 0
sleep 1
touch $__test_conf_d/dummy.fish
set -l output (__autoreload_check)
@test "disabled when autoreload_enabled=0" -z "$output"
set -e autoreload_enabled

# --- Test 8: _autoreload_uninstall cleans up ---

set -g __autoreload_version 1.0.0
_autoreload_uninstall
@test "uninstall removes __autoreload_mtime" (functions -q __autoreload_mtime; or echo gone) = gone
@test "uninstall removes __autoreload_snapshot" (functions -q __autoreload_snapshot; or echo gone) = gone
@test "uninstall removes __autoreload_check" (functions -q __autoreload_check; or echo gone) = gone
@test "uninstall removes __autoreload_version" (set -q __autoreload_version; or echo gone) = gone
@test "uninstall removes __autoreload_files" (set -q __autoreload_files; or echo gone) = gone

# --- Cleanup ---

command rm -rf $__test_dir
set -e __test_dir
set -e __test_conf_d
set -e __test_new_file_var
