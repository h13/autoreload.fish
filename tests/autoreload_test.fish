# Tests for autoreload.fish
# Requires: fishtape (fisher install jorgebucaran/fishtape)

# --- Setup ---

set -g __test_dir (mktemp -d)
set -g __test_conf_d $__test_dir/conf.d
mkdir -p $__test_conf_d

# Add plugin functions/ to fish_function_path so autoloaded functions are available
set -g __test_plugin_functions_dir (builtin realpath (status dirname)/../functions)
set -g __test_original_fish_function_path $fish_function_path
set -gx fish_function_path $__test_plugin_functions_dir $fish_function_path

# Create a dummy self file so the plugin can resolve its own path
echo "# self" >$__test_conf_d/autoreload.fish

# Save original __fish_config_dir for restoration in cleanup
set -g __test_original_fish_config_dir $__fish_config_dir

# Override __fish_config_dir and pre-set __autoreload_self
set -g __fish_config_dir $__test_dir
set -g __autoreload_self (builtin realpath $__test_conf_d/autoreload.fish)

# Extract version from production conf.d
set -g __test_plugin_file (builtin realpath (status dirname)/../conf.d/autoreload.fish)

# Initialize plugin state directly — no string replacement of production code.
# Event-bound functions (__autoreload_check, _autoreload_uninstall) are defined
# here without --on-event so they can be called directly from tests.
function __test_init_plugin
    eval (string match -r 'set -g __autoreload_version .*' <$__test_plugin_file)
    set -g __autoreload_tracked_keys
    function __autoreload_check
        __autoreload_run_check
    end
    function _autoreload_uninstall
        __autoreload_cleanup_all
        functions -e _autoreload_uninstall
    end
    __autoreload_snapshot
    # Invalidate conf.d mtime cache for test reliability.
    # Tests execute faster than stat's 1-second mtime resolution.
    set -g __autoreload_conf_d_mtime 0
end

__test_init_plugin

# Wrap __autoreload_snapshot to invalidate conf.d mtime cache after every call
functions -c __autoreload_snapshot __test_autoreload_snapshot_impl
function __autoreload_snapshot
    __test_autoreload_snapshot_impl
    set -g __autoreload_conf_d_mtime 0
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

# Set mtime to a known different value to ensure change detection
command touch -t 200101010000 $__test_conf_d/dummy.fish
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

# --- Test 6: source failure shows warning ---

__autoreload_snapshot
echo if >$__test_conf_d/broken.fish
set -l output (__autoreload_check 2>&1)
@test "source failure shows warning on stderr" (string match -q '*warning*broken.fish*' -- $output; and echo yes) = yes
@test "source failure shows failed on stdout" (string match -q '*failed*broken.fish*' -- $output; and echo yes) = yes
command rm -f $__test_conf_d/broken.fish
__autoreload_snapshot

# --- Test 7: autoreload_enabled=0 disables checking ---

__autoreload_snapshot
set -g autoreload_enabled 0
command touch -t 200201010000 $__test_conf_d/dummy.fish
set -l output (__autoreload_check)
@test "disabled when autoreload_enabled=0" -z "$output"
set -e autoreload_enabled

# --- Test 8: autoreload status command ---

__autoreload_snapshot
set -l output (autoreload status)
@test "autoreload status shows version" (string match -q "*v$__autoreload_version*" -- $output; and echo yes) = yes
@test "autoreload status lists tracked files" (string match -q '*dummy.fish*' -- $output; and echo yes) = yes
@test "autoreload version returns version" (autoreload version) = $__autoreload_version

set -g autoreload_exclude dummy.fish
set -l output (autoreload status)
@test "status shows excluding list" (string match -q '*excluding:*dummy.fish*' -- $output; and echo yes) = yes
set -e autoreload_exclude

# --- Test 9: autoreload_exclude skips files ---

set -g autoreload_exclude dummy.fish
__autoreload_snapshot
@test "excluded file is not tracked" (not contains -- $__test_conf_d/dummy.fish $__autoreload_files; and echo yes) = yes
@test "non-excluded file is still tracked" (contains -- $__test_conf_d/newfile.fish $__autoreload_files; and echo yes) = yes
set -e autoreload_exclude
__autoreload_snapshot

# --- Test 10: autoreload_quiet=1 suppresses messages ---

