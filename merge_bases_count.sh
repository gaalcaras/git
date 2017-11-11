#!/bin/sh
#
# Count merge bases with bisect

BISECT_LOG="my_bisect_log.txt"
# export LC_ALL=C
touch $BISECT_LOG

hash1=$1
hash2=$2

git bisect start $hash1 $hash2 > $BISECT_LOG
count=0

while grep -q "merge base must be tested" $BISECT_LOG
do
  git bisect good > $BISECT_LOG
  count=$(($count + 1))
done

echo "Merge bases: $count"

git bisect reset
rm $BISECT_LOG
