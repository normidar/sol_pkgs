import 'source_location.dart';

enum Severity { info, warning, error, fatalError }

class Diagnostic {
  const Diagnostic({
    required this.severity,
    required this.message,
    this.location = SourceLocation.invalid,
    this.errorCode,
    this.hint,
  });

  final Severity severity;
  final String message;
  final SourceLocation location;
  final int? errorCode;
  final String? hint;

  bool get isError =>
      severity == Severity.error || severity == Severity.fatalError;

  @override
  String toString() {
    final code = errorCode != null ? ' [$errorCode]' : '';
    final loc = location.isValid ? ' at $location' : '';
    return '${severity.name.toUpperCase()}$code$loc: $message';
  }
}

/// Collects diagnostics and controls early-exit behaviour.
class DiagnosticCollector {
  final List<Diagnostic> _diagnostics = [];

  List<Diagnostic> get diagnostics => List.unmodifiable(_diagnostics);

  bool get hasErrors => _diagnostics.any((d) => d.isError);

  void add(Diagnostic diagnostic) {
    _diagnostics.add(diagnostic);
    if (diagnostic.severity == Severity.fatalError) {
      throw FatalErrorException(diagnostic);
    }
  }

  void info(String msg, {SourceLocation location = SourceLocation.invalid}) =>
      add(
        Diagnostic(severity: Severity.info, message: msg, location: location),
      );

  void warning(
    String msg, {
    SourceLocation location = SourceLocation.invalid,
    int? errorCode,
  }) => add(
    Diagnostic(
      severity: Severity.warning,
      message: msg,
      location: location,
      errorCode: errorCode,
    ),
  );

  void error(
    String msg, {
    SourceLocation location = SourceLocation.invalid,
    int? errorCode,
  }) => add(
    Diagnostic(
      severity: Severity.error,
      message: msg,
      location: location,
      errorCode: errorCode,
    ),
  );

  void fatalError(
    String msg, {
    SourceLocation location = SourceLocation.invalid,
    int? errorCode,
  }) => add(
    Diagnostic(
      severity: Severity.fatalError,
      message: msg,
      location: location,
      errorCode: errorCode,
    ),
  );
}

class FatalErrorException implements Exception {
  const FatalErrorException(this.diagnostic);
  final Diagnostic diagnostic;

  @override
  String toString() => 'FatalError: ${diagnostic.message}';
}
