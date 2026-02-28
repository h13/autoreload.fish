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
set -l plugin_file (builtin realpath (status dirname)/../conf.d/autoreload.fish)
string replace 'if not status is-interactive' 'if false' <$plugin_file \
    | string replace 'set -g __autoreload_self (builtin realpath (status filename))' '# __autoreload_self already set by test' \
    | string replace 'if test -z "$__autoreload_self"' 'if false' \
    | string replace -- '--on-event fish_prompt' '' \
    | source

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
echo "if" >$__test_conf_d/broken.fish
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
@test "autoreload status shows version" (string match -q '*v1.2.0*' -- $output; and echo yes) = yes
@test "autoreload status lists tracked files" (string match -q '*dummy.fish*' -- $output; and echo yes) = yes
@test "autoreload version returns version" (autoreload version) = 1.2.0

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

# --- Test 20: _autoreload_uninstall cleans up ---

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
