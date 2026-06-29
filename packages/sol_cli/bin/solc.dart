import 'dart:io';
import 'package:sol_cli/sol_cli.dart';

Future<void> main(List<String> args) async {
  exit(await runCompiler(args));
}
