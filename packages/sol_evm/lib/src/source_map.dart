/// Solidity-compatible source map compression.
///
/// solc emits one `s:l:f:j:m` entry per instruction, separated by `;`. Adjacent
/// entries omit unchanged fields (an empty `;` repeats the previous entry).
/// See https://docs.soliditylang.org/en/latest/internals/source_mappings.html
library;

import 'assembler.dart';

/// Builds the compact source-map string from a per-instruction list.
///
/// solc's compression rules:
/// - Trailing fields with the same value as the previous entry are omitted.
/// - An entirely-empty entry means "everything same as the previous one".
String compressSourceMap(
  List<SourceMapEntry> entries, {
  String jumpKind = '-',
}) {
  if (entries.isEmpty) return '';
  final sb = StringBuffer();

  // Sentinels that force the first entry to emit all four fields.
  var prevS = -2;
  var prevL = -2;
  var prevF = -2;
  var prevJ = '_';

  for (var i = 0; i < entries.length; i++) {
    if (i > 0) sb.write(';');
    final e = entries[i];
    final s = e.start;
    final l = e.length;
    final f = e.fileIndex;
    final j = jumpKind;

    // Build fields in s:l:f:j order, dropping equal-to-previous trailing ones.
    final fields = <String>[
      s == prevS ? '' : '$s',
      l == prevL ? '' : '$l',
      f == prevF ? '' : '$f',
      j == prevJ ? '' : j,
    ];
    while (fields.isNotEmpty && fields.last.isEmpty) {
      fields.removeLast();
    }
    sb.write(fields.join(':'));

    prevS = s;
    prevL = l;
    prevF = f;
    prevJ = j;
  }
  return sb.toString();
}
