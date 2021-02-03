#!/usr/bin/env bash
[ -z $1 ] && echo "No git root dir given" && exit 1
git_root=$1
echo cd $git_root
cd $git_root

from="1 Jan, 2020"
to="1 Jan, 2021"
[ -z $2 ] && echo "No start_date given, use '1 Jan, 2020'" || from=$2
[ -z $3 ] && echo "No end_date given, use '1 Jan, 2021'" || to=$3
echo "Date range $from -> $to"

users=$(git shortlog -sn --no-merges --since="$from" --before="$to" | awk '{printf "%s %s\n", $2, $3}')
IFS=$'\n'
echo -e "User name;Files changed;Lines added;Lines deleted;Total lines (delta);Add./Del. ratio (1:n);Commit count"

for userName in $users
do
	result=$(git log --author="$userName" --no-merges --shortstat  --since="$from" --before="$to" | grep -E "fil(e|es) changed" | awk '{files+=$1; inserted+=$4; deleted+=$6; delta+=$4-$6; ratio=deleted/inserted} END {printf "%s;%s;%s;%s;%s", files, inserted, deleted, delta, ratio }' -)
	countCommits=$(git shortlog -sn --no-merges  --since="$from" --before="$to" --author="$userName" | awk '{print $1}')
	if [[ ${result} != ';;;;' ]]
	then
		echo -e "$userName;$result;$countCommits"
	fi
done

