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

# --- Test 8: autoreload status command ---

__autoreload_snapshot
set -l output (autoreload status)
@test "autoreload status shows version" (string match -q '*v1.1.0*' -- $output; and echo yes) = yes
@test "autoreload status lists tracked files" (string match -q '*dummy.fish*' -- $output; and echo yes) = yes
@test "autoreload version returns version" (autoreload version) = 1.1.0

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
sleep 1
touch $__test_conf_d/dummy.fish
set -l output (__autoreload_check)
@test "quiet mode suppresses sourced message" -z "$output"
set -e autoreload_quiet

# --- Test 11: _autoreload_uninstall cleans up ---

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
