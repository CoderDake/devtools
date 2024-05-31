// Copyright 2024 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:devtools_app_shared/service.dart';
import 'package:devtools_app_shared/utils.dart';
import 'package:devtools_shared/devtools_shared.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:vm_service/vm_service.dart';

import '../../../service/vm_service_wrapper.dart';
import '../../../shared/diagnostics/diagnostics_node.dart';
import '../../../shared/diagnostics/inspector_service.dart';
import '../../../shared/globals.dart';
import '../../../shared/primitives/byte_utils.dart';
import '../../../shared/primitives/message_bus.dart';
import '../../../shared/primitives/utils.dart';
import '../../../shared/ui/filter.dart';
import '../../../shared/ui/search.dart';
import '../logging_controller.dart'
    show NavigationInfo, ServiceExtensionStateChangedInfo;
import '../logging_screen.dart';

final _log = Logger('logging_controller');

// For performance reasons, we drop old logs in batches, so the log will grow
// to kMaxLogItemsUpperBound then truncate to kMaxLogItemsLowerBound.

bool _verboseDebugging = false;

Future<String> _retrieveFullStringValue(
  VmServiceWrapper? service,
  IsolateRef isolateRef,
  InstanceRef stringRef,
) {
  final fallback = '${stringRef.valueAsString}...';
  // TODO(kenz): why is service null?

  return service
          ?.retrieveFullStringValue(
            isolateRef.id!,
            stringRef,
            onUnavailable: (truncatedValue) => fallback,
          )
          .then((value) => value ?? fallback) ??
      Future.value(fallback);
}

const _flutterFirstFrameKind = 'Flutter.FirstFrame';
const _flutterFrameworkInitializationKind = 'Flutter.FrameworkInitialization';

