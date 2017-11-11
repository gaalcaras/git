#!/bin/sh
#
# Copyright (c) 2007 Christian Couder
#
test_description='Tests git bisect functionality'

exec </dev/null

. ./test-lib.sh

add_line_into_file()
{
    _line=$1
    _file=$2

    if [ -f "$_file" ]; then
        echo "$_line" >> $_file || return $?
        MSG="Add <$_line> into <$_file>."
    else
        echo "$_line" > $_file || return $?
        git add $_file || return $?
        MSG="Create file <$_file> with <$_line> inside."
    fi

    test_tick
    git commit --quiet -m "$MSG" $_file
}

HASH1=
HASH2=
HASH3=
HASH4=

test_expect_success 'set up basic repo with 1 file (hello) and 4 commits' '
     add_line_into_file "1: Hello World" hello &&
     HASH1=$(git rev-parse --verify HEAD) &&
     add_line_into_file "2: A new day for git" hello &&
     HASH2=$(git rev-parse --verify HEAD) &&
     add_line_into_file "3: Another new day for git" hello &&
     HASH3=$(git rev-parse --verify HEAD) &&
     add_line_into_file "4: Ciao for now" hello &&
     HASH4=$(git rev-parse --verify HEAD)
'

# $HASH1 is good, $HASH5 is bad, we skip $HASH3
# but $HASH4 is good,
# so we should find $HASH5 as the first bad commit
HASH5=
test_expect_success 'bisect skip: add line and then a new test' '
	add_line_into_file "5: Another new line." hello &&
	HASH5=$(git rev-parse --verify HEAD) &&
	git bisect start $HASH5 $HASH1 &&
	git bisect skip &&
	git bisect good > my_bisect_log.txt &&
	grep "$HASH5 is the first bad commit" my_bisect_log.txt &&
	git bisect log > log_to_replay.txt &&
	git bisect reset
'


HASH6=
test_expect_success 'bisect run & skip: cannot tell between 2' '
	add_line_into_file "6: Yet a line." hello &&
	HASH6=$(git rev-parse --verify HEAD) &&
	echo "#"\!"/bin/sh" > test_script.sh &&
	echo "sed -ne \\\$p hello | grep Ciao > /dev/null && exit 125" >> test_script.sh &&
	echo "grep line hello > /dev/null" >> test_script.sh &&
	echo "test \$? -ne 0" >> test_script.sh &&
	chmod +x test_script.sh &&
	git bisect start $HASH6 $HASH1 &&
	if git bisect run ./test_script.sh > my_bisect_log.txt
	then
		echo Oops, should have failed.
		false
	else
		test $? -eq 2 &&
		grep "first bad commit could be any of" my_bisect_log.txt &&
		! grep $HASH3 my_bisect_log.txt &&
		! grep $HASH6 my_bisect_log.txt &&
		grep $HASH4 my_bisect_log.txt &&
		grep $HASH5 my_bisect_log.txt
	fi
'

HASH7=
test_expect_success 'bisect run & skip: find first bad' '
	git bisect reset &&
	add_line_into_file "7: Should be the last line." hello &&
	HASH7=$(git rev-parse --verify HEAD) &&
	echo "#"\!"/bin/sh" > test_script.sh &&
	echo "sed -ne \\\$p hello | grep Ciao > /dev/null && exit 125" >> test_script.sh &&
	echo "sed -ne \\\$p hello | grep day > /dev/null && exit 125" >> test_script.sh &&
	echo "grep Yet hello > /dev/null" >> test_script.sh &&
	echo "test \$? -ne 0" >> test_script.sh &&
	chmod +x test_script.sh &&
	git bisect start $HASH7 $HASH1 &&
	git bisect run ./test_script.sh > my_bisect_log.txt &&
	grep "$HASH6 is the first bad commit" my_bisect_log.txt
'

# This creates a "side" branch to test "siblings" cases.
#
# H1-H2-H3-H4-H5-H6-H7  <--other
#            \
#             S5-S6-S7  <--side
#
test_expect_success 'side branch creation' '
	git bisect reset &&
	git checkout -b side $HASH4 &&
	add_line_into_file "5(side): first line on a side branch" hello2 &&
	SIDE_HASH5=$(git rev-parse --verify HEAD) &&
	add_line_into_file "6(side): second line on a side branch" hello2 &&
	SIDE_HASH6=$(git rev-parse --verify HEAD) &&
	add_line_into_file "7(side): third line on a side branch" hello2 &&
	SIDE_HASH7=$(git rev-parse --verify HEAD)