__autoreload_snapshot
set -g autoreload_quiet 1
command touch -t 200301010000 $__test_conf_d/dummy.fish
set -l output (__autoreload_check)
@test "quiet mode suppresses sourced message" -z "$output"
set -e autoreload_quiet

# --- Test 11: autoreload reset refreshes snapshot ---

echo "# extra" >$__test_conf_d/extra.fish
set -l output (autoreload reset)
@test "reset refreshes snapshot" (string match -q '*snapshot refreshed*' -- $output; and echo yes) = yes
@test "reset picks up new files" (contains -- $__test_conf_d/extra.fish $__autoreload_files; and echo yes) = yes
command rm -f $__test_conf_d/extra.fish
__autoreload_snapshot

set -g autoreload_quiet 1
set -l output (autoreload reset)
@test "reset quiet mode produces no output" -z "$output"
set -e autoreload_quiet

# --- Test 12: config.fish creation is detected ---

__autoreload_snapshot
set -l config_file $__test_dir/config.fish
command rm -f $config_file
__autoreload_snapshot
echo "set -g __test_config_var 99" >$config_file
set -l output (__autoreload_check)
@test "config.fish creation is detected" (string match -q '*sourced*config.fish*' -- $output; and echo yes) = yes
@test "config.fish content is sourced" "$__test_config_var" = 99
set -e __test_config_var

# --- Test 13: config.fish respects autoreload_exclude ---

command rm -f $config_file
__autoreload_snapshot
set -g autoreload_exclude config.fish
echo "set -g __test_config_excl_var bad" >$config_file
set -l output (__autoreload_check)
@test "excluded config.fish is not sourced" (not set -q __test_config_excl_var; and echo yes) = yes
@test "excluded config.fish produces no output" -z "$output"
command rm -f $config_file
set -e autoreload_exclude
__autoreload_snapshot

# --- Test 14: debug mode outputs to stderr ---

__autoreload_snapshot
set -g autoreload_debug 1
set -l output (__autoreload_check 2>&1)
@test "debug mode shows checking message" (string match -q '*debug*checking*' -- $output; and echo yes) = yes
set -e autoreload_debug

# --- Test 15: status shows flags ---

set -g autoreload_debug 1
set -l output (autoreload status)
@test "status shows debug flag" (string match -q '*debug*' -- $output; and echo yes) = yes
set -e autoreload_debug

set -g autoreload_enabled 0
set -l output (autoreload status)
@test "status shows disabled flag" (string match -q '*disabled*' -- $output; and echo yes) = yes
set -e autoreload_enabled

# --- Test 16: excluded new file is not sourced ---

set -g autoreload_exclude excluded_new.fish
__autoreload_snapshot
echo "set -g __test_excluded_var bad" >$__test_conf_d/excluded_new.fish
set -l output (__autoreload_check)
@test "excluded new file is not sourced" (not set -q __test_excluded_var; and echo yes) = yes
@test "excluded new file produces no output" -z "$output"
command rm -f $__test_conf_d/excluded_new.fish
set -e autoreload_exclude
__autoreload_snapshot

# --- Test 17: multiple files changed simultaneously ---

echo "set -g __test_multi_a 1" >$__test_conf_d/multi_a.fish
echo "set -g __test_multi_b 2" >$__test_conf_d/multi_b.fish
__autoreload_snapshot
echo "set -g __test_multi_a 10" >$__test_conf_d/multi_a.fish
echo "set -g __test_multi_b 20" >$__test_conf_d/multi_b.fish
command touch -t 200401010000 $__test_conf_d/multi_a.fish $__test_conf_d/multi_b.fish
set -l output (__autoreload_check)
@test "multiple changed files: a is sourced" "$__test_multi_a" = 10
@test "multiple changed files: b is sourced" "$__test_multi_b" = 20
@test "multiple changed files: output lists both" (string match -q '*multi_a.fish*multi_b.fish*' -- $output; and echo yes) = yes
command rm -f $__test_conf_d/multi_a.fish $__test_conf_d/multi_b.fish
set -e __test_multi_a
set -e __test_multi_b
__autoreload_snapshot

# --- Test 18: enable and disable subcommands ---

