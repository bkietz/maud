#!/usr/bin/sh

scan() { # expanded from CMAKE_CXX_SCANDEP_SOURCE
  echo "SCANNING $1 ==> $2"
}

cat "${1:--}" |
while IFS= read line # lines are "source file path;output ddi path"
do
  source=${line%%;*}
  ddi=${line#${source};}
  scan "$source" "$ddi"
done
# https://www.etalabs.net/sh_tricks.html
