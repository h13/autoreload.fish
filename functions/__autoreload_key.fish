function __autoreload_key -a file
    __autoreload_basename $file | string escape --style=var
end
