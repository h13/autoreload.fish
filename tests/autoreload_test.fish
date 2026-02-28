# Tests for autoreload.fish
# Requires: fishtape (fisher install jorgebucaran/fishtape)

# --- Setup ---

set -g __test_dir (mktemp -d)
set -g __test_conf_d $__test_dir/conf.d
mkdir -p $__test_conf_d

# Create a dummy self file so the plugin can resolve its own path
echo "# self" >$__test_conf_d/autoreload.fish

# Override __fish_config_dir and pre-set __autoreload_self before sourcing
set -g __fish_config_dir $__test_dir
set -g __autoreload_self (builtin realpath $__test_conf_d/autoreload.fish)

# Source production code with test-incompatible parts neutralized:
# - Disable interactive guard (tests run non-interactively)
# - Preserve pre-set __autoreload_self instead of resolving from status filename
# - Disable empty-self guard (we already set it)
# - Remove --on-event so __autoreload_check can be called directly
set -g __test_plugin_file (builtin realpath (status dirname)/../conf.d/autoreload.fish)

function __test_source_plugin
    string replace 'if not status is-interactive' 'if false' <$__test_plugin_file \
        | string replace 'set -g __autoreload_self (builtin realpath (status filename))' '# __autoreload_self already set by test' \
        | string replace 'if test -z "$__autoreload_self"' 'if false' \
        | string replace -- '--on-event fish_prompt' '' \
        | source
end

__test_source_plugin

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

# --- Test 6: source failure shows error ---

__autoreload_snapshot
echo if >$__test_conf_d/broken.fish
set -l output (__autoreload_check 2>&1)
@test "source failure shows error message" (string match -q '*error*broken.fish*' -- $output; and echo yes) = yes
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

# --- Test 13: debug mode outputs to stderr ---

__autoreload_snapshot
set -g autoreload_debug 1
set -l output (__autoreload_check 2>&1)
@test "debug mode shows checking message" (string match -q '*debug*checking*' -- $output; and echo yes) = yes
set -e autoreload_debug

# --- Test 14: status shows flags ---

set -g autoreload_debug 1
set -l output (autoreload status)
@test "status shows debug flag" (string match -q '*debug*' -- $output; and echo yes) = yes
set -e autoreload_debug

# --- Test 15: excluded new file is not sourced ---

set -g autoreload_exclude excluded_new.fish
__autoreload_snapshot
echo "set -g __test_excluded_var bad" >$__test_conf_d/excluded_new.fish
set -l output (__autoreload_check)
@test "excluded new file is not sourced" (not set -q __test_excluded_var; and echo yes) = yes
@test "excluded new file produces no output" -z "$output"
command rm -f $__test_conf_d/excluded_new.fish
set -e autoreload_exclude
__autoreload_snapshot

# --- Test 16: multiple files changed simultaneously ---

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

# --- Test 17: enable and disable subcommands ---

autoreload disable >/dev/null
@test "disable sets autoreload_enabled to 0" "$autoreload_enabled" = 0
autoreload enable >/dev/null
@test "enable clears autoreload_enabled" (not set -q autoreload_enabled; and echo yes) = yes

# --- Test 18: help subcommand ---

set -l output (autoreload help)
@test "help shows commands section" (string match -q '*Commands:*' -- $output; and echo yes) = yes
@test "help shows variables section" (string match -q '*Variables:*' -- $output; and echo yes) = yes

set -l output (autoreload)
@test "bare autoreload shows help" (string match -q '*Commands:*' -- $output; and echo yes) = yes

# --- Test 19: unknown command shows error ---

set -l output (autoreload nonexistent 2>&1)
@test "unknown command shows error" (string match -q '*unknown command*' -- $output; and echo yes) = yes
@test "unknown command suggests help" (string match -q '*autoreload help*' -- $output; and echo yes) = yes

# --- Test 20: __autoreload_key generates correct keys ---

@test "key: aliases.fish -> aliases_fish" (__autoreload_key /some/path/aliases.fish) = aliases_fish
@test "key: my-plugin.fish -> my_plugin_fish" (__autoreload_key /path/my-plugin.fish) = my_plugin_fish
@test "key: a.b.fish -> a_b_fish" (__autoreload_key /path/a.b.fish) = a_b_fish

# --- Test 20b: __autoreload_basename ---

