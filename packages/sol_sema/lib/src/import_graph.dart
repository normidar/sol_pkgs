/// A directed graph of `import` dependencies between source units, with cycle
/// detection.
///
/// Solidity permits circular imports, so a detected cycle is informational
/// rather than fatal — but surfacing it is useful for tooling and for guarding
/// naive resolvers against infinite recursion.
class ImportGraph {
  final Map<String, List<String>> _edges = {};

  /// Records that [from] imports each path in [to].
  void addImports(String from, Iterable<String> to) {
    (_edges[from] ??= []).addAll(to);
    for (final t in to) {
      _edges.putIfAbsent(t, () => []);
    }
  }

  /// All source units known to the graph.
  Iterable<String> get nodes => _edges.keys;

  /// Returns true if any import cycle exists.
  bool get hasCycle => findCycles().isNotEmpty;

  /// Returns the distinct cycles in the graph. Each cycle is a list of node
  /// names in dependency order, with the first node repeated implicitly
  /// (i.e. `[a, b, c]` means `a → b → c → a`).
  List<List<String>> findCycles() {
    final cycles = <List<String>>[];
    final seenSignatures = <String>{};
    final color = <String, int>{}; // 0=white, 1=gray, 2=black
    final stack = <String>[];

    void dfs(String node) {
      color[node] = 1;
      stack.add(node);
      for (final next in _edges[node] ?? const <String>[]) {
        final c = color[next] ?? 0;
        if (c == 0) {
          dfs(next);
        } else if (c == 1) {
          // Back-edge to a gray node ⇒ cycle from `next` down to `node`.
          final start = stack.indexOf(next);
          if (start >= 0) {
            final cycle = stack.sublist(start);
            final signature = (List<String>.from(cycle)..sort()).join('|');
            if (seenSignatures.add(signature)) cycles.add(cycle);
          }
        }
      }
      stack.removeLast();
      color[node] = 2;
    }

    for (final node in _edges.keys) {
      if ((color[node] ?? 0) == 0) dfs(node);
    }
    return cycles;
  }
}
