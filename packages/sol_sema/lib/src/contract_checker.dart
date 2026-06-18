import 'package:sol_ast/sol_ast.dart';
import 'package:sol_support/sol_support.dart';

/// Static checks that go beyond name/type resolution:
///
///  * **State mutability** — a `view` function must not modify state and a
///    `pure` function must not read or modify state.
///  * **Function visibility** — every ordinary function must declare a
///    visibility (Solidity ≥0.5 requires it).
///  * **`override` consistency** — `override` must override a base member, and
///    a function overriding a `virtual` base member must say `override`.
///  * **Unused local variables** — warns about locals that are never
///    referenced.
///
/// Operates on a single [SourceFile]; base contracts are resolved among the
/// declarations in that file (cross-file bases are skipped to avoid false
/// positives).
class ContractChecker {
  ContractChecker(this._diagnostics);

  final DiagnosticCollector _diagnostics;

  void check(SourceFile file) {
    final contracts = {for (final c in file.declarations) c.name: c};
    for (final contract in file.declarations) {
      _checkContract(contract, contracts);
    }
  }

  void _checkContract(
    ContractDefinition contract,
    Map<String, ContractDefinition> contracts,
  ) {
    final mutableState = _mutableStateVars(contract, contracts);
    final baseFns = _baseFunctions(contract, contracts);
    final basesResolvable = contract.baseContracts.every(
      (b) => contracts.containsKey(b.name),
    );

    for (final member in contract.members) {
      if (member is! FunctionDefinition) continue;
      _checkVisibility(member, contract);
      _checkOverride(member, baseFns, basesResolvable);
      if (member.body != null) {
        _checkMutability(member, mutableState);
        _checkUnusedLocals(member);
      }
    }
  }

  // ── Visibility ────────────────────────────────────────────────────────────

  void _checkVisibility(FunctionDefinition fn, ContractDefinition contract) {
    // Only ordinary functions need an explicit visibility. Constructors,
    // fallback/receive and interface members are exempt.
    if (fn.kind != FunctionKind.function) return;
    if (contract.kind == ContractKind.interface) return;
    if (fn.visibility == Visibility.defaultVisibility) {
      _diagnostics.error(
        'Function "${fn.name}" is missing a visibility specifier '
        '(public/external/internal/private).',
        location: fn.location,
      );
    }
  }

  // ── Override consistency ────────────────────────────────────────────────────

  void _checkOverride(
    FunctionDefinition fn,
    Map<String, bool> baseFns, // name → declared virtual in some base
    bool basesResolvable,
  ) {
    if (fn.name == null) return;
    final inBase = baseFns.containsKey(fn.name);
    if (fn.isOverride) {
      if (basesResolvable && !inBase) {
        _diagnostics.error(
          'Function "${fn.name}" is marked override but does not override '
          'anything.',
          location: fn.location,
        );
      }
    } else if (inBase && baseFns[fn.name] == true) {
      _diagnostics.error(
        'Overriding function "${fn.name}" must specify "override".',
        location: fn.location,
      );
    }
  }

  /// Function name → whether some base declares it `virtual`.
  Map<String, bool> _baseFunctions(
    ContractDefinition contract,
    Map<String, ContractDefinition> contracts,
  ) {
    final out = <String, bool>{};
    final seen = <String>{};
    void visit(String name) {
      if (!seen.add(name)) return;
      final c = contracts[name];
      if (c == null) return;
      for (final m in c.members) {
        if (m is FunctionDefinition && m.name != null) {
          out[m.name!] = (out[m.name!] ?? false) || m.isVirtual;
        }
      }
      for (final b in c.baseContracts) {
        visit(b.name);
      }
    }

    for (final b in contract.baseContracts) {
      visit(b.name);
    }
    return out;
  }

  // ── State mutability ────────────────────────────────────────────────────────

  void _checkMutability(FunctionDefinition fn, Set<String> mutableState) {
    final mut = fn.stateMutability;
    if (mut != StateMutability.view && mut != StateMutability.pure) return;

    final locals = <String>{
      for (final p in fn.parameters)
        if (p.name != null) p.name!,
      for (final p in fn.returnParameters)
        if (p.name != null) p.name!,
    };
    final declared = <String, SourceLocation>{};
    fn.body!.accept(_LocalDeclCollector(declared));
    locals.addAll(declared.keys);

    final scan = _MutabilityScan(mutableState, locals);
    fn.body!.accept(scan);

    final write = scan.writeLocation;
    if (write != null && mut == StateMutability.view) {
      _diagnostics.error(
        'Function "${fn.name}" is declared view but modifies state.',
        location: write,
      );
    }
    if (mut == StateMutability.pure) {
      final loc = scan.writeLocation ?? scan.readLocation;
      if (loc != null) {
        _diagnostics.error(
          'Function "${fn.name}" is declared pure but reads or modifies '
          'state.',
          location: loc,
        );
      }
    }
  }

