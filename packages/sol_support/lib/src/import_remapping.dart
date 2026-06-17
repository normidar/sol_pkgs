/// Handles `--remappings` / `context:prefix=target` import path rewriting.
class ImportRemapping {
  ImportRemapping({
    required this.context,
    required this.prefix,
    required this.target,
  });

  /// Parse a single remapping string: `[context:]prefix=target`.
  factory ImportRemapping.parse(String raw) {
    final eq = raw.indexOf('=');
    if (eq < 0) throw ArgumentError('Invalid remapping (no =): $raw');
    final target = raw.substring(eq + 1);
    final lhs = raw.substring(0, eq);
    final colon = lhs.indexOf(':');
    if (colon < 0) {
      return ImportRemapping(context: '', prefix: lhs, target: target);
    }
    return ImportRemapping(
      context: lhs.substring(0, colon),
      prefix: lhs.substring(colon + 1),
      target: target,
    );
  }

  final String context;
  final String prefix;
  final String target;

  @override
  String toString() => '$context:$prefix=$target';
}

class ImportRemapper {
  ImportRemapper(this._remappings);

  final List<ImportRemapping> _remappings;

  /// Resolve [importPath] as seen from [fromPath], applying remappings.
  String resolve(String importPath, String fromPath) {
    ImportRemapping? best;
    for (final r in _remappings) {
      if (r.context.isNotEmpty && !fromPath.startsWith(r.context)) continue;
      if (!importPath.startsWith(r.prefix)) continue;
      if (best == null || r.prefix.length > best.prefix.length) best = r;
    }
    if (best == null) return importPath;
    return best.target + importPath.substring(best.prefix.length);
  }
}
