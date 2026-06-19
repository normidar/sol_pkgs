/// Parsed NatSpec documentation tags for a single declaration.
///
/// See https://docs.soliditylang.org/en/latest/natspec-format.html
class NatSpec {
  NatSpec({
    this.title,
    this.author,
    this.notice,
    this.dev,
    this.inheritdoc,
    Map<String, String>? params,
    List<String>? returns,
    Map<String, String>? custom,
  }) : params = params ?? {},
       returns = returns ?? [],
       custom = custom ?? {};

  /// `@title`
  final String? title;

  /// `@author`
  final String? author;

  /// `@notice` — end-user facing description.
  final String? notice;

  /// `@dev` — developer facing details.
  final String? dev;

  /// `@inheritdoc <Contract>`
  final String? inheritdoc;

  /// `@param name description`, keyed by parameter name.
  final Map<String, String> params;

  /// `@return [name] description`, in declaration order.
  final List<String> returns;

  /// `@custom:tag …`, keyed by the part after `custom:`.
  final Map<String, String> custom;

  bool get isEmpty =>
      title == null &&
      author == null &&
      notice == null &&
      dev == null &&
      inheritdoc == null &&
      params.isEmpty &&
      returns.isEmpty &&
      custom.isEmpty;

  /// Parses cleaned NatSpec text (markers already stripped) into tags.
  ///
  /// Untagged leading text is treated as an implicit `@notice`, matching solc.
  static NatSpec parse(String? doc) {
    if (doc == null || doc.trim().isEmpty) return NatSpec();

    String? title;
    String? author;
    String? notice;
    String? dev;
    String? inheritdoc;
    final params = <String, String>{};
    final returns = <String>[];
    final custom = <String, String>{};

    // Split the text into (tag, content) chunks. Text before the first tag is
    // an implicit @notice.
    final tagPattern = RegExp(r'@(\w+(?::\w+)?)');
    final matches = tagPattern.allMatches(doc).toList();

    if (matches.isEmpty) {
      return NatSpec(notice: _collapse(doc));
    }

    final leading = doc.substring(0, matches.first.start).trim();
    if (leading.isNotEmpty) notice = _collapse(leading);

    for (var i = 0; i < matches.length; i++) {
      final m = matches[i];
      final tag = m.group(1)!;
      final end = i + 1 < matches.length ? matches[i + 1].start : doc.length;
      final content = _collapse(doc.substring(m.end, end));

      if (tag.startsWith('custom:')) {
        custom[tag.substring('custom:'.length)] = content;
        continue;
      }
      switch (tag) {
        case 'title':
          title = content;
        case 'author':
          author = content;
        case 'notice':
          notice = notice == null ? content : '$notice $content';
        case 'dev':
          dev = dev == null ? content : '$dev $content';
        case 'inheritdoc':
          inheritdoc = content;
        case 'param':
          final sp = content.indexOf(RegExp(r'\s'));
          if (sp > 0) {
            params[content.substring(0, sp)] = content.substring(sp + 1).trim();
          } else if (content.isNotEmpty) {
            params[content] = '';
          }
        case 'return':
          returns.add(content);
        default:
          // Unknown tag: ignore (forward-compatible).
          break;
      }
    }

    return NatSpec(
      title: title,
      author: author,
      notice: notice,
      dev: dev,
      inheritdoc: inheritdoc,
      params: params,
      returns: returns,
      custom: custom,
    );
  }

  /// Collapses internal runs of whitespace/newlines into single spaces.
  static String _collapse(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
}