set -l output (autoreload disable)
@test "disable sets autoreload_enabled to 0" "$autoreload_enabled" = 0
@test "disable shows message" (string match -q '*disabled*' -- $output; and echo yes) = yes
set -l output (autoreload enable)
@test "enable clears autoreload_enabled" (not set -q autoreload_enabled; and echo yes) = yes
@test "enable shows message" (string match -q '*enabled*' -- $output; and echo yes) = yes

set -g autoreload_quiet 1
set -l output (autoreload disable)
@test "disable quiet produces no output" -z "$output"
set -l output (autoreload enable)
@test "enable quiet produces no output" -z "$output"
set -e autoreload_quiet

# --- Test 19: help subcommand ---

set -l output (autoreload help)
@test "help shows commands section" (string match -q '*Commands:*' -- $output; and echo yes) = yes
@test "help shows variables section" (string match -q '*Variables:*' -- $output; and echo yes) = yes

set -l output (autoreload)
@test "bare autoreload shows help" (string match -q '*Commands:*' -- $output; and echo yes) = yes

set -l output (autoreload -h)
@test "-h flag shows help" (string match -q '*Commands:*' -- $output; and echo yes) = yes

set -l output (autoreload --help)
@test "--help flag shows help" (string match -q '*Commands:*' -- $output; and echo yes) = yes

# --- Test 20: unknown command shows error ---

set -l output (autoreload nonexistent 2>&1)
@test "unknown command shows error" (string match -q '*unknown command*' -- $output; and echo yes) = yes
@test "unknown command suggests help" (string match -q '*autoreload help*' -- $output; and echo yes) = yes
autoreload nonexistent 2>/dev/null
@test "unknown command returns non-zero" $status = 1

# --- Test 21: __autoreload_key generates correct keys ---

@test "key: aliases.fish -> aliases_2E_fish" (__autoreload_key /some/path/aliases.fish) = aliases_2E_fish
@test "key: my-plugin.fish -> my_2D_plugin_2E_fish" (__autoreload_key /path/my-plugin.fish) = my_2D_plugin_2E_fish
@test "key: a.b.fish -> a_2E_b_2E_fish" (__autoreload_key /path/a.b.fish) = a_2E_b_2E_fish
@test "key: no collision: my-plugin.fish != my_plugin.fish" (test (__autoreload_key /path/my-plugin.fish) != (__autoreload_key /path/my_plugin.fish); and echo yes) = yes

# --- Test 22: __autoreload_basename ---

@test "basename: extracts filename" (__autoreload_basename /some/path/foo.fish) = foo.fish
@test "basename: bare filename unchanged" (__autoreload_basename bar.fish) = bar.fish
@test "basename: multiple args" (count (__autoreload_basename /a/one.fish /b/two.fish)) = 2

# --- Test 23: __autoreload_is_excluded ---

set -g autoreload_exclude skip.fish
@test "is_excluded: matching file returns 0" (__autoreload_is_excluded /path/skip.fish; and echo yes) = yes
@test "is_excluded: non-matching file returns 1" (not __autoreload_is_excluded /path/keep.fish; and echo yes) = yes
set -e autoreload_exclude
@test "is_excluded: unset exclude returns 1" (not __autoreload_is_excluded /path/any.fish; and echo yes) = yes

# --- Test 24: cleanup disabled (default) — current behavior unchanged ---

__autoreload_snapshot
echo "set -g __test_cleanup_disabled_var 1" >$__test_conf_d/cleanup_off.fish
set -l output (__autoreload_check)
@test "cleanup disabled: file is sourced" "$__test_cleanup_disabled_var" = 1
# modify the file to remove the variable
echo "# empty now" >$__test_conf_d/cleanup_off.fish
command touch -t 200501010000 $__test_conf_d/cleanup_off.fish
set -l output (__autoreload_check)
@test "cleanup disabled: old var remains (no cleanup)" "$__test_cleanup_disabled_var" = 1
command rm -f $__test_conf_d/cleanup_off.fish
set -e __test_cleanup_disabled_var
__autoreload_snapshot

# --- Test 25: cleanup enabled — variable removed on re-source ---

