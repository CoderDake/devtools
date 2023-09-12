// #!/bin/bash -e
// RUN_ID=$1
import 'dart:async';
import 'dart:io';
import '../utils.dart';

import 'package:args/command_runner.dart';
import 'package:io/io.dart';
import 'package:path/path.dart' as path;

class FixGoldensCommand extends Command {
  FixGoldensCommand() {
    argParser.addOption(
      'run-id',
      help: 'The ID of the workflow run where the goldens are failing. '
          'e.g.https://github.com/flutter/devtools/actions/runs/<run-id>/job/16691428186',
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
    // Change the CWD to the repo root
    Directory.current = pathFromRepoRoot("");

    final runId = argResults!['run-id']!;
// DOWNLOAD_DIR=$(mktemp -d)
    final tmpDownloadDir = Directory(
      path.join('.tmp${DateTime.now().millisecondsSinceEpoch}'),
    );
    tmpDownloadDir.createSync();
    try {
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
      final newGoldens = tmpDownloadDir
          .listSync(recursive: true)
          .where((e) => e.path.endsWith('testImage.png'));
      print(newGoldens);
// cd packages/devtools_app/test/
      final allDevtoolsPngFiles =
          Directory(pathFromRepoRoot("packages/devtools_app/test/"))
              .listSync(recursive: true)
            ..where((e) => e.path.endsWith('.png'));

      for (final file in newGoldens) {
// while IFS= read -r GOLDEN ; do
//   FILE_NAME=$(basename $GOLDEN | sed "s|_testImage.png$|.png|")
        final baseName = path.basename(file.path);
        final pngRoot =
            '${RegExp(r'(^.*)_testImage.png').firstMatch(baseName)?.group(1)}.png';

        final fileMatches = allDevtoolsPngFiles.where(
          (e) => e.path.endsWith(pngRoot),
        );
//   FOUND_FILES=$(find . -name "$FILE_NAME" )
//   FOUND_FILE_COUNT=$(echo -n "$FOUND_FILES" | grep -c '^')

//   if [[ $FOUND_FILE_COUNT -ne 1 ]] ; then
        final String destinationPath;
        if (fileMatches.isEmpty) {
          throw 'Could not find a golden Image for $baseName using $pngRoot as '
              'the item of the search.';
        } else if (fileMatches.length == 1) {
          destinationPath = fileMatches.first.path;
        } else {
          print("Multiple goldens found for ${file.path}");
          print("Select which golden should be overridden:");

          for (int i = 0; i < fileMatches.length; i++) {
            final fileMatch = fileMatches.elementAt(i);
            print('${i + 1}) ${fileMatch.path}');
          }

          final userSelection = int.parse(stdin.readLineSync()!);

          destinationPath = fileMatches.elementAt(userSelection - 1).path;
        }
        await file.rename(destinationPath);

        print("Fixed: $destinationPath");
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
      }

// echo "Done updating $(echo -n "$NEW_GOLDENS" | grep -c '^') goldens"
      print('Done updating ${newGoldens.length} goldens');
    } finally {
      tmpDownloadDir.deleteSync(recursive: true);
    }
  }
}