class LoggingControllerV2 extends DisposableController
    with AutoDisposeControllerMixin, FilterControllerMixin<LogDataV2> {
  LoggingControllerV2() {
    addAutoDisposeListener(serviceConnection.serviceManager.connectedState, () {
      if (serviceConnection.serviceManager.connectedState.value.connected) {
        _handleConnectionStart(serviceConnection.serviceManager.service!);

        autoDisposeStreamSubscription(
          serviceConnection.serviceManager.service!.onIsolateEvent
              .listen((event) {
            messageBus.addEvent(
              BusEvent(
                'debugger',
                data: event,
              ),
            );
          }),
        );
      }
    });
    if (serviceConnection.serviceManager.connectedAppInitialized) {
      _handleConnectionStart(serviceConnection.serviceManager.service!);
    }
    _handleBusEvents();
  }

  static const kindFilterId = 'logging-kind-filter';

  final StreamController<String> _logStatusController =
      StreamController.broadcast();

  /// A stream of events for the textual description of the log contents.
  ///
  /// See also [statusText].
  Stream<String> get onLogStatusChanged => _logStatusController.stream;

  List<LogDataV2> data = <LogDataV2>[];

  final selectedLog = ValueNotifier<LogDataV2?>(null);

  void _updateData(List<LogDataV2> logs) {
    data = logs;
    filteredData.replaceAll(logs);
    _updateSelection();
    _updateStatus();
  }

  void _updateSelection() {
    final selected = selectedLog.value;
    if (selected != null) {
      final List<LogDataV2> logs = filteredData.value;
      if (!logs.contains(selected)) {
        selectedLog.value = null;
      }
    }
  }

  ObjectGroup get objectGroup =>
      serviceConnection.consoleService.objectGroup as ObjectGroup;

  String get statusText {
    final int totalCount = data.length;
    final int showingCount = filteredData.value.length;

    String label;

    label = totalCount == showingCount
        ? nf.format(totalCount)
        : 'showing ${nf.format(showingCount)} of ' '${nf.format(totalCount)}';

    label = '$label ${pluralize('event', totalCount)}';

    return label;
  }

  void _updateStatus() {
    final label = statusText;
    _logStatusController.add(label);
  }

  void clear() {
    _updateData([]);
    serviceConnection.errorBadgeManager.clearErrors(LoggingScreen.id);
  }

  void _handleConnectionStart(VmServiceWrapper service) {
    // Log stdout events.
    final _StdoutEventHandler stdoutHandler =
        _StdoutEventHandler(this, 'stdout');
    autoDisposeStreamSubscription(
      service.onStdoutEventWithHistorySafe.listen(stdoutHandler.handle),
    );

    // Log stderr events.
    final _StdoutEventHandler stderrHandler =
        _StdoutEventHandler(this, 'stderr', isError: true);
    autoDisposeStreamSubscription(
      service.onStderrEventWithHistorySafe.listen(stderrHandler.handle),
    );

    // Log GC events.
    autoDisposeStreamSubscription(service.onGCEvent.listen(_handleGCEvent));

    // Log `dart:developer` `log` events.
    autoDisposeStreamSubscription(
      service.onLoggingEventWithHistorySafe.listen(_handleDeveloperLogEvent),
    );

    // Log Flutter extension events.
    autoDisposeStreamSubscription(
      service.onExtensionEventWithHistorySafe.listen(_handleExtensionEvent),
    );
  }

  void _handleExtensionEvent(Event e) {
    // Events to show without a summary in the table.
    const Set<String> untitledEvents = {
      _flutterFirstFrameKind,
      _flutterFrameworkInitializationKind,
    };

    if (e.extensionKind == _FrameInfo.eventName) {
      final _FrameInfo frame = _FrameInfo(e.extensionData!.data);

      final String frameId = '#${frame.number}';
      final String frameInfoText =
          '$frameId ${frame.elapsedMs.toStringAsFixed(1).padLeft(4)}ms ';

      log(
        LogDataV2(
          e.extensionKind!.toLowerCase(),
          jsonEncode(e.extensionData!.data),
          e.timestamp,
          summary: frameInfoText,
        ),
      );
    } else if (e.extensionKind == _ImageSizesForFrame.eventName) {
      final images = _ImageSizesForFrame.from(e.extensionData!.data);

      for (final image in images) {
        log(
          LogDataV2(
            e.extensionKind!.toLowerCase(),
            jsonEncode(image.json),
            e.timestamp,
            summary: image.summary,
          ),
        );
      }
    } else if (e.extensionKind == NavigationInfo.eventName) {
      final NavigationInfo navInfo = NavigationInfo.from(e.extensionData!.data);

      log(
        LogDataV2(
          e.extensionKind!.toLowerCase(),
          jsonEncode(e.json),
          e.timestamp,
          summary: navInfo.routeDescription,
        ),
      );
    } else if (untitledEvents.contains(e.extensionKind)) {
      log(
        LogDataV2(
          e.extensionKind!.toLowerCase(),
          jsonEncode(e.json),
          e.timestamp,
          summary: '',
        ),
      );
    } else if (e.extensionKind == ServiceExtensionStateChangedInfo.eventName) {
      final ServiceExtensionStateChangedInfo changedInfo =
          ServiceExtensionStateChangedInfo.from(e.extensionData!.data);

      log(
        LogDataV2(
          e.extensionKind!.toLowerCase(),
          jsonEncode(e.json),
          e.timestamp,
          summary: '${changedInfo.extension}: ${changedInfo.value}',
        ),
      );
    } else if (e.extensionKind == 'Flutter.Error') {
      // TODO(pq): add tests for error extension handling once framework changes
      // are landed.
      final RemoteDiagnosticsNode node = RemoteDiagnosticsNode(
        e.extensionData!.data,
        objectGroup,
        false,
        null,
      );
      // Workaround the fact that the error objects from the server don't have
      // style error.
      node.style = DiagnosticsTreeStyle.error;
      if (_verboseDebugging) {
        _log.info('node toStringDeep:######\n${node.toStringDeep()}\n###');
      }

      final RemoteDiagnosticsNode summary = _findFirstSummary(node) ?? node;
      log(
        LogDataV2(
          e.extensionKind!.toLowerCase(),
          jsonEncode(e.extensionData!.data),
          e.timestamp,
          summary: summary.toDiagnosticsNode().toString(),
        ),
      );
    } else {
      log(
        LogDataV2(
          e.extensionKind!.toLowerCase(),
          jsonEncode(e.json),
          e.timestamp,
          summary: e.json.toString(),
        ),
      );
    }
  }

  void _handleGCEvent(Event e) {
    final HeapSpace newSpace = HeapSpace.parse(e.json!['new'])!;
    final HeapSpace oldSpace = HeapSpace.parse(e.json!['old'])!;
    final isolateRef = (e.json!['isolate'] as Map).cast<String, Object?>();

    final int usedBytes = newSpace.used! + oldSpace.used!;
    final int capacityBytes = newSpace.capacity! + oldSpace.capacity!;

    final int time = ((newSpace.time! + oldSpace.time!) * 1000).round();

    final String summary = '${isolateRef['name']} • '
        '${e.json!['reason']} collection in $time ms • '
        '${printBytes(usedBytes, unit: ByteUnit.mb, includeUnit: true)} used of '
        '${printBytes(capacityBytes, unit: ByteUnit.mb, includeUnit: true)}';

    final event = <String, Object>{
      'reason': e.json!['reason'],
      'new': newSpace.json,
      'old': oldSpace.json,
      'isolate': isolateRef,
    };

    final String message = jsonEncode(event);
    log(LogDataV2('gc', message, e.timestamp, summary: summary));
  }

  void _handleDeveloperLogEvent(Event e) {
    final VmServiceWrapper? service = serviceConnection.serviceManager.service;

    final logRecord = _LogRecord(e.json!['logRecord']);

    String? loggerName =
        _valueAsString(InstanceRef.parse(logRecord.loggerName));
    if (loggerName == null || loggerName.isEmpty) {
      loggerName = 'log';
    }
    final level = logRecord.level;
    final messageRef = InstanceRef.parse(logRecord.message)!;
    String? summary = _valueAsString(messageRef);
    if (messageRef.valueAsStringIsTruncated == true) {
      summary = '${summary!}...';
    }
    final error = InstanceRef.parse(logRecord.error);
    final stackTrace = InstanceRef.parse(logRecord.stackTrace);

    final String? details = summary;
    Future<String> Function()? detailsComputer;

    // If the message string was truncated by the VM, or the error object or
    // stackTrace objects were non-null, we need to ask the VM for more
    // information in order to render the log entry. We do this asynchronously
    // on-demand using the `detailsComputer` Future.
    if (messageRef.valueAsStringIsTruncated == true ||
        _isNotNull(error) ||
        _isNotNull(stackTrace)) {
      detailsComputer = () async {
        // Get the full string value of the message.
        String result =
            await _retrieveFullStringValue(service, e.isolate!, messageRef);

        // Get information about the error object. Some users of the
        // dart:developer log call may pass a data payload in the `error`
        // field, encoded as a json encoded string, so handle that case.
        if (_isNotNull(error)) {
          if (error!.valueAsString != null) {
            final String errorString =
                await _retrieveFullStringValue(service, e.isolate!, error);
            result += '\n\n$errorString';
          } else {
            // Call `toString()` on the error object and display that.
            final toStringResult = await service!.invoke(
              e.isolate!.id!,
              error.id!,
              'toString',
              <String>[],
              disableBreakpoints: true,
            );

            if (toStringResult is ErrorRef) {
              final String? errorString = _valueAsString(error);
              result += '\n\n$errorString';
            } else if (toStringResult is InstanceRef) {
              final String str = await _retrieveFullStringValue(
                service,
                e.isolate!,
                toStringResult,
              );
              result += '\n\n$str';
            }
          }
        }

        // Get info about the stackTrace object.
        if (_isNotNull(stackTrace)) {
          result += '\n\n${_valueAsString(stackTrace)}';
        }

        return result;
      };
    }

    const int severeIssue = 1000;
    final bool isError = level != null && level >= severeIssue ? true : false;

    log(
      LogDataV2(
        loggerName,
        details,
        e.timestamp,
        isError: isError,
        summary: summary,
        detailsComputer: detailsComputer,
      ),
    );
  }

  void log(LogDataV2 log) {
    data.add(log);
    // TODO(danchevalier): Add filtersearch behavior
    // TODO(danchevalier): Add Search behavior
    // TODO(danchevalier): Add Selection update behavior
    // TODO(danchevalier): Add status update
    filteredData.add(log);
  }

  static RemoteDiagnosticsNode? _findFirstSummary(RemoteDiagnosticsNode node) {
    if (node.level == DiagnosticLevel.summary) {
      return node;
    }
    RemoteDiagnosticsNode? summary;
    for (final property in node.inlineProperties) {
      summary = _findFirstSummary(property);
      if (summary != null) return summary;
    }

    for (final child in node.childrenNow) {
      summary = _findFirstSummary(child);
      if (summary != null) return summary;
    }

    return null;
  }

  void _handleBusEvents() {
    // TODO(jacobr): expose the messageBus for use by vm tests.
    autoDisposeStreamSubscription(
      messageBus.onEvent(type: 'reload.end').listen((BusEvent event) {
        log(
          LogDataV2(
            'hot.reload',
            event.data as String?,
            DateTime.now().millisecondsSinceEpoch,
          ),
        );
      }),
    );

    autoDisposeStreamSubscription(
      messageBus.onEvent(type: 'restart.end').listen((BusEvent event) {
        log(
          LogDataV2(
            'hot.restart',
            event.data as String?,
            DateTime.now().millisecondsSinceEpoch,
          ),
        );
      }),
    );

    // Listen for debugger events.
    autoDisposeStreamSubscription(
      messageBus
          .onEvent()
          .where(
            (event) =>
                event.type == 'debugger' || event.type.startsWith('debugger.'),
          )
          .listen(_handleDebuggerEvent),
    );

    // Listen for DevTools internal events.
    autoDisposeStreamSubscription(
      messageBus
          .onEvent()
          .where((event) => event.type.startsWith('devtools.'))
          .listen(_handleDevToolsEvent),
    );
  }

  void _handleDebuggerEvent(BusEvent event) {
    final Event debuggerEvent = event.data as Event;

    // Filter ServiceExtensionAdded events as they're pretty noisy.
    if (debuggerEvent.kind == EventKind.kServiceExtensionAdded) {
      return;
    }

    log(
      LogDataV2(
        event.type,
        jsonEncode(debuggerEvent.json),
        debuggerEvent.timestamp,
        summary: '${debuggerEvent.kind} ${debuggerEvent.isolate!.id}',
      ),
    );
  }

  void _handleDevToolsEvent(BusEvent event) {
    var details = event.data.toString();
    String? summary;

    if (details.contains('\n')) {
      final lines = details.split('\n');
      summary = lines.first;
      details = lines.sublist(1).join('\n');
    }

    log(
      LogDataV2(
        event.type,
        details,
        DateTime.now().millisecondsSinceEpoch,
        summary: summary,
      ),
    );
  }
}

