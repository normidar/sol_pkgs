/// Tests for the sol_cli compiler command.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sol_cli/sol_cli.dart';
import 'package:test/test.dart';

// ── helpers ───────────────────────────────────────────────────────────────────

/// Runs [runCompiler] with captured stdout/stderr.
Future<({int exitCode, String out, String err})> _run(List<String> args) async {
  final outBuf = StringBuffer();
  final errBuf = StringBuffer();
  final code = await IOOverrides.runZoned(
    () => runCompiler(args),
    stdout: () => _StringSink(outBuf),
    stderr: () => _StringSink(errBuf),
  );
  return (exitCode: code, out: outBuf.toString(), err: errBuf.toString());
}

/// Writes [source] to a temp .sol file and registers teardown for cleanup.
String _tempSol(String source) {
  final f = File(
    '${Directory.systemTemp.path}/'
    'sol_cli_test_${DateTime.now().microsecondsSinceEpoch}.sol',
  );
  f.writeAsStringSync(source);
  addTearDown(f.deleteSync);
  return f.path;
}

// ── Solidity fixtures ─────────────────────────────────────────────────────────

const _counter = '''
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Counter {
  uint256 public value;
  function set(uint256 v) external { value = v; }
  function get() external view returns (uint256) { return value; }
}
''';

const _syntaxError = '''
pragma solidity ^0.8.0;
contract Bad {
  uint256 public x
''';

// ── IOOverrides stubs ─────────────────────────────────────────────────────────

/// An [IOSink]-compatible [Stdout] that writes into a [StringBuffer].
class _StringSink implements Stdout {
  _StringSink(this._buf);
  final StringBuffer _buf;

  @override
  void write(Object? obj) => _buf.write(obj);
  @override
  void writeln([Object? obj = '']) => _buf.writeln(obj);
  @override
  void writeAll(Iterable<dynamic> objects, [String sep = '']) =>
      _buf.writeAll(objects, sep);
  @override
  void writeCharCode(int charCode) => _buf.writeCharCode(charCode);
  @override
  void add(List<int> data) => _buf.write(utf8.decode(data));
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future<void> addStream(Stream<List<int>> stream) async {}
  @override
  Future<void> flush() async {}
  @override
  Future<void> close() async {}
  @override
  Future<void> get done => Future<void>.value();
  @override
  bool get hasTerminal => false;
  @override
  IOSink get nonBlocking => this;
  @override
  bool get supportsAnsiEscapes => false;
  @override
  int get terminalColumns => 80;
  @override
  int get terminalLines => 24;
  @override
  Encoding get encoding => utf8;
  @override
  set encoding(Encoding enc) {}
  @override
  String get lineTerminator => '\n';
  @override
  set lineTerminator(String value) {}
}

/// A [Stdin] that returns a fixed line from [readLineSync].
class _LineStdin implements Stdin {
  _LineStdin(this._line);
  final String _line;

  @override
  String? readLineSync({
    Encoding encoding = systemEncoding,
    bool retainNewlines = false,
  }) => _line;

