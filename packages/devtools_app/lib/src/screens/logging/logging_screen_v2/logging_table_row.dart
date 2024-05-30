// Copyright 2024 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';

import 'logging_controller_v2.dart';

class LoggingTableRow extends StatefulWidget {
  const LoggingTableRow({
    super.key,
    required this.index,
    required this.data,
    required this.isSelected,
  });

  final int index;
  final LogDataV2 data;
  final bool isSelected;

  @override
  State<LoggingTableRow> createState() => _LoggingTableRowState();

  static TextSpan _detailsSpan(String text) {
    return TextSpan(
      text: text,
      style: _detailsStyle,
    );
  }

  static TextSpan _metadataSpan(String text) {
    return TextSpan(
      text: text,
      style: _metaDataStyle,
    );
  }

  static const _detailsStyle = TextStyle();

  static const _metaDataStyle = TextStyle();

  static const double _dividerHeight = 10.0;

  static double calculateRowHeight(LogDataV2 log, double width) {
    final text = log.asLogDetails();

    final row1 = _textSize(_detailsSpan(text), width: width);

    // TODO(danchevalier): Improve row2 height by manually flowing metadas into another row
    // if theyoverflow.
    final row2 = _textSize(
      _metadataSpan('always a single line of text'),
      width: width,
    );
    return row1.height + row2.height + _dividerHeight;
  }

  static Size _textSize(
    TextSpan textSpan, {
    double width = double.infinity,
  }) {
    final TextPainter textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width);
    final size = textPainter.size;
    textPainter.dispose();
    return size;
  }
}

class _LoggingTableRowState extends State<LoggingTableRow> {
  @override
  Widget build(BuildContext context) {
    Color? color = alternatingColorForIndex(
      widget.index,
      Theme.of(context).colorScheme,
    );

    if (widget.isSelected) {
      color = Colors.blueGrey;
    }

    return Container(
      decoration: BoxDecoration(color: color),
      child: ValueListenableBuilder(
        valueListenable: widget.data.needsComputing,
        builder: (context, _, __) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: LoggingTableRow._detailsSpan(widget.data.asLogDetails()),
              ),
              Row(
                children: [
                  RichText(
                    text: LoggingTableRow._metadataSpan('Some METADATA'),
                  ),
                  const SizedBox(width: 20.0),
                  RichText(
                    text: LoggingTableRow._metadataSpan('Goes Here'),
                  ),
                ],
              ),
              const Divider(
                height: LoggingTableRow._dividerHeight,
                color: Colors.black,
              ),
            ],
          );
        },
      ),
    );
  }
}