'

test_expect_success 'good merge base when good and bad are siblings' '
	git bisect start "$HASH7" "$SIDE_HASH7" > my_bisect_log.txt &&
	test_i18ngrep "merge base must be tested" my_bisect_log.txt &&
	grep $HASH4 my_bisect_log.txt &&
	git bisect good > my_bisect_log.txt &&
	! grep "merge base must be tested" my_bisect_log.txt &&
	grep $HASH6 my_bisect_log.txt &&
	git bisect reset
'
test_expect_success 'skipped merge base when good and bad are siblings' '
	git bisect start "$SIDE_HASH7" "$HASH7" > my_bisect_log.txt &&
	test_i18ngrep "merge base must be tested" my_bisect_log.txt &&
	grep $HASH4 my_bisect_log.txt &&
	git bisect skip > my_bisect_log.txt 2>&1 &&
	grep "warning" my_bisect_log.txt &&
	grep $SIDE_HASH6 my_bisect_log.txt &&
	git bisect reset
'

test_expect_success 'bad merge base when good and bad are siblings' '
	git bisect start "$HASH7" HEAD > my_bisect_log.txt &&
	test_i18ngrep "merge base must be tested" my_bisect_log.txt &&
	grep $HASH4 my_bisect_log.txt &&
	test_must_fail git bisect bad > my_bisect_log.txt 2>&1 &&
	test_i18ngrep "merge base $HASH4 is bad" my_bisect_log.txt &&
	test_i18ngrep "fixed between $HASH4 and \[$SIDE_HASH7\]" my_bisect_log.txt &&
	git bisect reset
'

# This adds some more commits to have multiple merge bases
#
# H1-H2-H3-H4-H5-H6-H7-H8  <--other
#            \        \
#             S5-S6-S7-S8-S9  <--side
HASH8=
test_expect_success 'extra commits to get multiple merge bases' '
	git checkout "$HASH7" &&
	add_line_into_file "8: last line in main branch" hello &&
	HASH8=$(git rev-parse --verify HEAD) &&
	git checkout "$SIDE_HASH7" &&
	git merge -m "merge HASH7 and SIDE_HASH7" "$HASH7" &&
	SIDE_HASH8=$(git rev-parse --verify HEAD) &&
	add_line_into_file "9: last line in side branch" hello2 &&
	SIDE_HASH9=$(git rev-parse --verify HEAD)
'

test_expect_success 'good merge base when side is good and other is bad' '
	git bisect start "$HASH8" "$SIDE_HASH9" > my_bisect_log.txt &&
	test_i18ngrep "merge base must be tested" my_bisect_log.txt &&
	grep $HASH7 my_bisect_log.txt &&
	git bisect reset
'

test_expect_success 'good merge base when side is bad and other is good' '
	git bisect start "$SIDE_HASH9" "$HASH8" > my_bisect_log.txt &&
	test_i18ngrep "merge base must be tested" my_bisect_log.txt &&
	grep $HASH7 my_bisect_log.txt &&
	git bisect reset
'


# This adds some more commits to have multiple merge bases
#
# H1-H2-H3-H4-H5-H6-H7-H8-H9-H10  <--other
#            \           /  /
#             S5-S6-S7-S8-S9-S10  <--side
HASH9=
test_expect_success 'extra commits to get multiple merge bases merged in other' '
	git checkout "$HASH8" &&
	git merge -m "merge HASH8 and SIDE_HASH8" "$SIDE_HASH8" &&
	HASH9=$(git rev-parse --verify HEAD) &&
	git merge -m "merge HASH9 and SIDE_HASH9" "$SIDE_HASH9" &&
	HASH10=$(git rev-parse --verify HEAD) &&
	git checkout "$SIDE_HASH9" &&
	add_line_into_file "S10: last line in main branch" hello2 &&
	SIDE_HASH10=$(git rev-parse --verify HEAD)
'

test_expect_success 'good merge base when S10 is good and H10 is bad' '
	git bisect start "$HASH10" "$SIDE_HASH10" > my_bisect_log.txt &&
	test_i18ngrep "merge base must be tested" my_bisect_log.txt &&
	grep $SIDE_HASH9 my_bisect_log.txt &&
	git bisect reset
'

test_expect_success 'good merge base when S10 is bad and H10 is good' '
	git bisect start "$SIDE_HASH10" "$HASH10" > my_bisect_log.txt &&
	test_i18ngrep "merge base must be tested" my_bisect_log.txt &&
	grep $SIDE_HASH9 my_bisect_log.txt &&
	git bisect reset