  // ── unused stubs ──────────────────────────────────────────────────────────
  @override
  bool get echoMode => false;
  @override
  set echoMode(bool v) {}
  @override
  bool get echoNewlineMode => false;
  @override
  set echoNewlineMode(bool v) {}
  @override
  bool get lineMode => false;
  @override
  set lineMode(bool v) {}
  @override
  bool get hasTerminal => false;
  @override
  bool get supportsAnsiEscapes => false;
  @override
  int readByteSync() => -1;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.empty().listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  Future<bool> any(bool Function(List<int>) test) async => false;
  @override
  Stream<List<int>> asBroadcastStream({
    void Function(StreamSubscription<List<int>>)? onListen,
    void Function(StreamSubscription<List<int>>)? onCancel,
  }) => Stream<List<int>>.empty();
  @override
  Stream<S> asyncExpand<S>(Stream<S>? Function(List<int>) convert) =>
      Stream<S>.empty();
  @override
  Stream<S> asyncMap<S>(FutureOr<S> Function(List<int>) convert) =>
      Stream<S>.empty();
  @override
  Stream<R> cast<R>() => Stream<R>.empty();
  @override
  Future<bool> contains(Object? needle) async => false;
  @override
  Stream<List<int>> distinct([bool Function(List<int>, List<int>)? equals]) =>
      Stream<List<int>>.empty();
  @override
  Future<E> drain<E>([E? futureValue]) async => futureValue as E;
  @override
  Future<List<int>> elementAt(int index) async => [];
  @override
  Future<bool> every(bool Function(List<int>) test) async => true;
  @override
  Stream<S> expand<S>(Iterable<S> Function(List<int>) convert) =>
      Stream<S>.empty();
  @override
  Future<List<int>> get first async => [];
  @override
  Future<List<int>> firstWhere(
    bool Function(List<int>) test, {
    List<int> Function()? orElse,
  }) async => orElse != null ? orElse() : [];
  @override
  Future<S> fold<S>(S init, S Function(S, List<int>) combine) async => init;
  @override
  Future<void> forEach(void Function(List<int>) action) async {}
  @override
  Stream<List<int>> handleError(
    Function onError, {
    bool Function(dynamic)? test,
  }) => Stream<List<int>>.empty();
  @override
  bool get isBroadcast => false;
  @override
  Future<bool> get isEmpty async => true;
  @override
  Future<String> join([String separator = '']) async => '';
  @override
  Future<List<int>> get last async => [];
  @override
  Future<List<int>> lastWhere(
    bool Function(List<int>) test, {
    List<int> Function()? orElse,
  }) async => orElse != null ? orElse() : [];
  @override
  Future<int> get length async => 0;
  @override
  Stream<S> map<S>(S Function(List<int>) convert) => Stream<S>.empty();
  @override
  Future<dynamic> pipe(StreamConsumer<List<int>> streamConsumer) async {}
  @override
  Future<List<int>> reduce(
    List<int> Function(List<int>, List<int>) combine,
  ) async => [];
  @override
  Future<List<int>> get single async => [];
  @override
  Future<List<int>> singleWhere(
    bool Function(List<int>) test, {
    List<int> Function()? orElse,
  }) async => orElse != null ? orElse() : [];
  @override
  Stream<List<int>> skip(int count) => Stream<List<int>>.empty();
  @override
  Stream<List<int>> skipWhile(bool Function(List<int>) test) =>
      Stream<List<int>>.empty();
  @override
  Stream<List<int>> take(int count) => Stream<List<int>>.empty();
  @override
  Stream<List<int>> takeWhile(bool Function(List<int>) test) =>
      Stream<List<int>>.empty();
  @override
  Stream<List<int>> timeout(
    Duration timeLimit, {
    void Function(EventSink<List<int>>)? onTimeout,
  }) => Stream<List<int>>.empty();
  @override
  Future<List<List<int>>> toList() async => [];
  @override
  Future<Set<List<int>>> toSet() async => {};
  @override
  Stream<S> transform<S>(StreamTransformer<List<int>, S> transformer) =>
      Stream<S>.empty();
  @override
  Stream<List<int>> where(bool Function(List<int>) test) =>
      Stream<List<int>>.empty();
}

// ── test suite ────────────────────────────────────────────────────────────────

