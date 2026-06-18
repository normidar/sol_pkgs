/// C3 linearisation for Solidity multiple inheritance.
///
/// Given a contract name and a function that returns its direct base list
/// (in source order, left-to-right), returns the MRO including the contract
/// itself.  Throws [C3LinearisationError] if linearisation fails (e.g. cycle).
List<String> c3Linearise(String name, List<String> Function(String) basesOf) {
  return _merge(name, basesOf, {});
}

List<String> _merge(
  String name,
  List<String> Function(String) basesOf,
  Set<String> visiting,
) {
  if (visiting.contains(name)) {
    throw C3LinearisationError(
      'Cycle detected in inheritance hierarchy at $name',
    );
  }
  visiting = {...visiting, name};

  final bases = basesOf(name);
  if (bases.isEmpty) return [name];

  // Build linearisations of each base + their lists.
  final lists = [
    for (final b in bases) _merge(b, basesOf, visiting),
    [...bases],
  ];

  final result = [name];
  while (true) {
    lists.removeWhere((l) => l.isEmpty);
    if (lists.isEmpty) return result;

    String? good;
    outer:
    for (final lst in lists) {
      final candidate = lst.first;
      // candidate must not appear in the tail of any list
      for (final lst2 in lists) {
        if (lst2.length > 1 && lst2.sublist(1).contains(candidate)) {
          continue outer;
        }
      }
      good = candidate;
      break;
    }

    if (good == null) {
      throw C3LinearisationError(
        'Cannot linearise inheritance hierarchy for $name',
      );
    }

    result.add(good);
    for (final lst in lists) {
      lst.remove(good);
    }
  }
}

class C3LinearisationError implements Exception {
  const C3LinearisationError(this.message);
  final String message;

  @override
  String toString() => 'C3LinearisationError: $message';
}
