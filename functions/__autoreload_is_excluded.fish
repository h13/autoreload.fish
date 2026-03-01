function __autoreload_is_excluded -a file
    set -q autoreload_exclude[1]; or return 1
    contains -- (__autoreload_basename $file) $autoreload_exclude
end
