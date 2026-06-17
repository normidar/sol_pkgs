import 'source_location.dart';

/// Represents a single Solidity source file tracked by the compiler.
class SourceUnit {
  SourceUnit({
    required this.index,
    required this.path,
    required this.source,
  }) : sourceMap = SourceMap(source);

  final int index;
  final String path;
  final String source;
  final SourceMap sourceMap;

  LineColumn locationOf(int offset) => sourceMap.locationOf(offset);
}

/// Registry of all source files for one compilation.
class SourceUnitRegistry {
  final List<SourceUnit> _units = [];
  final Map<String, SourceUnit> _byPath = {};

  List<SourceUnit> get units => List.unmodifiable(_units);

  SourceUnit add(String path, String source) {
    if (_byPath.containsKey(path)) return _byPath[path]!;
    final unit = SourceUnit(index: _units.length, path: path, source: source);
    _units.add(unit);
    _byPath[path] = unit;
    return unit;
  }

  SourceUnit? byPath(String path) => _byPath[path];
  SourceUnit? byIndex(int index) =>
      index >= 0 && index < _units.length ? _units[index] : null;
}
