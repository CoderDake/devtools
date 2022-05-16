#!/bin/bash -xe

i=0
while [ $i -ne 5 ]
do
        i=$(($i+1))
	BRANCH=$1-$i
	FILE=test${i}.txt
#	bash -c "git checkout -b $BRANCH"
	git checkout  $BRANCH
	echo "$BRANCH" >> $FILE 
	git add $FILE
	git commit -m "adding file"
	git push origin $BRANCH
done
