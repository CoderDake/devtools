# Details about tests

## .test/2022-05-19-1652989495_perfConPlusAnotherFile 
This test runs just the `flutter test test/performance/performance_controller_test.dart test/inspector/inspector_integration_test.dart > $TEST_NAME`
to try to see if just running 2 test files against each other can cause the failures

The this was rerun 100 times with the following failures
PASSES: 96 FAILS: 4

### Failure that occured in all 4
```
00:40 +0: /usr/local/google/home/danchevalier/development/devtools/packages/devtools_app/test/performance/performance_controller_test.dart: PerformanceController processOfflineData
Attempted to call extension 'ext.flutter.inspector.structuredErrors', but no service with that name exists
00:40 +0: /usr/local/google/home/danchevalier/development/devtools/packages/devtools_app/test/inspector/inspector_integration_test.dart: screenshot tests navigation
Attempted to call extension 'ext.flutter.inspector.structuredErrors', but no service with that name exists
00:41 +0: /usr/local/google/home/danchevalier/development/devtools/packages/devtools_app/test/performance/performance_controller_test.dart: PerformanceController processOfflineData
Could not find UI thread and / or Raster thread from names: (DartWorker (248490), DartWorker (248489), DartWorker (248488), ..., Dart Profiler ThreadInterrupter (248485), io.flutter.test..platform (248459))
00:41 +0 -1: /usr/local/google/home/danchevalier/development/devtools/packages/devtools_app/test/performance/performance_controller_test.dart: PerformanceController processOfflineData [E]
  Expected: true
    Actual: <false>

  package:test_api                                        expect
  package:flutter_test/src/widget_tester.dart 455:16      expect
  test/performance/performance_controller_test.dart 46:9  main.<fn>.<fn>

Retry: PerformanceController processOfflineData
  Expected: <1>
    Actual: <-1>

  package:test_api                                        expect
  package:flutter_test/src/widget_tester.dart 455:16      expect
  test/performance/performance_controller_test.dart 60:9  main.<fn>.<fn>

Retry: PerformanceController processOfflineData
  Expected: <1>
    Actual: <-1>

  package:test_api                                        expect
  package:flutter_test/src/widget_tester.dart 455:16      expect
  test/performance/performance_controller_test.dart 60:9  main.<fn>.<fn>

Retry: PerformanceController processOfflineData
  Expected: <1>
    Actual: <-1>

  package:test_api                                        expect
  package:flutter_test/src/widget_tester.dart 455:16      expect
  test/performance/performance_controller_test.dart 60:9  main.<fn>.<fn>

01:28 +6 -1: /usr/local/google/home/danchevalier/development/devtools/packages/devtools_app/test/inspector/inspector_integration_test.dart: widget errors show navigator and error labels
Attempted to call extension 'ext.flutter.inspector.structuredErrors', but no service with that name exists
01:49 +7 -1: Some tests failed.
```

### Analysis
- The above 4 failures all had the same failure. 
- The exception that fails is the following:
```
expect(
    performanceController.processor.uiThreadId,
    equals(testUiThreadId),
);
```
- the logs from the test mean that `performanceController.processor.uiThreadId` is -1
- looking further into how the performanceController initializes this value, it looks like a value of -1 is assigned when the threadIdFor Events can't find the trace event
    - see: https://github.com/flutter/devtools/blob/98c79871b2ea2dff20b5dd04eedd1b11409b8518/packages/devtools_app/lib/src/screens/performance/performance_controller.dart#L738
-  this would mean that the offlineData being passed to processOfflineData doesn't have a trace event with name 'Animator::BeginFrame'

###
Next steps:
- since the offline data doesn't seem to have the right data in it when it was processed, then I'm going to log the data on the way into the test and rerun this one. that way we will see if it is truly different or not set when this error comes up.

## .test/2022-05-20-1653010070_testWithPrints/

https://github.com/CoderDake/devtools/commit/3963f518126715867f7fa4bc0c9a42bf03445f4c

This test runs just the `flutter test test/performance/performance_controller_test.dart test/inspector/inspector_integration_test.dart > $TEST_NAME` with print statements in order to see if there truly is no ui thread in the trace events.

### Failures
```
DAKE processOfflineData: offlineTimelineData offlineTimelineData.traceEvents.map((e) => e['name']): (VSYNC, Animator::BeginFrame, Framework Workload, ..., PipelineConsume, GPURasterizer::Draw)
00:22 +0 -1: /usr/local/google/home/danchevalier/development/devtools/packages/devtools_app/test/performance/performance_controller_test.dart: PerformanceController processOfflineData [E]
  Expected: true
    Actual: <false>

  package:test_api                                        expect
  package:flutter_test/src/widget_tester.dart 455:16      expect
  test/performance/performance_controller_test.dart 49:9  main.<fn>.<fn>

Retry: PerformanceController processOfflineData
DAKE processOfflineData: offlineTimelineData offlineTimelineData.traceEvents.map((e) => e['name']): (VSYNC, Animator::BeginFrame, Framework Workload, ..., PipelineConsume, GPURasterizer::Draw)
DAKE uiThreadId is -1: traceEvents:traceEvents.map((e) => e.event.name) ()
  Expected: <1>
    Actual: <-1>

  package:test_api                                        expect
  package:flutter_test/src/widget_tester.dart 455:16      expect
  test/performance/performance_controller_test.dart 63:9  main.<fn>.<fn>

Retry: PerformanceController processOfflineData
DAKE processOfflineData: offlineTimelineData offlineTimelineData.traceEvents.map((e) => e['name']): ()
DAKE uiThreadId is -1: traceEvents:traceEvents.map((e) => e.event.name) ()
  Expected: <1>
    Actual: <-1>

  package:test_api                                        expect
  package:flutter_test/src/widget_tester.dart 455:16      expect
  test/performance/performance_controller_test.dart 63:9  main.<fn>.<fn>

Retry: PerformanceController processOfflineData
DAKE processOfflineData: offlineTimelineData offlineTimelineData.traceEvents.map((e) => e['name']): ()
DAKE uiThreadId is -1: traceEvents:traceEvents.map((e) => e.event.name) ()
  Expected: <1>
    Actual: <-1>

  package:test_api                                        expect
  package:flutter_test/src/widget_tester.dart 455:16      expect
  test/performance/performance_controller_test.dart 63:9  main.<fn>.<fn>

```

### Analysis
Here we can see the test retrying and on each instance, the offlineData passed into the test has no entries. 
This makes me curious if there were other failures that ended up repairing themselves.

The following was run to determine if there were any errors that resolved themselves
```
danchevalier@dake:~/development/devtools/packages/devtools_app/.test/2022-05-20-1653010070_testWithPrints$ grep -r "Retry: PerformanceController processOfflineData"
fails/test-89.log:Retry: PerformanceController processOfflineData
fails/test-89.log:Retry: PerformanceController processOfflineData
fails/test-89.log:Retry: PerformanceController processOfflineData
fails/test-74.log:Retry: PerformanceController processOfflineData
fails/test-74.log:Retry: PerformanceController processOfflineData
fails/test-74.log:Retry: PerformanceController processOfflineData
fails/test-12.log:Retry: PerformanceController processOfflineData
fails/test-12.log:Retry: PerformanceController processOfflineData
fails/test-12.log:Retry: PerformanceController processOfflineData
```