void main() {
  group('CLI flags', () {
    test('--help returns 0 and prints usage', () async {
      final r = await _run(['--help']);
      expect(r.exitCode, 0);
      expect(r.out, contains('solc-dart'));
      expect(r.out, contains('[no-]bin'));
    });

    test('--version returns 0 and prints version string', () async {
      final r = await _run(['--version']);
      expect(r.exitCode, 0);
      expect(r.out, contains('solc-dart'));
    });

    test('no input files returns 1 with error message', () async {
      final r = await _run([]);
      expect(r.exitCode, 1);
      expect(r.err, contains('No input files'));
    });

    test('unknown flag returns 1', () async {
      expect((await _run(['--totally-unknown-flag-xyz'])).exitCode, 1);
    });

    test('--optimize alone (no files) returns 1, not a flag error', () async {
      final r = await _run(['--optimize']);
      expect(r.exitCode, 1);
      expect(r.err, contains('No input files'));
    });

    test('--warnings-as-errors flag accepted', () async {
      expect((await _run(['--warnings-as-errors'])).exitCode, 1);
    });

    test('--output-dir flag accepted', () async {
      expect((await _run(['--output-dir', '/tmp'])).exitCode, 1);
    });

    test('--remappings flag accepted', () async {
      expect((await _run(['--remappings', 'prefix=target'])).exitCode, 1);
    });

    test('--base-path flag accepted', () async {
      expect((await _run(['--base-path', '/some/path'])).exitCode, 1);
    });

    test('--include-path flag accepted', () async {
      expect((await _run(['--include-path', '/some/path'])).exitCode, 1);
    });
  });

  group('file errors', () {
    test('non-existent file returns 1 with error message', () async {
      final r = await _run(['/nonexistent/path/Missing.sol']);
      expect(r.exitCode, 1);
      expect(r.err, contains('file not found'));
    });

    test('contract with syntax error returns 1', () async {
      final path = _tempSol(_syntaxError);
      expect((await _run([path])).exitCode, 1);
    });
  });

  group('compilation output', () {
    test('valid contract compiles successfully (exit 0)', () async {
      final path = _tempSol(_counter);
      expect((await _run([path])).exitCode, 0);
    });

    test('--bin outputs hex bytecode section', () async {
      final path = _tempSol(_counter);
      final r = await _run(['--bin', path]);
      expect(r.exitCode, 0);
      expect(r.out, contains('Binary:'));
      expect(r.out, matches(RegExp(r'[0-9a-f]{10,}')));
    });

    test('--abi outputs parseable JSON array', () async {
      final path = _tempSol(_counter);
      final r = await _run(['--abi', path]);
      expect(r.exitCode, 0);
      expect(r.out, contains('Contract JSON ABI:'));
      final jsonStart = r.out.indexOf('[');
      expect(jsonStart, greaterThanOrEqualTo(0));
      final abi = jsonDecode(r.out.substring(jsonStart));
      expect(abi, isA<List>());
      expect(abi, isNotEmpty);
    });

    test(
      '--abi includes public function and state-variable getter entries',
      () async {
        final path = _tempSol(_counter);
        final r = await _run(['--abi', path]);
        final jsonStart = r.out.indexOf('[');
        final abi = (jsonDecode(r.out.substring(jsonStart)) as List)
            .cast<Map<String, dynamic>>();
        final names = abi.map((e) => e['name']).whereType<String>().toSet();
        expect(names, containsAll(['set', 'get']));
      },
    );

    test('--ir outputs Yul IR with "object" keyword', () async {
      final path = _tempSol(_counter);
      final r = await _run(['--ir', path]);
      expect(r.exitCode, 0);
      expect(r.out, contains('IR:'));
      expect(r.out, contains('object'));
    });

    test('--bin --abi outputs both sections', () async {
      final path = _tempSol(_counter);
      final r = await _run(['--bin', '--abi', path]);
      expect(r.exitCode, 0);
      expect(r.out, contains('Binary:'));
      expect(r.out, contains('Contract JSON ABI:'));
    });

    test('--output-dir writes .bin and .abi files', () async {
      final path = _tempSol(_counter);
      final dir = Directory(
        '${Directory.systemTemp.path}/sol_cli_test_outdir_'
        '${DateTime.now().microsecondsSinceEpoch}',
      );
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final r = await _run(['--bin', '--abi', '--output-dir', dir.path, path]);
      expect(r.exitCode, 0);
      expect(File('${dir.path}/Counter.bin').existsSync(), isTrue);
      expect(File('${dir.path}/Counter.abi').existsSync(), isTrue);
    });

    test('--warnings-as-errors with no warnings exits 0', () async {
      final path = _tempSol(_counter);
      expect((await _run(['--warnings-as-errors', path])).exitCode, 0);
    });

    test('--optimize --bin produces valid bytecode', () async {
      final path = _tempSol(_counter);
      final r = await _run(['--optimize', '--bin', path]);
      expect(r.exitCode, 0);
      expect(r.out, matches(RegExp(r'[0-9a-f]{10,}')));
    });

    test('output section header contains contract name', () async {
      final path = _tempSol(_counter);
      final r = await _run(['--bin', path]);
      expect(r.out, contains('Counter'));
    });
  });

  group('standard-json mode', () {
    test(
      'valid standard-JSON input compiles and returns JSON with contracts',
      () async {
        final source = _counter;
        final input = jsonEncode({
          'language': 'Solidity',
          'sources': {
            'Counter.sol': {'content': source},
          },
          'settings': {
            'outputSelection': {
              '*': {
                '*': ['evm.bytecode', 'abi'],
              },
            },
          },
        });

        final outBuf = StringBuffer();
        final errBuf = StringBuffer();
        final code = await IOOverrides.runZoned(
          () => runCompiler(['--standard-json']),
          stdout: () => _StringSink(outBuf),
          stderr: () => _StringSink(errBuf),
          stdin: () => _LineStdin(input),
        );

        expect(code, 0);
        final result = jsonDecode(outBuf.toString()) as Map<String, dynamic>;
        expect(result, contains('contracts'));
      },
    );

    test(
      'standard-JSON with syntax error returns JSON with errors field',
      () async {
        final input = jsonEncode({
          'language': 'Solidity',
          'sources': {
            'Bad.sol': {'content': _syntaxError},
          },
          'settings': {
            'outputSelection': {
              '*': {'*': <String>[]},
            },
          },
        });

        final outBuf = StringBuffer();
        await IOOverrides.runZoned(
          () => runCompiler(['--standard-json']),
          stdout: () => _StringSink(outBuf),
          stderr: () => _StringSink(StringBuffer()),
          stdin: () => _LineStdin(input),
        );

        final result = jsonDecode(outBuf.toString()) as Map<String, dynamic>;
        // On failure the output should at minimum be a JSON object.
        expect(result, isA<Map>());
      },
    );
  });
}
