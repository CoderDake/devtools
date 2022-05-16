#!/bin/bash -x

i=0
while [ $i -ne 5 ]
do
        i=$(($i+1))
	BRANCH=$1-$i
#	bash -c "git checkout -b $BRANCH"
	git checkout -b $BRANCH
	git push -u origin $BRANCH
done