extension type _LogRecord(Map<String, dynamic> json) {
  int? get level => json['level'];

  Map<String, Object?> get loggerName => json['loggerName'];

  Map<String, Object?> get message => json['message'];

  Map<String, Object?> get error => json['error'];

  Map<String, Object?> get stackTrace => json['stackTrace'];
}

/// Receive and log stdout / stderr events from the VM.
///
/// This class buffers the events for up to 1ms. This is in order to combine a
/// stdout message and its newline. Currently, `foo\n` is sent as two VM events;
/// we wait for up to 1ms when we get the `foo` event, to see if the next event
/// is a single newline. If so, we add the newline to the previous log message.
class _StdoutEventHandler {
  _StdoutEventHandler(
    this.loggingController,
    this.name, {
    this.isError = false,
  });

  final LoggingControllerV2 loggingController;
  final String name;
  final bool isError;

  LogDataV2? buffer;
  Timer? timer;

  void handle(Event e) {
    final String message = decodeBase64(e.bytes!);

    if (buffer != null) {
      timer?.cancel();

      if (message == '\n') {
        loggingController.log(
          LogDataV2(
            buffer!.kind,
            buffer!.details! + message,
            buffer!.timestamp,
            summary: buffer!.summary! + message,
            isError: buffer!.isError,
          ),
        );
        buffer = null;
        return;
      }

      loggingController.log(buffer!);
      buffer = null;
    }

    const maxLength = 200;

    String summary = message;
    if (message.length > maxLength) {
      summary = message.substring(0, maxLength);
    }

    final LogDataV2 data = LogDataV2(
      name,
      message,
      e.timestamp,
      summary: summary,
      isError: isError,
    );

    if (message == '\n') {
      loggingController.log(data);
    } else {
      buffer = data;
      timer = Timer(const Duration(milliseconds: 1), () {
        loggingController.log(buffer!);
        buffer = null;
      });
    }
  }
}

