function __autoreload_key -a file
    string escape --style=var -- (__autoreload_basename $file)
end