set -g autoreload_cleanup 1
__autoreload_snapshot
echo "set -g __test_cleanup_var alpha" >$__test_conf_d/cleanup_var.fish
set -l output (__autoreload_check)
@test "cleanup: var is set after first source" "$__test_cleanup_var" = alpha
# re-source with the variable removed
echo "# var removed" >$__test_conf_d/cleanup_var.fish
command touch -t 200601010000 $__test_conf_d/cleanup_var.fish
set -l output (__autoreload_check)
@test "cleanup: var is removed after re-source" (not set -q __test_cleanup_var; and echo yes) = yes
command rm -f $__test_conf_d/cleanup_var.fish
__autoreload_snapshot

# --- Test 26: cleanup enabled — function removed on re-source ---

__autoreload_snapshot
echo "function __test_cleanup_fn; echo hi; end" >$__test_conf_d/cleanup_fn.fish
set -l output (__autoreload_check)
@test "cleanup: function exists after first source" (functions -q __test_cleanup_fn; and echo yes) = yes
# re-source without the function
echo "# fn removed" >$__test_conf_d/cleanup_fn.fish
command touch -t 200701010000 $__test_conf_d/cleanup_fn.fish
set -l output (__autoreload_check)
@test "cleanup: function removed after re-source" (functions -q __test_cleanup_fn; or echo gone) = gone
command rm -f $__test_conf_d/cleanup_fn.fish
__autoreload_snapshot

# --- Test 27: cleanup enabled — abbreviation removed on re-source ---

__autoreload_snapshot
echo "abbr --add __test_cleanup_abbr 'echo test'" >$__test_conf_d/cleanup_abbr.fish
set -l output (__autoreload_check)
@test "cleanup: abbr exists after first source" (abbr --list | string match -q '*__test_cleanup_abbr*'; and echo yes) = yes
# re-source without the abbreviation
echo "# abbr removed" >$__test_conf_d/cleanup_abbr.fish
command touch -t 200801010000 $__test_conf_d/cleanup_abbr.fish
set -l output (__autoreload_check)
@test "cleanup: abbr removed after re-source" (abbr --list | string match -q '*__test_cleanup_abbr*'; or echo gone) = gone
command rm -f $__test_conf_d/cleanup_abbr.fish
__autoreload_snapshot

# --- Test 28: cleanup enabled — PATH entry removed on re-source ---

__autoreload_snapshot
echo "set -ga PATH /tmp/__test_cleanup_path_entry" >$__test_conf_d/cleanup_path.fish
set -l output (__autoreload_check)
@test "cleanup: PATH entry exists after first source" (contains -- /tmp/__test_cleanup_path_entry $PATH; and echo yes) = yes
# re-source without the PATH entry
echo "# path removed" >$__test_conf_d/cleanup_path.fish
command touch -t 200901010000 $__test_conf_d/cleanup_path.fish
set -l output (__autoreload_check)
@test "cleanup: PATH entry removed after re-source" (not contains -- /tmp/__test_cleanup_path_entry $PATH; and echo yes) = yes
command rm -f $__test_conf_d/cleanup_path.fish
__autoreload_snapshot

# --- Test 29: file deletion — side effects cleaned up ---

__autoreload_snapshot
echo "set -g __test_del_var 1
function __test_del_fn; echo x; end" >$__test_conf_d/cleanup_del.fish
set -l output (__autoreload_check)
@test "delete cleanup: var exists" "$__test_del_var" = 1
@test "delete cleanup: fn exists" (functions -q __test_del_fn; and echo yes) = yes
# delete the file
command rm -f $__test_conf_d/cleanup_del.fish
set -l output (__autoreload_check)
@test "delete cleanup: var removed" (not set -q __test_del_var; and echo yes) = yes
@test "delete cleanup: fn removed" (functions -q __test_del_fn; or echo gone) = gone
__autoreload_snapshot

# --- Test 30: multiple file deletion — side effects cleaned up ---

__autoreload_snapshot
echo "set -g __test_mdel_var_a 1" >$__test_conf_d/mdel_a.fish
echo "set -g __test_mdel_var_b 2" >$__test_conf_d/mdel_b.fish
set -l output (__autoreload_check)
@test "multi delete: var a exists" "$__test_mdel_var_a" = 1
@test "multi delete: var b exists" "$__test_mdel_var_b" = 2
# delete both files simultaneously
command rm -f $__test_conf_d/mdel_a.fish $__test_conf_d/mdel_b.fish
set -l output (__autoreload_check)
@test "multi delete: var a removed" (not set -q __test_mdel_var_a; and echo yes) = yes
@test "multi delete: var b removed" (not set -q __test_mdel_var_b; and echo yes) = yes
@test "multi delete: output lists both" (string match -q '*mdel_a.fish*mdel_b.fish*' -- $output; and echo yes) = yes
__autoreload_snapshot

