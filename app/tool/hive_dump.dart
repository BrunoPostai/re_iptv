// Reads a Hive box produced by the player and prints it as JSON.
//
// Useful for two things:
//   1. inspecting what a local database contains;
//   2. confirming that this project's own `AppStorage` reads the same schema.
//
// The box is opened read-only: the command refuses to run if the box file does
// not already exist, so it can never create or modify an application database.
//
// Usage (from the `app` directory):
//   dart run tool/hive_dump.dart <box-directory> <box-name> [--keys] [--out file.json]
//
// Example (this app's own data folder):
//   dart run tool/hive_dump.dart "%APPDATA%\com.reiptv\re_iptv\localData" hive-re-iptv-box --keys
//
// WARNING: a real settings box contains plaintext playlist credentials. Treat any
// output as sensitive and never commit it.

import 'dart:convert';
import 'dart:io';

import 'package:hive/hive.dart';

const _usage = '''
Usage: dart run tool/hive_dump.dart <box-directory> <box-name> [options]

Options:
  --keys        list the keys only
  --out <file>  also write the JSON to <file>
  --help        show this message
''';

Future<int> run(List<String> args) async {
  if (args.isEmpty || args.contains('--help') || args.contains('-h')) {
    stdout.writeln(_usage);
    return args.isEmpty ? 2 : 0;
  }

  final positional = args.where((a) => !a.startsWith('--')).toList();
  final keysOnly = args.contains('--keys');
  final outIndex = args.indexOf('--out');
  final outPath = outIndex >= 0 && outIndex + 1 < args.length ? args[outIndex + 1] : null;

  if (positional.length < 2) {
    stdout.writeln(_usage);
    return 2;
  }

  final directory = Directory(positional[0]);
  final name = positional[1];
  final boxFile = File('${directory.path}${Platform.pathSeparator}$name.hive');

  if (!boxFile.existsSync()) {
    stderr.writeln('No such box: ${boxFile.path}');
    stderr.writeln('Available:');
    if (directory.existsSync()) {
      for (final entry in directory.listSync()) {
        if (entry is File && entry.path.endsWith('.hive')) {
          stderr.writeln('  ${entry.uri.pathSegments.last.replaceAll('.hive', '')}');
        }
      }
    }
    return 1;
  }

  Hive.init(directory.path);
  final box = await Hive.openBox<dynamic>(name);

  try {
    final Object payload;
    if (keysOnly) {
      payload = box.keys.map((k) => k.toString()).toList();
    } else {
      payload = box.toMap().map((key, value) => MapEntry(key.toString(), value));
    }

    final text = const JsonEncoder.withIndent('  ').convert(payload);
    stdout.writeln(text);
    if (outPath != null) {
      File(outPath).writeAsStringSync(text);
      stderr.writeln('written: $outPath');
    }
  } finally {
    await box.close();
    await Hive.close();
  }
  return 0;
}

Future<void> main(List<String> args) async {
  exitCode = await run(args);
}