@test "basename: extracts filename" (__autoreload_basename /some/path/foo.fish) = foo.fish
@test "basename: bare filename unchanged" (__autoreload_basename bar.fish) = bar.fish
@test "basename: multiple args" (count (__autoreload_basename /a/one.fish /b/two.fish)) = 2

# --- Test 20c: __autoreload_is_excluded ---

set -g autoreload_exclude skip.fish
@test "is_excluded: matching file returns 0" (__autoreload_is_excluded /path/skip.fish; and echo yes) = yes
@test "is_excluded: non-matching file returns 1" (not __autoreload_is_excluded /path/keep.fish; and echo yes) = yes
set -e autoreload_exclude
@test "is_excluded: unset exclude returns 1" (not __autoreload_is_excluded /path/any.fish; and echo yes) = yes

# --- Test 21: cleanup disabled (default) — current behavior unchanged ---

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

# --- Test 22: cleanup enabled — variable removed on re-source ---

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

# --- Test 23: cleanup enabled — function removed on re-source ---

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

# --- Test 24: cleanup enabled — abbreviation removed on re-source ---

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

# --- Test 25: cleanup enabled — PATH entry removed on re-source ---

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

# --- Test 26: file deletion — side effects cleaned up ---

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

# --- Test 27: teardown hook called on re-source ---

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

# --- Test 28: teardown hook called on file deletion ---

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

# --- Test 29: first re-source has no baseline — old state remains ---

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

# --- Test 30: source failure clears tracking ---

__autoreload_snapshot
echo "set -g __test_fail_var 1" >$__test_conf_d/fail_track.fish
set -l output (__autoreload_check)
@test "source fail: var set on first source" "$__test_fail_var" = 1
# break the file
echo if >$__test_conf_d/fail_track.fish
command touch -t 201201010000 $__test_conf_d/fail_track.fish
set -l output (__autoreload_check 2>&1)
# tracking should be cleared after failure
set -l key (__autoreload_key $__test_conf_d/fail_track.fish)
@test "source fail: tracking cleared" (not contains -- $key $__autoreload_tracked_keys; and echo yes) = yes
command rm -f $__test_conf_d/fail_track.fish
set -e __test_fail_var
__autoreload_snapshot

# --- Test 31: autoreload status shows cleanup info ---

set -l output (autoreload status)
@test "status shows cleanup flag" (string match -q '*cleanup*' -- $output; and echo yes) = yes

set -e autoreload_cleanup

# --- Test 32: uninstall clears tracking variables ---

set -g autoreload_cleanup 1
__autoreload_snapshot
echo "set -g __test_uninstall_var 1" >$__test_conf_d/uninstall_track.fish
set -l output (__autoreload_check)
@test "uninstall tracking: var exists" "$__test_uninstall_var" = 1
set -l key (__autoreload_key $__test_conf_d/uninstall_track.fish)
@test "uninstall tracking: key registered" (contains -- $key $__autoreload_tracked_keys; and echo yes) = yes
_autoreload_uninstall

# Re-source production code for final uninstall test
__test_source_plugin

set -g __fish_config_dir $__test_dir
@test "uninstall tracking: tracking var cleaned" (not set -q __autoreload_added_vars_$key; and echo yes) = yes
@test "uninstall tracking: tracked keys cleared" (test (count $__autoreload_tracked_keys) -eq 0; and echo yes) = yes
command rm -f $__test_conf_d/uninstall_track.fish
set -e __test_uninstall_var
set -e autoreload_cleanup

# --- Test 33: _autoreload_uninstall cleans up ---

_autoreload_uninstall
@test "uninstall removes __autoreload_mtime" (functions -q __autoreload_mtime; or echo gone) = gone
@test "uninstall removes __autoreload_snapshot" (functions -q __autoreload_snapshot; or echo gone) = gone
@test "uninstall removes __autoreload_source_file" (functions -q __autoreload_source_file; or echo gone) = gone
@test "uninstall removes __autoreload_check" (functions -q __autoreload_check; or echo gone) = gone
@test "uninstall removes __autoreload_version" (set -q __autoreload_version; or echo gone) = gone
@test "uninstall removes __autoreload_files" (set -q __autoreload_files; or echo gone) = gone

# --- Cleanup ---

command rm -rf $__test_dir
functions -e __test_source_plugin
set -e __test_plugin_file
set -e __test_dir
set -e __test_conf_d
set -e __test_new_file_var