# --- Test 31: teardown hook called on re-source ---

# Pre-create marker so it's not tracked as "added" by cleanup
set -g __test_teardown_marker 0
__autoreload_snapshot
echo 'function __teardown_hook_teardown
    set -g __test_teardown_marker called
end' >$__test_conf_d/teardown_hook.fish
set -l output (__autoreload_check)
@test "teardown: marker initialized" "$__test_teardown_marker" = 0
# trigger re-source — new content does NOT reset marker, so teardown's "called" value persists
echo "# no marker reset" >$__test_conf_d/teardown_hook.fish
command touch -t 201001010000 $__test_conf_d/teardown_hook.fish
set -l output (__autoreload_check)
@test "teardown: hook was called on re-source" "$__test_teardown_marker" = called
command rm -f $__test_conf_d/teardown_hook.fish
set -e __test_teardown_marker
__autoreload_snapshot

# --- Test 32: teardown hook called on file deletion ---

# Pre-create marker so it's not tracked as "added" by cleanup
set -g __test_teardown_del_marker initial
__autoreload_snapshot
echo 'function __teardown_del_teardown
    set -g __test_teardown_del_marker torn_down
end' >$__test_conf_d/teardown_del.fish
set -l output (__autoreload_check)
@test "teardown delete: fn defined" (functions -q __teardown_del_teardown; and echo yes) = yes
# delete the file
command rm -f $__test_conf_d/teardown_del.fish
set -l output (__autoreload_check)
@test "teardown delete: hook called" "$__test_teardown_del_marker" = torn_down
set -e __test_teardown_del_marker
__autoreload_snapshot

# --- Test 33: first re-source has no baseline — old state remains ---

__autoreload_snapshot
set -g __test_no_baseline_var first
echo "set -g __test_no_baseline_var first" >$__test_conf_d/no_baseline.fish
set -l output (__autoreload_check)
# now modify
echo "# var removed" >$__test_conf_d/no_baseline.fish
command touch -t 201101010000 $__test_conf_d/no_baseline.fish
set -l output (__autoreload_check)
# Since __test_no_baseline_var existed BEFORE the first source, it wasn't tracked as "added"
# But the source set it again, and now the file doesn't set it. The var was set before the
# first snapshot, so Tier 1 doesn't know about it.
# Actually: the var existed before source, so the diff didn't pick it up as "new"
@test "no baseline: pre-existing var remains" "$__test_no_baseline_var" = first
command rm -f $__test_conf_d/no_baseline.fish
set -e __test_no_baseline_var
__autoreload_snapshot

# --- Test 34: source failure clears tracking (undo already happened) ---

__autoreload_snapshot
echo "set -g __test_fail_var 1" >$__test_conf_d/fail_track.fish
set -l output (__autoreload_check)
@test "source fail: var set on first source" "$__test_fail_var" = 1
# break the file
echo if >$__test_conf_d/fail_track.fish
command touch -t 201201010000 $__test_conf_d/fail_track.fish
set -l output (__autoreload_check 2>&1)
# undo happens before source, so tracking is cleared even on failure
set -l key (__autoreload_key $__test_conf_d/fail_track.fish)
@test "source fail: tracking cleared" (not contains -- $key $__autoreload_tracked_keys; and echo yes) = yes
command rm -f $__test_conf_d/fail_track.fish
set -e __test_fail_var
__autoreload_snapshot

# --- Test 35: autoreload status shows cleanup info ---

# create a file with a variable to ensure tracked keys exist
__autoreload_snapshot
echo "set -g __test_status_detail_var 1" >$__test_conf_d/status_detail.fish
set -l output (__autoreload_check)
set -l output (autoreload status)
@test "status shows cleanup flag" (string match -q '*cleanup*' -- $output; and echo yes) = yes
@test "status shows per-key details" (string match -q '*vars=*' -- $output; and echo yes) = yes
command rm -f $__test_conf_d/status_detail.fish
set -e __test_status_detail_var
__autoreload_snapshot