  /// Mutable (non-constant, non-immutable) state variable names of [contract]
  /// and its in-file bases.
  Set<String> _mutableStateVars(
    ContractDefinition contract,
    Map<String, ContractDefinition> contracts,
  ) {
    final out = <String>{};
    final seen = <String>{};
    void visit(ContractDefinition? c) {
      if (c == null || !seen.add(c.name)) return;
      for (final m in c.members) {
        if (m is StateVariableDeclaration &&
            m.mutability == VariableMutability.mutable) {
          out.add(m.name);
        }
      }
      for (final b in c.baseContracts) {
        visit(contracts[b.name]);
      }
    }

    visit(contract);
    return out;
  }

  // ── Unused locals ───────────────────────────────────────────────────────────

  void _checkUnusedLocals(FunctionDefinition fn) {
    final declared = <String, SourceLocation>{};
    fn.body!.accept(_LocalDeclCollector(declared));
    if (declared.isEmpty) return;

    final referenced = <String>{};
    fn.body!.accept(_IdentifierCollector(referenced));

    declared.forEach((name, loc) {
      if (!referenced.contains(name)) {
        _diagnostics.warning('Unused local variable "$name".', location: loc);
      }
    });
  }
}

// ── Visitor helpers ─────────────────────────────────────────────────────────

/// Records the name+location of every locally declared variable.
class _LocalDeclCollector extends AstVisitor {
  _LocalDeclCollector(this._out);
  final Map<String, SourceLocation> _out;

  @override
  void visitVariableDeclarationStatement(VariableDeclarationStatement node) {
    for (final d in node.declarations) {
      if (d != null) _out[d.name] = d.location;
    }
    super.visitVariableDeclarationStatement(node);
  }
}

/// Records the name of every referenced [Identifier].
class _IdentifierCollector extends AstVisitor {
  _IdentifierCollector(this._out);
  final Set<String> _out;

  @override
  void visitIdentifier(Identifier node) => _out.add(node.name);
}

/// Detects state reads/writes (and environment reads) within a function body.
class _MutabilityScan extends AstVisitor {
  _MutabilityScan(this.mutableState, this.locals);

  final Set<String> mutableState;
  final Set<String> locals;

  SourceLocation? writeLocation;
  SourceLocation? readLocation;

  static const _envObjects = {'block', 'tx'};
  static const _allowedMsgMembers = {'data', 'sig'};

  @override
  void visitAssignment(Assignment node) {
    _markWriteIfState(node.leftHandSide);
    super.visitAssignment(node);
  }

  @override
  void visitUnaryOperation(UnaryOperation node) {
    if (node.operator$ == '++' || node.operator$ == '--') {
      _markWriteIfState(node.subExpression);
    }
    super.visitUnaryOperation(node);
  }

  @override
  void visitDeleteExpression(DeleteExpression node) {
    _markWriteIfState(node.expression);
    super.visitDeleteExpression(node);
  }

  @override
  void visitEmitStatement(EmitStatement node) {
    writeLocation ??= node.location;
    super.visitEmitStatement(node);
  }

  @override
  void visitIdentifier(Identifier node) {
    if (mutableState.contains(node.name) && !locals.contains(node.name)) {
      readLocation ??= node.location;
    }
  }

  @override
  void visitMemberAccess(MemberAccess node) {
    final base = node.expression;
    if (base is Identifier) {
      if (_envObjects.contains(base.name)) {
        readLocation ??= node.location;
      } else if (base.name == 'msg' &&
          !_allowedMsgMembers.contains(node.memberName)) {
        readLocation ??= node.location;
      }
    }
    super.visitMemberAccess(node);
  }

  void _markWriteIfState(Expression target) {
    final root = _rootName(target);
    if (root != null && mutableState.contains(root) && !locals.contains(root)) {
      writeLocation ??= target.location;
    }
  }

  static String? _rootName(Expression e) => switch (e) {
    Identifier(:final name) => name,
    IndexAccess(:final base) => _rootName(base),
    MemberAccess(:final expression) => _rootName(expression),
    _ => null,
  };
}
