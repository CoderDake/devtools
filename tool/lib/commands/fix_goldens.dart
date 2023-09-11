// #!/bin/bash -e
// RUN_ID=$1
import 'dart:async';
import 'dart:io';
import '../utils.dart';

import 'package:args/command_runner.dart';
import 'package:io/io.dart';

class FixGoldensCommand extends Command {
  FixGoldensCommand() {
    argParser.addOption(
      'run-id',
      help: 'The ID of the workflow run where the goldens are failing.',
      valueHelp: '12345',
      mandatory: true,
    );
  }
  @override
  String get description =>
      'A helper script for downloading and applying golden fixes, when they are broken.';

  @override
  String get name => 'fix-goldens';

  final processManager = ProcessManager();

  @override
  FutureOr? run() async {
    final runId = argResults!['run-id']!;
// DOWNLOAD_DIR=$(mktemp -d)
    final tmpDownloadDir = Directory('.tmp/');
    tmpDownloadDir.createSync();

// echo "Downloading the artifacts to $DOWNLOAD_DIR"
// gh run download $RUN_ID -p "*golden_image_failures*" -D "$DOWNLOAD_DIR"
    await processManager.runProcess(
      CliCommand.from('gh', [
        'run',
        'download',
        runId,
        '-p',
        '*golden_image_failures*',
        '-D',
        tmpDownloadDir.path,
      ]),
    );

// NEW_GOLDENS=$(find $DOWNLOAD_DIR -type f | grep "testImage.png" )
    for (final file in tmpDownloadDir.listSync(recursive: true)) {
      print(file.path);
    }
// cd packages/devtools_app/test/

// while IFS= read -r GOLDEN ; do
//   FILE_NAME=$(basename $GOLDEN | sed "s|_testImage.png$|.png|")
//   FOUND_FILES=$(find . -name "$FILE_NAME" )
//   FOUND_FILE_COUNT=$(echo -n "$FOUND_FILES" | grep -c '^')

//   if [[ $FOUND_FILE_COUNT -ne 1 ]] ; then
//     # If there are goldens with conflicting names, we need to pick which one
//     # maps to the artifact.
//     echo "Multiple goldens found for $(echo $GOLDEN| sed 's|^.*golden_image_failures[^/]*/||')"
//     echo "Select which golden should be overridden:"

//     select SELECTED_FILE in $FOUND_FILES
//     do
//       DEST_PATH="$SELECTED_FILE"
//       break;
//     done </dev/tty
//   else
//     DEST_PATH=$FOUND_FILES
//   fi

//   echo "FIXED: $DEST_PATH"
//   mv "$GOLDEN" "$DEST_PATH"
// done <<< "$NEW_GOLDENS"

// echo "Done updating $(echo -n "$NEW_GOLDENS" | grep -c '^') goldens"
  }
}