set -e autoreload_cleanup

# --- Test 36: direct undo restores vars, funcs, abbrs, PATH ---

set -g autoreload_cleanup 1
__autoreload_snapshot
echo 'set -g __test_undo_var hello
function __test_undo_fn; echo x; end
abbr --add __test_undo_abbr "echo undo"
set -ga PATH /tmp/__test_undo_path' >$__test_conf_d/undo_direct.fish
set -l output (__autoreload_check)
@test "direct undo: var set" "$__test_undo_var" = hello
@test "direct undo: fn exists" (functions -q __test_undo_fn; and echo yes) = yes
@test "direct undo: abbr exists" (abbr --list | string match -q '*__test_undo_abbr*'; and echo yes) = yes
@test "direct undo: PATH added" (contains -- /tmp/__test_undo_path $PATH; and echo yes) = yes
# Call undo directly
set -l key (__autoreload_key $__test_conf_d/undo_direct.fish)
__autoreload_undo $key
@test "direct undo: var removed" (not set -q __test_undo_var; and echo yes) = yes
@test "direct undo: fn removed" (functions -q __test_undo_fn; or echo gone) = gone
@test "direct undo: abbr removed" (abbr --list | string match -q '*__test_undo_abbr*'; or echo gone) = gone
@test "direct undo: PATH removed" (not contains -- /tmp/__test_undo_path $PATH; and echo yes) = yes
command rm -f $__test_conf_d/undo_direct.fish
__autoreload_snapshot

# --- Test 37: simultaneous file change and deletion ---

__autoreload_snapshot
echo "set -g __test_simul_change_var 1" >$__test_conf_d/simul_change.fish
echo "set -g __test_simul_delete_var 1" >$__test_conf_d/simul_delete.fish
__autoreload_snapshot
echo "set -g __test_simul_change_var 2" >$__test_conf_d/simul_change.fish
command touch -t 201701010000 $__test_conf_d/simul_change.fish
command rm -f $__test_conf_d/simul_delete.fish
set -l output (__autoreload_check)
@test "simultaneous: changed file sourced" "$__test_simul_change_var" = 2
@test "simultaneous: deleted file reported" (string match -q '*removed*simul_delete.fish*' -- $output; and echo yes) = yes
@test "simultaneous: changed file reported" (string match -q '*sourced*simul_change.fish*' -- $output; and echo yes) = yes
@test "simultaneous: deleted var cleaned up" (not set -q __test_simul_delete_var; and echo yes) = yes
command rm -f $__test_conf_d/simul_change.fish
set -e __test_simul_change_var
__autoreload_snapshot

# --- Test 38: source failure recovery on re-source ---

__autoreload_snapshot
echo "set -g __test_recover_var 1" >$__test_conf_d/recover.fish
set -l output (__autoreload_check)
@test "recovery: initial source works" "$__test_recover_var" = 1
echo if >$__test_conf_d/recover.fish
command touch -t 201801010000 $__test_conf_d/recover.fish
set -l output (__autoreload_check 2>&1)
@test "recovery: broken file warned" (string match -q '*warning*recover.fish*' -- $output; and echo yes) = yes
echo "set -g __test_recover_var fixed" >$__test_conf_d/recover.fish
command touch -t 201901010000 $__test_conf_d/recover.fish
set -l output (__autoreload_check)
@test "recovery: fixed file re-sourced" "$__test_recover_var" = fixed
command rm -f $__test_conf_d/recover.fish
set -e __test_recover_var
__autoreload_snapshot

# --- Test 39: teardown failure logged in debug mode ---

__autoreload_snapshot
echo 'function __teardown_fail_teardown; return 1; end' >$__test_conf_d/teardown_fail.fish
set -l output (__autoreload_check)
set -g autoreload_debug 1
echo "# modified" >$__test_conf_d/teardown_fail.fish
command touch -t 202001010000 $__test_conf_d/teardown_fail.fish
set -l output (__autoreload_check 2>&1)
@test "teardown fail: failure logged" (string match -q '*failed with status*' -- $output; and echo yes) = yes
set -e autoreload_debug
command rm -f $__test_conf_d/teardown_fail.fish
__autoreload_snapshot

# --- Test 40: empty conf.d returns empty file list ---