bool _isNotNull(InstanceRef? serviceRef) {
  return serviceRef != null && serviceRef.kind != 'Null';
}

String? _valueAsString(InstanceRef? ref) {
  if (ref == null) {
    return null;
  }

  if (ref.valueAsString == null) {
    return ref.valueAsString;
  }

  return ref.valueAsStringIsTruncated == true
      ? '${ref.valueAsString}...'
      : ref.valueAsString;
}

/// A log data object that includes optional summary information about whether
/// the log entry represents an error entry, the log entry kind, and more
/// detailed data for the entry.
///
/// The details can optionally be loaded lazily on first use. If this is the
/// case, this log entry will have a non-null `detailsComputer` field. After the
/// data is calculated, the log entry will be modified to contain the calculated
/// `details` data.
class LogDataV2 with SearchableDataMixin {
  LogDataV2(
    this.kind,
    this._details,
    this.timestamp, {
    this.summary,
    this.isError = false,
    this.detailsComputer,
    this.node,
  });

  final String kind;
  final int? timestamp;
  final bool isError;
  final String? summary;

  final RemoteDiagnosticsNode? node;
  String? _details;
  Future<String> Function()? detailsComputer;

  static const JsonEncoder prettyPrinter = JsonEncoder.withIndent('  ');

  String? get details => _details;

