import 'package:sol_types/sol_types.dart';

/// A single symbol in a scope.
class Symbol {
  const Symbol({required this.name, required this.type, required this.kind});

  final String name;
  final SolType type;
  final SymbolKind kind;
}

enum SymbolKind {
  stateVariable,
  localVariable,
  parameter,
  function,
  modifier,
  event,
  error,
  struct,
  enum$,
  contract,
  userDefinedValueType,
}

/// Lexical scope chain.
class Scope {
  Scope({this.parent});

  final Scope? parent;
  final Map<String, Symbol> _symbols = {};

  void declare(Symbol symbol) {
    _symbols[symbol.name] = symbol;
  }

  Symbol? lookup(String name) => _symbols[name] ?? parent?.lookup(name);

  bool isDeclaredLocally(String name) => _symbols.containsKey(name);
}
