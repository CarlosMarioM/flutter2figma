import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:flutter2figma/src/commands.dart';

Future<void> main(List<String> args) async {
  try {
    exitCode = await buildRunner().run(args) ?? 0;
  } on UsageException catch (e) {
    stderr.writeln(e);
    exitCode = 64;
  } on StateError catch (e) {
    stderr.writeln('error: ${e.message}');
    exitCode = 1;
  } on ArgumentError catch (e) {
    stderr.writeln('error: ${e.message}');
    exitCode = 1;
  }
}
