#!/bin/sh
#
# Remove a parent from a commit.

commit="$1"

test $(egrep "^parent " "$commit" | wc -l) -eq 2 &&
	sed -i '3d' "$commit"