for f in $__test_conf_d/*.fish
    if test (string replace -r '.*/' '' $f) != autoreload.fish
        command rm -f $f
    end
end
command rm -f $__test_dir/config.fish
__autoreload_snapshot
@test "empty conf.d: no files tracked" (count $__autoreload_files) = 0
# Restore files for remaining tests
echo "# dummy" >$__test_conf_d/dummy.fish
__autoreload_snapshot

# --- Test 41: PATH duplicate not accumulated on re-source ---

__autoreload_snapshot
set -l __test_dup_path /tmp/__test_dup_path_entry
set -ga PATH $__test_dup_path
echo "set -ga PATH $__test_dup_path" >$__test_conf_d/dup_path.fish
set -l output (__autoreload_check)
# The conf.d file adds a duplicate PATH entry; cleanup should track it
set -l key (__autoreload_key $__test_conf_d/dup_path.fish)
set -l _paths_var __autoreload_added_paths_$key
@test "dup PATH: duplicate is tracked" (count $$_paths_var) = 1
# Re-source without the PATH append — undo should remove the duplicate
echo "# path removed" >$__test_conf_d/dup_path.fish
command touch -t 202101010000 $__test_conf_d/dup_path.fish
set -l output (__autoreload_check)
@test "dup PATH: duplicate removed after re-source" (count (string match -- $__test_dup_path $PATH)) = 1
# Clean up
command rm -f $__test_conf_d/dup_path.fish
if set -l idx (contains -i -- $__test_dup_path $PATH)
    set -e PATH[$idx]
end
__autoreload_snapshot

# --- Test 42: cleanup tracks side effects when source exits non-zero ---

__autoreload_snapshot
echo 'set -g __test_nonzero_var 1
false' >$__test_conf_d/nonzero_exit.fish
set -l output (__autoreload_check 2>&1)
@test "nonzero exit: var is set" "$__test_nonzero_var" = 1
set -l key (__autoreload_key $__test_conf_d/nonzero_exit.fish)
@test "nonzero exit: side effects tracked" (contains -- $key $__autoreload_tracked_keys; and echo yes) = yes
# Re-source without the variable
echo true >$__test_conf_d/nonzero_exit.fish
command touch -t 202401010000 $__test_conf_d/nonzero_exit.fish
set -l output (__autoreload_check)
@test "nonzero exit: var cleaned up on re-source" (not set -q __test_nonzero_var; and echo yes) = yes
command rm -f $__test_conf_d/nonzero_exit.fish
__autoreload_snapshot

set -e autoreload_cleanup

# --- Test 43: conf.d mtime cache updated on no-op directory change ---

set -g __autoreload_conf_d_mtime 0
set -l output (__autoreload_check)
@test "conf.d cache: no spurious output on no-op" -z "$output"
@test "conf.d cache: mtime updated after scan" (test "$__autoreload_conf_d_mtime" != 0; and echo yes) = yes

# --- Test 44: config.fish modification is detected ---

__autoreload_snapshot
set -l config_file $__test_dir/config.fish
echo "set -g __test_config_mod_var 1" >$config_file
__autoreload_snapshot
echo "set -g __test_config_mod_var 2" >$config_file
command touch -t 202201010000 $config_file
set -l output (__autoreload_check)
@test "config.fish modification detected" (string match -q '*sourced*config.fish*' -- $output; and echo yes) = yes
@test "config.fish modified content is sourced" "$__test_config_mod_var" = 2
command rm -f $config_file
set -e __test_config_mod_var
__autoreload_snapshot

# --- Test 45: batch stat fallback detects changes ---

__autoreload_snapshot
echo "set -g __test_fallback_var 1" >$__test_conf_d/fallback.fish
__autoreload_snapshot
echo "set -g __test_fallback_var 2" >$__test_conf_d/fallback.fish
command touch -t 202301010000 $__test_conf_d/fallback.fish
# Override __autoreload_mtime to return fewer results on batch call
functions -c __autoreload_mtime __test_original_mtime
function __autoreload_mtime
    if test (count $argv) -gt 1
        # Drop last arg to trigger count mismatch fallback
        for i in (seq (math (count $argv) - 1))
            __test_original_mtime $argv[$i]
        end
    else
        __test_original_mtime $argv
    end
