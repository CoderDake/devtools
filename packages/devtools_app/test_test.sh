#!/bin/bash -x

COUNT=50
TEST_NAME=$1
NOW=$(date +"%Y-%m-%d-%s")
TEST_DIR=.test/${NOW}_${TEST_NAME}
PASS_DIR=$TEST_DIR/passes
FAIL_DIR=$TEST_DIR/fails

PASS_COUNT=0
FAIL_COUNT=0

mkdir -p $PASS_DIR
mkdir -p $FAIL_DIR

flutter clean

for (( i=1; i<=$COUNT; i++ ))
do
  TEST_NAME=.tmp_test.log
  flutter test test/performance/performance_controller_test.dart  > $TEST_NAME
  if [ $? -eq 0 ]; then
    PASS_COUNT=$((PASS_COUNT+1))
    mv $TEST_NAME $PASS_DIR/test-$i.log
  else
    FAIL_COUNT=$((FAIL_COUNT+1))
    mv $TEST_NAME $FAIL_DIR/test-$i.log
  fi
  echo "PASSES: $PASS_COUNT FAILS: $FAIL_COUNT"
done