'

# This adds some more commits to have multiple merge bases
# "crossing"
#
# H1-H2-H3-H4-H5-H6-H7-H8-H9-H10-H11-H12  <--other
#            \           /  /   X
#             S5-S6-S7-S8-S9-S10-S11-S12  <--side
test_expect_success 'extra commits to get multiple merge bases merged in other' '
	git checkout "$SIDE_HASH10" &&
	git merge -m "merge HASH10 and SIDE_HASH10" "$HASH10" &&
	SIDE_HASH11=$(git rev-parse --verify HEAD) &&
	git checkout "$HASH10" &&
	git merge -m "merge HASH10 and SIDE_HASH10" "$SIDE_HASH10" &&
	HASH11=$(git rev-parse --verify HEAD) &&
	add_line_into_file "12: last line in main branch" hello &&
	HASH12=$(git rev-parse --verify HEAD) &&
	git checkout "$SIDE_HASH11" &&
	add_line_into_file "S12: last line in main branch" hello2 &&
	SIDE_HASH12=$(git rev-parse --verify HEAD)
'

test_expect_success 'good merge base when S12 is good and H12 is bad' '
  git bisect start "$HASH12" "$SIDE_HASH12" > my_bisect_log.txt &&
  test_i18ngrep "merge base must be tested" my_bisect_log.txt &&
  grep $SIDE_HASH10 my_bisect_log.txt &&
  git bisect good "$SIDE_HASH10" > my_bisect_log.txt &&
  test_i18ngrep "merge base must be tested" my_bisect_log.txt &&
  grep $HASH10 my_bisect_log.txt &&
  git bisect good "$HASH10" > my_bisect_log.txt &&
  test_i18ngrep "merge base must be tested" my_bisect_log.txt &&
  git bisect reset
'

# This creates a few more commits (A and B) to test "siblings" cases
# when a good and a bad rev have many merge bases.
#
# We should have the following:
#
# H1-H2-H3-H4-H5-H6-H7
#            \  \     \
#             S5-A     \
#              \        \
#               S6-S7----B
#
# And there A and B have 2 merge bases (S5 and H5) that should be
# reported by "git merge-base --all A B".
#
test_expect_success 'many merge bases creation' '
	git checkout "$SIDE_HASH5" &&
	git merge -m "merge HASH5 and SIDE_HASH5" "$HASH5" &&
	A_HASH=$(git rev-parse --verify HEAD) &&
	git checkout side &&
	git merge -m "merge HASH7 and SIDE_HASH7" "$HASH7" &&
	B_HASH=$(git rev-parse --verify HEAD) &&
	git merge-base --all "$A_HASH" "$B_HASH" > merge_bases.txt &&
	test_line_count = 2 merge_bases.txt &&
	grep "$HASH5" merge_bases.txt &&
	grep "$SIDE_HASH5" merge_bases.txt
'

test_expect_success 'good merge bases when good and bad are siblings' '
	git bisect start "$B_HASH" "$A_HASH" > my_bisect_log.txt &&
	test_i18ngrep "merge base must be tested" my_bisect_log.txt &&
	git bisect good > my_bisect_log2.txt &&
	test_i18ngrep "merge base must be tested" my_bisect_log2.txt &&
	{
		{
			grep "$SIDE_HASH5" my_bisect_log.txt &&
			grep "$HASH5" my_bisect_log2.txt
		} || {
			grep "$SIDE_HASH5" my_bisect_log2.txt &&
			grep "$HASH5" my_bisect_log.txt
		}
	} &&
	git bisect reset
'

test_expect_success 'optimized merge base checks' '
	git bisect start "$HASH7" "$SIDE_HASH7" > my_bisect_log.txt &&
	test_i18ngrep "merge base must be tested" my_bisect_log.txt &&
	grep "$HASH4" my_bisect_log.txt &&
	git bisect good > my_bisect_log2.txt &&
	test -f ".git/BISECT_ANCESTORS_OK" &&
	test "$HASH6" = $(git rev-parse --verify HEAD) &&
	git bisect bad > my_bisect_log3.txt &&
	git bisect good "$A_HASH" > my_bisect_log4.txt &&
	test_i18ngrep "merge base must be tested" my_bisect_log4.txt &&
	test_must_fail test -f ".git/BISECT_ANCESTORS_OK"
'

test_done
