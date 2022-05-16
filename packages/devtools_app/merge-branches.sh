#!/bin/bash -xe

i=0
while [ $i -ne 5 ]
do
        i=$(($i+1))
	BRANCH=$1-$i
	FILE=test${i}.txt
#	bash -c "git checkout -b $BRANCH"
	git checkout  $BRANCH
	git merge $1-1 -m "MERGE $1-1 into self"
	git push origin $BRANCH
done