end
set -g autoreload_debug 1
set -l output (__autoreload_check 2>&1)
set -e autoreload_debug
@test "stat fallback: triggered on count mismatch" (string match -q '*stat count mismatch*' -- $output; and echo yes) = yes
@test "stat fallback: change detected" (string match -q '*sourced*fallback.fish*' -- $output; and echo yes) = yes
@test "stat fallback: content sourced correctly" "$__test_fallback_var" = 2
# Restore original __autoreload_mtime
functions -e __autoreload_mtime
functions -c __test_original_mtime __autoreload_mtime
functions -e __test_original_mtime
command rm -f $__test_conf_d/fallback.fish
set -e __test_fallback_var
__autoreload_snapshot

# --- Test 46: uninstall clears tracking variables ---

set -g autoreload_cleanup 1
__autoreload_snapshot
echo "set -g __test_uninstall_var 1" >$__test_conf_d/uninstall_track.fish
set -l output (__autoreload_check)
@test "uninstall tracking: var exists" "$__test_uninstall_var" = 1
set -l key (__autoreload_key $__test_conf_d/uninstall_track.fish)
@test "uninstall tracking: key registered" (contains -- $key $__autoreload_tracked_keys; and echo yes) = yes
_autoreload_uninstall

# Re-initialize plugin after uninstall — explicit source since autoloading
# may fail for functions that were defined inline then erased.
set -g __autoreload_self (builtin realpath $__test_conf_d/autoreload.fish)
for f in $__test_plugin_functions_dir/__autoreload_*.fish
    source $f
end
__test_init_plugin
# Re-wrap snapshot for mtime cache invalidation
functions -e __test_autoreload_snapshot_impl
functions -c __autoreload_snapshot __test_autoreload_snapshot_impl
function __autoreload_snapshot
    __test_autoreload_snapshot_impl
    set -g __autoreload_conf_d_mtime 0
end
@test "re-source after uninstall succeeded" (functions -q __autoreload_check; and echo yes) = yes
@test "uninstall tracking: tracking var cleaned" (not set -q __autoreload_added_vars_$key; and echo yes) = yes
@test "uninstall tracking: tracked keys cleared" (test (count $__autoreload_tracked_keys) -eq 0; and echo yes) = yes
command rm -f $__test_conf_d/uninstall_track.fish
set -e __test_uninstall_var
set -e autoreload_cleanup

# --- Test 47: _autoreload_uninstall cleans up ---

# Pre-load __autoreload_cleanup_all into memory before removing plugin from path
source $__test_plugin_functions_dir/__autoreload_cleanup_all.fish
# Remove plugin functions/ BEFORE uninstall so autoload cannot re-discover erased functions
set -gx fish_function_path $__test_original_fish_function_path
# Set universal config vars to verify cleanup erases both scopes
set -U autoreload_cleanup 1
set -U autoreload_debug 1
_autoreload_uninstall
@test "uninstall removes __autoreload_mtime" (functions -q __autoreload_mtime; or echo gone) = gone
@test "uninstall removes __autoreload_snapshot" (functions -q __autoreload_snapshot; or echo gone) = gone
@test "uninstall removes __autoreload_source_file" (functions -q __autoreload_source_file; or echo gone) = gone
@test "uninstall removes __autoreload_check" (functions -q __autoreload_check; or echo gone) = gone
@test "uninstall removes __autoreload_version" (set -q __autoreload_version; or echo gone) = gone
@test "uninstall removes __autoreload_files" (set -q __autoreload_files; or echo gone) = gone
@test "uninstall removes universal autoreload_cleanup" (set -qU autoreload_cleanup; or echo gone) = gone
@test "uninstall removes universal autoreload_debug" (set -qU autoreload_debug; or echo gone) = gone

# --- Cleanup ---

command rm -rf $__test_dir
functions -e __test_init_plugin
functions -e __test_autoreload_snapshot_impl
set -e __test_plugin_file
set -e __test_dir
set -e __test_conf_d
set -e __test_new_file_var
set -g __fish_config_dir $__test_original_fish_config_dir
set -e __test_original_fish_config_dir
set -gx fish_function_path $__test_original_fish_function_path
set -e __test_original_fish_function_path
set -e __test_plugin_functions_dir
# Safety net: clean up any universal vars that might persist if tests fail
set -eU autoreload_cleanup
set -eU autoreload_debug