  bool get needsComputing => detailsComputer != null;

  Future<void> compute() async {
    _details = await detailsComputer!();
    detailsComputer = null;
  }

  String? prettyPrinted() {
    if (needsComputing) {
      return details;
    }

    try {
      return prettyPrinter
          .convert(jsonDecode(details!))
          .replaceAll(r'\n', '\n');
    } catch (_) {
      return details;
    }
  }

  @override
  bool matchesSearchToken(RegExp regExpSearch) {
    return kind.caseInsensitiveContains(regExpSearch) ||
        (summary?.caseInsensitiveContains(regExpSearch) == true) ||
        (details?.caseInsensitiveContains(regExpSearch) == true);
  }

  @override
  String toString() => 'LogData($kind, $timestamp)';
}

extension type _FrameInfo(Map<String, dynamic> _json) {
  static const String eventName = 'Flutter.Frame';

  int? get number => _json['number'];
  num get elapsedMs => (_json['elapsed'] as num) / 1000;
}

extension type _ImageSizesForFrame(Map<String, dynamic> json) {
  static const String eventName = 'Flutter.ImageSizesForFrame';

  static List<_ImageSizesForFrame> from(Map<String, dynamic> data) {
    //     "packages/flutter_gallery_assets/assets/icons/material/2.0x/material.png": {
    //       "source": "packages/flutter_gallery_assets/assets/icons/material/2.0x/material.png",
    //       "displaySize": {
    //         "width": 64.0,
    //         "height": 63.99999999999999
    //       },
    //       "imageSize": {
    //         "width": 128.0,
    //         "height": 128.0
    //       },
    //       "displaySizeInBytes": 21845,
    //       "decodedSizeInBytes": 87381
    //     }

    return data.values.map((entry_) => _ImageSizesForFrame(entry_)).toList();
  }

  String get source => json['source'];

  _ImageSize get displaySize => _ImageSize(json['displaySize']);

  _ImageSize get imageSize => _ImageSize(json['imageSize']);

  int? get displaySizeInBytes => json['displaySizeInBytes'];

  int? get decodedSizeInBytes => json['decodedSizeInBytes'];

  String get summary {
    final file = path.basename(source);

    final double expansion =
        math.sqrt(decodedSizeInBytes ?? 0) / math.sqrt(displaySizeInBytes ?? 1);

    return 'Image $file • displayed at '
        '${displaySize.width.round()}x${displaySize.height.round()}'
        ' • created at '
        '${imageSize.width.round()}x${imageSize.height.round()}'
        ' • ${expansion.toStringAsFixed(1)}x';
  }
}

extension type _ImageSize(Map<String, dynamic> json) {
  double get width => json['width'];

  double get height => json['height'];
}