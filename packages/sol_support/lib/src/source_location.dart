/// Byte-offset based position in a Solidity source file.
class SourceLocation {
  const SourceLocation({
    required this.sourceIndex,
    required this.offset,
    required this.length,
  });

  static const SourceLocation invalid = SourceLocation(
    sourceIndex: -1,
    offset: -1,
    length: 0,
  );

  /// Index into the compiler's source list (matches SourceUnit.index).
  final int sourceIndex;

  /// Byte offset from the start of the source file.
  final int offset;

  /// Length of the source span in bytes.
  final int length;

  bool get isValid => sourceIndex >= 0 && offset >= 0;

  SourceLocation combine(SourceLocation other) {
    if (!isValid) return other;
    if (!other.isValid) return this;
    final start = offset < other.offset ? offset : other.offset;
    final end1 = offset + length;
    final end2 = other.offset + other.length;
    final end = end1 > end2 ? end1 : end2;
    return SourceLocation(
      sourceIndex: sourceIndex,
      offset: start,
      length: end - start,
    );
  }

  @override
  String toString() => '$sourceIndex:$offset:$length';
}

/// Line/column breakdown computed lazily from raw source text.
class LineColumn {
  const LineColumn(this.line, this.column);

  final int line;
  final int column;

  @override
  bool operator ==(Object other) =>
      other is LineColumn && other.line == line && other.column == column;

  @override
  int get hashCode => Object.hash(line, column);

  @override
  String toString() => '$line:$column';
}

/// Converts byte offsets to (line, column) pairs for a single source file.
class SourceMap {
  SourceMap(this.source) : _lineOffsets = _buildLineOffsets(source);

  final String source;
  final List<int> _lineOffsets;

  static List<int> _buildLineOffsets(String source) {
    final offsets = [0];
    for (var i = 0; i < source.length; i++) {
      if (source.codeUnitAt(i) == 0x0A /* \n */ ) {
        offsets.add(i + 1);
      }
    }
    return offsets;
  }

  LineColumn locationOf(int offset) {
    var lo = 0;
    var hi = _lineOffsets.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_lineOffsets[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return LineColumn(lo + 1, offset - _lineOffsets[lo] + 1);
  }
}
