import 'package:sol_abi/sol_abi.dart';
import 'package:sol_ast/sol_ast.dart';
import 'package:sol_support/sol_support.dart';
import 'package:sol_types/sol_types.dart';
import 'package:sol_yul/sol_yul.dart';

/// Lowers a single [ContractDefinition] (post-sema) to a [YulObject].
///
/// The generated structure mirrors solc's IRGenerator output:
///   object "ContractName" {
///     code { … deployment code … }
///     object "ContractName_deployed" {
///       code { … runtime code … }
///     }
///   }
class IRGenerator {
  IRGenerator(this._diagnostics);

  final DiagnosticCollector _diagnostics;
  int _tmpCounter = 0;

  /// Yul slot names of the return variables of the function being lowered.
  final List<String> _returnSlots = [];

  /// Storage slot assigned to each mutable state variable.
  final Map<String, int> _stateVarSlots = {};

  /// TypeName AST node for each mutable state variable (for struct layout).
  final Map<String, TypeName> _stateVarTypeNames = {};

  /// Names of locals/parameters in scope (so they shadow state variables).
  final Set<String> _localNames = {};

  /// Whether arithmetic is currently overflow-checked (Solidity ≥0.8 default).
  /// Set to `false` inside `unchecked { … }` blocks.
  bool _checked = true;

  /// Statements that must be emitted *before* the current expression's use site
  /// (used to implement short-circuit `&&` / `||`).
  final List<YulStatement> _preStmts = [];

  /// Runtime helper functions (panics, checked arithmetic) discovered while
  /// lowering, keyed by name and emitted once into the runtime object.
  final Map<String, YulFunctionDefinition> _helpers = {};

  /// Events and custom errors declared in the contract being lowered, by name.
  final Map<String, EventDefinition> _events = {};
  final Map<String, CustomErrorDefinition> _errors = {};

  /// Struct definitions in the contract being lowered, by name.
  final Map<String, StructDefinition> _structs = {};

  YulObject generateContract(ContractDefinition contract) {
    _events
      ..clear()
      ..addEntries(
        contract.members.whereType<EventDefinition>().map(
          (e) => MapEntry(e.name, e),
        ),
      );
    _errors
      ..clear()
      ..addEntries(
        contract.members.whereType<CustomErrorDefinition>().map(
          (e) => MapEntry(e.name, e),
        ),
      );
    _structs
      ..clear()
      ..addEntries(
        contract.members.whereType<StructDefinition>().map(
          (s) => MapEntry(s.name, s),
        ),
      );
    _allocateStateVariables(contract);

    final runtimeBlock = _generateRuntimeCode(contract);
    final deployBlock = _generateDeploymentCode(contract);

    final runtimeObj = YulObject(
      '${contract.name}_deployed',
      runtimeBlock,
      [],
      {},
    );

    return YulObject(contract.name, deployBlock, [runtimeObj], {});
  }

  /// Assigns sequential storage slots to mutable state variables.
  ///
  /// Each type occupies as many storage slots as its layout requires:
  ///  * Value types, dynamic arrays, mappings: 1 slot.
  ///  * Fixed-length array `T[N]`: N × slotSizeOf(T) slots.
  ///  * Struct: sum of member slot sizes.
  ///
  /// `constant` variables are inlined and `immutable` ones live in code, so
  /// neither occupies a storage slot.
  void _allocateStateVariables(ContractDefinition contract) {
    _stateVarSlots.clear();
    _stateVarTypeNames.clear();
    var slot = 0;
    for (final member in contract.members) {
      if (member is StateVariableDeclaration &&
          member.mutability == VariableMutability.mutable) {
        _stateVarSlots[member.name] = slot;
        _stateVarTypeNames[member.name] = member.typeName;
        slot += _slotSizeOf(member.typeName);
      }
    }
  }

  /// Returns the number of storage slots occupied by [typeName].
  int _slotSizeOf(TypeName typeName) {
    if (typeName is ArrayTypeName && typeName.length != null) {
      final n = _evalIntLiteral(typeName.length!);
      if (n != null && n > 0) {
        return n * _slotSizeOf(typeName.baseType);
      }
    }
    if (typeName is UserDefinedTypeName) {
      final struct = _structs[typeName.name];
      if (struct != null) {
        return struct.members.fold(
          0,
          (sum, m) => sum + _slotSizeOf(m.typeName),
        );
      }
    }
    // Elementary types, dynamic arrays, mappings: each occupy 1 slot.
    return 1;
  }

  /// Returns the value of a constant integer literal expression, or null.
  static int? _evalIntLiteral(Expression expr) {
    if (expr is Literal && expr.kind == LiteralKind.number) {
      return int.tryParse(expr.value);
    }
    return null;
  }

  /// Returns the offset (in slots) of [memberName] inside [struct], or -1.
  int _structMemberOffset(StructDefinition struct, String memberName) {
    var offset = 0;
    for (final m in struct.members) {
      if (m.name == memberName) return offset;
      offset += _slotSizeOf(m.typeName);
    }
    return -1;
  }

  // ── Deployment code ───────────────────────────────────────────────────────

  YulBlock _generateDeploymentCode(ContractDefinition contract) {
    // Helpers discovered while lowering the constructor must live in *this*
    // (creation) object, separate from the runtime object's helpers.
    _helpers.clear();
    final contractName = contract.name;

    // Run the constructor body (if any) before returning the runtime code.
    final ctorStmts = <YulStatement>[];
    FunctionDefinition? ctor;
    for (final m in contract.members) {
      if (m is FunctionDefinition && m.kind == FunctionKind.constructor) {
        ctor = m;
        break;
      }
    }
    if (ctor != null && ctor.body != null) {
      final savedLocals = Set<String>.from(_localNames);
      final savedReturns = List<String>.from(_returnSlots);
      _localNames.clear();
      _returnSlots.clear();

      if (ctor.parameters.isNotEmpty) {
        // Constructor args are ABI-encoded and appended after the creation
        // bytecode; they start at offset codesize() in the calldata.
        final paramDecls = <YulStatement>[];
        for (var i = 0; i < ctor.parameters.length; i++) {
          final p = ctor.parameters[i];
          final pName = p.name;
          if (pName != null && pName.isNotEmpty) {
            _localNames.add(pName);
            paramDecls.add(
              YulVariableDeclaration(
                ['var_$pName'],
                YulFunctionCall('calldataload', [
                  YulFunctionCall('add', [
                    YulFunctionCall('codesize', const []),
                    YulLiteral('${i * 32}', YulLiteralKind.number),
                  ]),
                ]),
              ),
            );
          }
        }
        ctorStmts.addAll(paramDecls);
      }
      ctorStmts.add(_generateBlock(ctor.body!));

      _localNames
        ..clear()
        ..addAll(savedLocals);
      _returnSlots
        ..clear()
        ..addAll(savedReturns);
    }

    final deployed = '"${contractName}_deployed"';
    return YulBlock([
      ...ctorStmts,
      YulExpressionStatement(
        YulFunctionCall('codecopy', [
          YulLiteral('0', YulLiteralKind.number),
          YulFunctionCall('dataoffset', [
            YulLiteral(deployed, YulLiteralKind.string),
          ]),
          YulFunctionCall('datasize', [
            YulLiteral(deployed, YulLiteralKind.string),
          ]),
        ]),
      ),
      YulExpressionStatement(
        YulFunctionCall('return', [
          YulLiteral('0', YulLiteralKind.number),
          YulFunctionCall('datasize', [
            YulLiteral(deployed, YulLiteralKind.string),
          ]),
        ]),
      ),
      ..._helpers.values,
    ]);
  }

  // ── Runtime code ──────────────────────────────────────────────────────────

  YulBlock _generateRuntimeCode(ContractDefinition contract) {
    _helpers.clear();
    // Lower the function bodies first: this discovers which runtime helpers
    // (overflow panics, checked-arithmetic routines) are needed.
    final functions = <YulStatement>[
      for (final member in contract.members)
        if (member is FunctionDefinition &&
            member.body != null &&
            member.kind == FunctionKind.function &&
            member.name != null)
          _generateFunction(member),
    ];

    final stmts = <YulStatement>[];

    // Dispatcher: read selector and route to functions.
    stmts.add(_generateDispatcher(contract));

    stmts.addAll(functions);

    // Revert if no selector matched.
    stmts.add(
      YulExpressionStatement(
        YulFunctionCall('revert', [
          YulLiteral('0', YulLiteralKind.number),
          YulLiteral('0', YulLiteralKind.number),
        ]),
      ),
    );

    // Emit discovered helper functions (hoisted alongside the others).
    stmts.addAll(_helpers.values);

    return YulBlock(stmts);
  }

  YulStatement _generateDispatcher(ContractDefinition contract) {
    final publicFns = contract.members
        .whereType<FunctionDefinition>()
        .where(
          (fn) =>
              fn.visibility == Visibility.public ||
              fn.visibility == Visibility.external,
        )
        .where((fn) => fn.name != null)
        .toList();

    // switch shr(224, calldataload(0))  — the 4-byte function selector.
    final cases = publicFns.map((fn) {
      final selector = functionSelectorHex(fn);
      final args = [
        for (var i = 0; i < fn.parameters.length; i++)
          _decodeParam(fn.parameters[i], i),
      ];
      final call = YulFunctionCall('fun_${fn.name}', args);
      final returnCount = fn.returnParameters.length;

      final body = <YulStatement>[];
      if (returnCount == 0) {
        body.add(YulExpressionStatement(call));
        body.add(_abiReturn(0));
      } else if (returnCount == 1 &&
          _isDynStringTypeName(fn.returnParameters.first.typeName)) {
        // Single dynamic return (string/bytes): encode as offset+length+data.
        final ret = 'abi_ret_${fn.name}_0';
        body.add(YulVariableDeclaration([ret], call));
        body.addAll(_abiEncodeShortString(YulIdentifier(ret)));
      } else {
        // Capture the return value(s), ABI-encode them into memory at 0x00,
        // then RETURN the head region (one 32-byte word per static value).
        final captures = [
          for (var i = 0; i < returnCount; i++) 'abi_ret_${fn.name}_$i',
        ];
        body.add(YulVariableDeclaration(captures, call));
        for (var i = 0; i < returnCount; i++) {
          body.add(
            YulExpressionStatement(
              YulFunctionCall('mstore', [
                YulLiteral('${i * 32}', YulLiteralKind.number),
                YulIdentifier(captures[i]),
              ]),
            ),
          );
        }
        body.add(_abiReturn(returnCount * 32));
      }

      return YulCase(
        YulLiteral(selector, YulLiteralKind.number),
        YulBlock(body),
      );
    }).toList();

    // Auto-generated getters for `public` state variables.
    for (final member in contract.members) {
      if (member is StateVariableDeclaration &&
          member.visibility == Visibility.public &&
          member.mutability == VariableMutability.mutable) {
        final getter = _generateGetterCase(member);
        if (getter != null) cases.add(getter);
      }
    }

    return YulSwitch(
      YulFunctionCall('shr', [
        YulLiteral('224', YulLiteralKind.number),
        YulFunctionCall('calldataload', [
          YulLiteral('0', YulLiteralKind.number),
        ]),
      ]),
      cases,
      null,
    );
  }

  /// Builds the dispatcher case for the auto-generated getter of a `public`
  /// state variable: scalars become `name()`, mappings/arrays take their key/
  /// index arguments (e.g. `balances(address)`), returning the value slot.
  /// Returns null when the value type isn't a returnable value type.
  YulCase? _generateGetterCase(StateVariableDeclaration sv) {
    final baseSlot = _stateVarSlots[sv.name];
    if (baseSlot == null) return null;

    final keyTypes = <String>[];
    YulExpression slotExpr = YulLiteral('$baseSlot', YulLiteralKind.number);
    var typeName = sv.typeName;
    var argIndex = 0;
    while (true) {
      if (typeName is MappingTypeName) {
        keyTypes.add(abiCanonicalType(typeName.keyType));
        slotExpr = YulFunctionCall(_mappingSlotHelper(), [
          _calldataArg(argIndex++),
          slotExpr,
        ]);
        typeName = typeName.valueType;
      } else if (typeName is ArrayTypeName) {
        keyTypes.add('uint256');
        slotExpr = typeName.length == null
            ? YulFunctionCall(_dynArraySlotHelper(), [
                slotExpr,
                _calldataArg(argIndex++),
              ])
            : YulFunctionCall('add', [slotExpr, _calldataArg(argIndex++)]);
        typeName = typeName.baseType;
      } else {
        break;
      }
    }
    // string/bytes state variables: ABI-encode as dynamic type.
    if (typeName is ElementaryTypeName &&
        (typeName.name == 'string' || typeName.name == 'bytes')) {
      final signature = '${sv.name}(${keyTypes.join(',')})';
      final packedVar = '__getter_packed_${sv.name}';
      return YulCase(
        YulLiteral(selectorHex(signature), YulLiteralKind.number),
        YulBlock([
          YulVariableDeclaration([
            packedVar,
          ], YulFunctionCall('sload', [slotExpr])),
          ..._abiEncodeShortString(YulIdentifier(packedVar)),
        ]),
      );
    }

    // Only value types are returned in a single word; structs/tuples are not.
    if (typeName is! ElementaryTypeName) return null;

    final signature = '${sv.name}(${keyTypes.join(',')})';
    return YulCase(
      YulLiteral(selectorHex(signature), YulLiteralKind.number),
      YulBlock([
        _callStmt('mstore', [
          _n('0'),
          YulFunctionCall('sload', [slotExpr]),
        ]),
        _abiReturn(32),
      ]),
    );
  }

  YulExpression _calldataArg(int index) => YulFunctionCall('calldataload', [
    YulLiteral('${4 + index * 32}', YulLiteralKind.number),
  ]);

  /// True when [typeName] is `string` or `bytes` (a dynamic type).
  static bool _isDynStringTypeName(TypeName typeName) {
    if (typeName is! ElementaryTypeName) return false;
    return typeName.name == 'string' || typeName.name == 'bytes';
  }

  /// Packs a string literal (without surrounding quotes) into the Solidity
  /// short-string storage layout: data left-aligned in 31 bytes, length*2 in
  /// the bottom byte (even → short string marker).
  ///
  /// Returns the 32-byte value as a `0x…` hex literal, or null if [s] is
  /// longer than 31 bytes (would require long-string layout).
  static String? _packShortStringLiteral(String s) {
    final bytes = s.codeUnits;
    if (bytes.length > 31) return null;
    final len = bytes.length;
    // Build 32-byte word: data in bytes [0..len-1], zeros [len..30], len*2 in [31].
    final word = List<int>.filled(32, 0);
    for (var i = 0; i < len; i++) {
      word[i] = bytes[i] & 0xff;
    }
    word[31] = len * 2;
    final hex = word.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '0x$hex';
  }

  /// ABI-encodes a packed short-string word [packedWord] (as stored in
  /// Solidity's slot layout) into memory at offset 0 and emits
  /// `return(0, 96)`.
  ///
  /// Memory layout produced:
  ///   [0x00]: 32  (offset to string data within return payload)
  ///   [0x20]: len (string byte length)
  ///   [0x40]: data (string bytes, left-aligned, padded to 32 bytes)
  List<YulStatement> _abiEncodeShortString(YulExpression packedWord) {
    final tmp = _tmp();
    final lenTmp = _tmp();
    final dataTmp = _tmp();
    return [
      YulVariableDeclaration([tmp], packedWord),
      // length = (word & 0xff) >> 1  (bottom byte / 2 for short strings)
      YulVariableDeclaration(
        [lenTmp],
        _c('shr', [
          _n('1'),
          _c('and', [_id(tmp), _n('0xff')]),
        ]),
      ),
      // data = word with bottom byte cleared (left-aligned string bytes)
      YulVariableDeclaration(
        [dataTmp],
        _c('and', [
          _id(tmp),
          _n(
            '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00',
          ),
        ]),
      ),
      _callStmt('mstore', [_n('0'), _n('32')]),
      _callStmt('mstore', [_n('32'), _id(lenTmp)]),
      _callStmt('mstore', [_n('64'), _id(dataTmp)]),
      _abiReturn(96),
    ];
  }

  YulFunctionDefinition _generateFunction(FunctionDefinition fn) {
    // Parameters are referenced from the body as plain identifiers, so their
    // Yul slot names must match what [_generateExpression] produces for an
    // [Identifier] (`var_<name>`). Unnamed/return slots fall back to indices.
    final params = [
      for (var i = 0; i < fn.parameters.length; i++)
        _slotName(fn.parameters[i].name, 'param_$i'),
    ];
    final rets = [
      for (var i = 0; i < fn.returnParameters.length; i++)
        _slotName(fn.returnParameters[i].name, 'ret_$i'),
    ];

    final savedReturnSlots = List<String>.from(_returnSlots);
    final savedLocals = Set<String>.from(_localNames);
    _returnSlots
      ..clear()
      ..addAll(rets);
    _localNames
      ..clear()
      ..addAll(fn.parameters.map((p) => p.name).whereType<String>())
      ..addAll(fn.returnParameters.map((p) => p.name).whereType<String>());

    final body = fn.body != null ? _generateBlock(fn.body!) : YulBlock([]);

    _returnSlots
      ..clear()
      ..addAll(savedReturnSlots);
    _localNames
      ..clear()
      ..addAll(savedLocals);

    return YulFunctionDefinition('fun_${fn.name}', params, rets, body);
  }

  /// Slot name for a (possibly named) parameter/return variable.
  static String _slotName(String? name, String fallback) =>
      name != null ? 'var_$name' : fallback;

  YulBlock _generateBlock(Block block) {
    return YulBlock(block.statements.map(_generateStatement).toList());
  }

  YulStatement _generateStatement(Statement stmt) {
    switch (stmt) {
      case ReturnStatement(:final expression):
        if (expression == null || _returnSlots.isEmpty) return YulLeave();
        // `return (a, b)` → assign each declared return slot in order.
        if (expression is TupleExpression && _returnSlots.length > 1) {
          final stmts = <YulStatement>[];
          final n = expression.components.length < _returnSlots.length
              ? expression.components.length
              : _returnSlots.length;
          for (var i = 0; i < n; i++) {
            final component = expression.components[i];
            if (component != null) {
              stmts.add(
                YulAssignment([
                  _returnSlots[i],
                ], _generateExpression(component)),
              );
            }
          }
          stmts.add(YulLeave());
          return YulBlock(stmts);
        }
        final retExpr = _generateExpression(expression);
        final retPre = _drainPre();
        final retBlock = YulBlock([
          YulAssignment([_returnSlots.first], retExpr),
          YulLeave(),
        ]);
        if (retPre.isEmpty) return retBlock;
        return YulBlock([...retPre, retBlock]);

      case ExpressionStatement(:final expression):
        final s = _generateExpressionStatement(expression);
        return _wrapPre(s);

      case Block():
        return _generateBlock(stmt);

      case ForStatement(
        :final initStatement,
        :final condition,
        :final loopExpression,
        :final body,
      ):
        return YulForLoop(
          initStatement != null
              ? YulBlock([_generateStatement(initStatement)])
              : YulBlock([]),
          condition != null
              ? _generateExpression(condition)
              : YulLiteral('1', YulLiteralKind.number),
          loopExpression != null
              ? YulBlock([_generateStatement(loopExpression)])
              : YulBlock([]),
          _generateBlock2(body),
        );

      case WhileStatement(:final condition, :final body):
        return YulForLoop(
          YulBlock([]),
          _generateExpression(condition),
          YulBlock([]),
          _generateBlock2(body),
        );

      case DoWhileStatement(:final condition, :final body):
        // Yul has no do-while; run the body, then loop while the condition holds.
        // `for {} 1 {} { <body>; if iszero(cond) { break } }`
        final loopBody = <YulStatement>[
          ..._generateBlock2(body).statements,
          YulIf(
            YulFunctionCall('iszero', [_generateExpression(condition)]),
            YulBlock([YulBreak()]),
          ),
        ];
        return YulForLoop(
          YulBlock([]),
          YulLiteral('1', YulLiteralKind.number),
          YulBlock([]),
          YulBlock(loopBody),
        );

      case BreakStatement():
        return YulBreak();

      case ContinueStatement():
        return YulContinue();

      case IfStatement(:final condition, :final trueBody, :final falseBody):
        final condExpr = _generateExpression(condition);
        final condPre = _drainPre();
        if (falseBody == null) {
          final ifStmt = YulIf(condExpr, _generateBlock2(trueBody));
          if (condPre.isEmpty) return ifStmt;
          return YulBlock([...condPre, ifStmt]);
        }
        final tmp = _tmp();
        final ifBlock = YulBlock([
          YulVariableDeclaration([tmp], condExpr),
          YulIf(YulIdentifier(tmp), _generateBlock2(trueBody)),
          YulIf(
            YulFunctionCall('iszero', [YulIdentifier(tmp)]),
            _generateBlock2(falseBody),
          ),
        ]);
        if (condPre.isEmpty) return ifBlock;
        return YulBlock([...condPre, ifBlock]);

      case VariableDeclarationStatement(
        :final declarations,
        :final initialValue,
      ):
        for (final d in declarations) {
          if (d != null) _localNames.add(d.name);
        }
        final names = declarations
            .map((d) => d != null ? 'var_${d.name}' : '_')
            .toList();
        final initExpr = initialValue != null
            ? _generateExpression(initialValue)
            : null;
        final decl = YulVariableDeclaration(names, initExpr);
        return _wrapPre(decl);

      case UncheckedStatement(:final body):
        // Arithmetic inside `unchecked { … }` wraps instead of reverting.
        final savedChecked = _checked;
        _checked = false;
        final result = _generateBlock(body);
        _checked = savedChecked;
        return result;

      case RevertStatement(:final expression):
        return _generateRevert(expression);

      case EmitStatement(:final call):
        return _generateEmit(call);

      default:
        _diagnostics.warning(
          'Unhandled statement ${stmt.runtimeType} in IR generator',
          location: stmt.location,
        );
        return YulBlock([]);
    }
  }

  YulBlock _generateBlock2(Statement stmt) {
    if (stmt is Block) return _generateBlock(stmt);
    return YulBlock([_generateStatement(stmt)]);
  }

  /// Lowers an expression used as a statement, giving assignments and
  /// increment/decrement their store side-effect (which a value-only
  /// [_generateExpression] cannot express).
  YulStatement _generateExpressionStatement(Expression expr) {
    switch (expr) {
      case Assignment(
        :final operator$,
        :final leftHandSide,
        :final rightHandSide,
      ):
        // Whole-struct assignment `s = Struct(a, b, …)`: a struct value does
        // not fit in one EVM word, so the single-word path below would emit a
        // bogus `fun_Struct` call (jump-to-0 at runtime).  Expand it to one
        // `sstore` per member instead.
        if (operator$ == '=') {
          final structAssign = _tryStructLiteralAssignment(
            leftHandSide,
            rightHandSide,
          );
          if (structAssign != null) return structAssign;
        }
        var value = _generateExpression(rightHandSide);
        if (operator$ != '=') {
          // Compound assignment: x op= y  ⇒  x = x op y.
          final baseOp = operator$.substring(0, operator$.length - 1);
          value = _binaryOp(
            baseOp,
            _readLValue(leftHandSide),
            value,
            _intTypeOf(leftHandSide) ?? _intTypeOf(rightHandSide),
            expr.location,
          );
        }
        return _writeLValue(leftHandSide, value);

      case UnaryOperation(:final operator$, :final subExpression)
          when operator$ == '++' || operator$ == '--':
        final value = _binaryOp(
          operator$ == '++' ? '+' : '-',
          _readLValue(subExpression),
          YulLiteral('1', YulLiteralKind.number),
          _intTypeOf(subExpression),
          expr.location,
        );
        return _writeLValue(subExpression, value);

      // Statement-level built-ins: require / assert / revert(...).
      case FunctionCall(expression: Identifier(:final name), :final arguments)
          when _isStatementBuiltin(name):
        return _generateBuiltinStatement(name, arguments, expr.location);

      // Dynamic array .push(value) / .pop()
      case FunctionCall(
            expression: MemberAccess(
              expression: final arrayExpr,
              memberName: final memberName,
            ),
            arguments: final arguments,
          )
          when (memberName == 'push' || memberName == 'pop') &&
              _isStorageIndex(arrayExpr):
        return _generateArrayPushPop(memberName, arrayExpr, arguments);

      default:
        return YulExpressionStatement(_generateExpression(expr));
    }
  }

  /// Lowers `target = StructName(arg0, arg1, …)` into one `sstore` per struct
  /// member, or returns null when [rhs] is not a struct-constructor call (so
  /// the caller falls back to the generic assignment path).
  YulStatement? _tryStructLiteralAssignment(Expression target, Expression rhs) {
    if (rhs is! FunctionCall) return null;
    final callee = rhs.expression;
    if (callee is! Identifier) return null;
    final struct = _structs[callee.name];
    if (struct == null) return null;

    if (!_isStorageIndex(target)) {
      _diagnostics.warning(
        'Struct literal assignment to a non-storage target is not supported',
        location: target.location,
      );
      return null;
    }
    if (rhs.arguments.length != struct.members.length) {
      _diagnostics.warning(
        'Struct "${struct.name}" constructed with ${rhs.arguments.length} '
        'argument(s) but declares ${struct.members.length} member(s)',
        location: rhs.location,
      );
      return null;
    }

    final baseSlot = _storageSlotOf(target);
    final stmts = <YulStatement>[];
    var offset = 0;
    for (var i = 0; i < struct.members.length; i++) {
      final member = struct.members[i];
      final size = _slotSizeOf(member.typeName);
      if (size != 1) {
        // Nested struct / array member: not representable as a single word.
        _diagnostics.warning(
          'Struct member "${member.name}" spans multiple slots; struct '
          'literal assignment supports value-type members only',
          location: rhs.location,
        );
        return null;
      }
      final slot = offset == 0
          ? baseSlot
          : YulFunctionCall('add', [
              baseSlot,
              YulLiteral('$offset', YulLiteralKind.number),
            ]);
      stmts.add(
        YulExpressionStatement(
          YulFunctionCall('sstore', [
            slot,
            _generateExpression(rhs.arguments[i]),
          ]),
        ),
      );
      offset += size;
    }
    return YulBlock(stmts);
  }

  static bool _isStatementBuiltin(String name) =>
      name == 'require' || name == 'assert' || name == 'revert';

  /// Lowers `require(c)`, `require(c, "msg")`, `assert(c)`, and `revert(...)`.
  YulStatement _generateBuiltinStatement(
    String name,
    List<Expression> args,
    SourceLocation location,
  ) {
    switch (name) {
      case 'require':
        if (args.isEmpty) return YulBlock([]);
        final cond = _generateExpression(args.first);
        final onFail = args.length >= 2 && args[1] is Literal
            ? _revertWithReason((args[1] as Literal).value)
            : [_revertCall(0, 0)];
        return YulIf(YulFunctionCall('iszero', [cond]), YulBlock(onFail));
      case 'assert':
        if (args.isEmpty) return YulBlock([]);
        final cond = _generateExpression(args.first);
        return YulIf(
          YulFunctionCall('iszero', [cond]),
          YulBlock([_callStmt(_panic(0x01), const [])]),
        );
      case 'revert':
        return _generateRevert(
          args.isEmpty
              ? null
              : FunctionCall(
                  location,
                  Identifier(location, 'revert'),
                  args,
                  const [],
                ),
        );
    }
    return YulBlock([]);
  }

  /// Lowers a `revert …;` statement: `revert()`, `revert("msg")`
  /// (`Error(string)`), or `revert CustomError(args)` (selector + ABI args).
  YulStatement _generateRevert(Expression? expression) {
    if (expression is FunctionCall) {
      final callee = expression.expression;
      if (callee is Identifier && callee.name == 'revert') {
        if (expression.arguments.length == 1 &&
            expression.arguments.first is Literal) {
          return YulBlock(
            _revertWithReason((expression.arguments.first as Literal).value),
          );
        }
        return YulBlock([_revertCall(0, 0)]);
      }
      if (callee is Identifier && _errors.containsKey(callee.name)) {
        return YulBlock(
          _revertWithError(_errors[callee.name]!, expression.arguments),
        );
      }
    }
    return YulBlock([_revertCall(0, 0)]);
  }

  /// `revert CustomError(args)` → store the 4-byte selector + ABI-encoded
  /// (static value-type) args in memory and revert with them.
  List<YulStatement> _revertWithError(
    CustomErrorDefinition error,
    List<Expression> args,
  ) {
    final selector = int.parse(
      selectorHex(errorSignature(error)).substring(2),
      radix: 16,
    );
    final stmts = <YulStatement>[
      _callStmt('mstore', [_n('0'), _n(_selectorWord(selector))]),
      for (var i = 0; i < args.length; i++)
        _callStmt('mstore', [
          _n('${4 + i * 32}'),
          _generateExpression(args[i]),
        ]),
    ];
    stmts.add(_revertCall(0, 4 + args.length * 32));
    return stmts;
  }

  /// Lowers `emit Event(args)` to a `log{n}` with the (compile-time) topic-0
  /// hash, indexed args as topics, and non-indexed args as ABI-encoded data.
  YulStatement _generateEmit(Expression call) {
    if (call is! FunctionCall || call.expression is! Identifier) {
      _diagnostics.warning('Unsupported emit target', location: call.location);
      return YulBlock([]);
    }
    final name = (call.expression as Identifier).name;
    final event = _events[name];
    if (event == null) {
      _diagnostics.warning('Unknown event "$name"', location: call.location);
      return YulBlock([]);
    }

    final topics = <YulExpression>[];
    if (!event.anonymous) {
      topics.add(_n(eventTopicHex(event)));
    }
    final dataArgs = <YulExpression>[];
    for (
      var i = 0;
      i < call.arguments.length && i < event.parameters.length;
      i++
    ) {
      final value = _generateExpression(call.arguments[i]);
      if (event.parameters[i].indexed) {
        topics.add(value);
      } else {
        dataArgs.add(value);
      }
    }

    final stmts = <YulStatement>[
      for (var i = 0; i < dataArgs.length; i++)
        _callStmt('mstore', [_n('${i * 32}'), dataArgs[i]]),
    ];
    stmts.add(
      _callStmt('log${topics.length}', [
        _n('0'),
        _n('${dataArgs.length * 32}'),
        ...topics,
      ]),
    );
    return YulBlock(stmts);
  }

  /// Reads an assignable expression (identifier or storage index — local,
  /// state variable, or `mapping[key]` / `array[i]`).
  YulExpression _readLValue(Expression target) {
    if (target is Identifier && _isStateVar(target.name)) {
      return YulFunctionCall('sload', [_slot(target.name)]);
    }
    if (target is IndexAccess && _isStorageIndex(target)) {
      return YulFunctionCall('sload', [_storageSlotOf(target)]);
    }
    if (target is MemberAccess && _isStorageIndex(target)) {
      return YulFunctionCall('sload', [_storageSlotOf(target)]);
    }
    return _generateExpression(target);
  }

  /// Writes [value] to an assignable expression as a statement.
  YulStatement _writeLValue(Expression target, YulExpression value) {
    if (target is Identifier) {
      if (_isStateVar(target.name)) {
        return YulExpressionStatement(
          YulFunctionCall('sstore', [_slot(target.name), value]),
        );
      }
      return YulAssignment(['var_${target.name}'], value);
    }
    if (target is IndexAccess && _isStorageIndex(target)) {
      return YulExpressionStatement(
        YulFunctionCall('sstore', [_storageSlotOf(target), value]),
      );
    }
    if (target is MemberAccess && _isStorageIndex(target)) {
      return YulExpressionStatement(
        YulFunctionCall('sstore', [_storageSlotOf(target), value]),
      );
    }
    _diagnostics.warning(
      'Unhandled assignment target ${target.runtimeType} in IR generator',
      location: target.location,
    );
    return YulExpressionStatement(value);
  }

  bool _isStateVar(String name) =>
      !_localNames.contains(name) && _stateVarSlots.containsKey(name);

  YulExpression _slot(String name) =>
      YulLiteral('${_stateVarSlots[name]}', YulLiteralKind.number);

  YulExpression _generateExpression(Expression expr) {
    switch (expr) {
      case Literal(:final kind, :final value):
        // String/unicode string literals are packed into Solidity's short-string
        // storage layout (≤31 bytes) so they can be sstore'd directly.
        if (kind == LiteralKind.string || kind == LiteralKind.unicodeString) {
          final content = _unquote(value);
          final packed = _packShortStringLiteral(content);
          if (packed != null) {
            return YulLiteral(packed, YulLiteralKind.number);
          }
          // Long string literal: not supported in codegen yet.
          _diagnostics.warning(
            'String literal longer than 31 bytes not supported in codegen: $value',
            location: expr.location,
          );
          return YulLiteral('0', YulLiteralKind.number);
        }
        if (kind == LiteralKind.hexString) {
          // hex"aabbcc" → pack as bytes, same short-string layout.
          final hexContent = _unquote(value);
          final hexBody = hexContent.startsWith('hex')
              ? hexContent.substring(4, hexContent.length - 1)
              : hexContent;
          final bytes = <int>[];
          for (var i = 0; i + 1 < hexBody.length; i += 2) {
            bytes.add(int.parse(hexBody.substring(i, i + 2), radix: 16));
          }
          if (bytes.length <= 31) {
            final word = List<int>.filled(32, 0);
            for (var i = 0; i < bytes.length; i++) {
              word[i] = bytes[i];
            }
            word[31] = bytes.length * 2;
            final hex = word
                .map((b) => b.toRadixString(16).padLeft(2, '0'))
                .join();
            return YulLiteral('0x$hex', YulLiteralKind.number);
          }
          _diagnostics.warning(
            'hex literal longer than 31 bytes not supported in codegen: $value',
            location: expr.location,
          );
          return YulLiteral('0', YulLiteralKind.number);
        }
        return YulLiteral(
          value,
          kind == LiteralKind.bool$
              ? YulLiteralKind.bool$
              : YulLiteralKind.number,
        );

      case Identifier(:final name):
        if (_isStateVar(name)) {
          return YulFunctionCall('sload', [_slot(name)]);
        }
        return YulIdentifier('var_$name');

      case BinaryOperation(:final operator$, :final left, :final right):
        if (operator$ == '&&' || operator$ == '||') {
          return _shortCircuit(operator$, left, right);
        }
        return _binaryOp(
          operator$,
          _generateExpression(left),
          _generateExpression(right),
          _opIntType(left, right),
          expr.location,
        );

      case UnaryOperation(:final operator$, :final subExpression):
        return _unaryOp(operator$, subExpression, expr.location);

      case TypeConversion(:final typeName, :final expression):
        return _typeConversion(typeName, expression);

      case MemberAccess(:final expression, :final memberName):
        final global = _globalMember(expression, memberName);
        if (global != null) return global;

        // Dynamic array .length: the base slot stores the length.
        if (memberName == 'length' && _isStorageIndex(expression)) {
          final baseType = expression.annotation;
          if (baseType is ArrayType && !baseType.isFixed) {
            return YulFunctionCall('sload', [_storageSlotOf(expression)]);
          }
        }

        // Struct member read from storage.
        if (_isStorageIndex(expression)) {
          final structDef = _resolveStructType(expression);
          if (structDef != null) {
            return YulFunctionCall('sload', [_structMemberSlot(expr)]);
          }
        }

        _diagnostics.warning(
          'Unsupported member access ".$memberName" in IR generator',
          location: expr.location,
        );
        return YulLiteral('0', YulLiteralKind.number);

      case IndexAccess():
        if (_isStorageIndex(expr)) {
          return YulFunctionCall('sload', [_storageSlotOf(expr)]);
        }
        _diagnostics.warning(
          'Unsupported (non-storage) index access in IR generator',
          location: expr.location,
        );
        return YulLiteral('0', YulLiteralKind.number);

      case FunctionCall(:final expression, :final arguments):
        if (expression is Identifier) {
          final builtin = _valueBuiltin(expression.name, arguments.length);
          if (builtin != null) {
            return YulFunctionCall(
              builtin,
              arguments.map(_generateExpression).toList(),
            );
          }
          // A struct constructor (`Struct(a, b)`) yields a multi-word value
          // that cannot be used as a single-word expression.  Calling it
          // `fun_Struct` would jump to a non-existent function (offset 0).
          // Whole-struct *assignments* are handled in the statement lowerer;
          // any other use is unsupported.
          if (_structs.containsKey(expression.name)) {
            _diagnostics.warning(
              'Struct value "${expression.name}(…)" can only be assigned '
              'directly to a storage variable, not used inline',
              location: expr.location,
            );
            return YulLiteral('0', YulLiteralKind.number);
          }
          return YulFunctionCall(
            'fun_${expression.name}',
            arguments.map(_generateExpression).toList(),
          );
        }
        _diagnostics.warning(
          'Unsupported call target ${expression.runtimeType} in IR generator',
          location: expr.location,
        );
        return YulLiteral('0', YulLiteralKind.number);

      case Assignment(:final rightHandSide):
        // Side-effectful; only the assigned value is propagated for now.
        return _generateExpression(rightHandSide);

      default:
        _diagnostics.warning(
          'Unhandled expression ${expr.runtimeType}',
          location: expr.location,
        );
        return YulLiteral('0', YulLiteralKind.number);
    }
  }

  /// Short-circuit evaluation for `&&` and `||`.
  ///
  /// Emits the right-hand side evaluation code to [_preStmts] so the caller
  /// can place it before the expression's use site.  Returns a [YulIdentifier]
  /// naming the result.
  YulExpression _shortCircuit(String op, Expression left, Expression right) {
    final leftExpr = _generateExpression(left);
    final leftPre = _drainPre();

    final rightExpr = _generateExpression(right);
    final rightPre = _drainPre();

    final tmp = _tmp();

    // let tmp := leftExpr
    // if (op=='&&') tmp { <rightPre>; tmp := rightExpr }
    // if (op=='||') iszero(tmp) { <rightPre>; tmp := rightExpr }
    final condExpr = op == '&&'
        ? YulIdentifier(tmp)
        : YulFunctionCall('iszero', [YulIdentifier(tmp)]);

    _preStmts
      ..addAll(leftPre)
      ..add(YulVariableDeclaration([tmp], leftExpr))
      ..add(
        YulIf(
          condExpr,
          YulBlock([
            ...rightPre,
            YulAssignment([tmp], rightExpr),
          ]),
        ),
      );

    return YulIdentifier(tmp);
  }

  /// Lowers a binary operator over already-generated operands.
  ///
  /// [type] is the integer type that governs the operation (used to pick
  /// signed vs unsigned opcodes and the width for overflow checks); it is
  /// `null` when the operands are not integers or are untyped, in which case
  /// the raw, unsigned, unchecked opcode is used.
  ///
  /// Comparisons without a direct opcode are composed via `iszero`, and shifts
  /// reorder operands to Yul's `shl(shift, value)` / `shr(shift, value)`.
  YulExpression _binaryOp(
    String op,
    YulExpression l,
    YulExpression r,
    IntType? type,
    SourceLocation location,
  ) {
    final signed = type?.signed ?? false;
    switch (op) {
      // ── Arithmetic (overflow-checked outside `unchecked`) ──
      case '+':
      case '-':
      case '*':
        if (type != null && _checked) {
          return YulFunctionCall(_checkedArith(op, type), [l, r]);
        }
        return YulFunctionCall(_rawArith(op), [l, r]);
      case '/':
        if (type != null) {
          return YulFunctionCall(_checkedDivMod('/', type), [l, r]);
        }
        return YulFunctionCall('div', [l, r]);
      case '%':
        if (type != null) {
          return YulFunctionCall(_checkedDivMod('%', type), [l, r]);
        }
        return YulFunctionCall('mod', [l, r]);
      case '**':
        if (type != null && _checked) {
          return YulFunctionCall(_checkedExp(type), [l, r]);
        }
        return YulFunctionCall('exp', [l, r]);

      // ── Comparisons (signedness-aware) ──
      case '==':
        return YulFunctionCall('eq', [l, r]);
      case '!=':
        return YulFunctionCall('iszero', [
          YulFunctionCall('eq', [l, r]),
        ]);
      case '<':
        return YulFunctionCall(signed ? 'slt' : 'lt', [l, r]);
      case '>':
        return YulFunctionCall(signed ? 'sgt' : 'gt', [l, r]);
      case '<=':
        return YulFunctionCall('iszero', [
          YulFunctionCall(signed ? 'sgt' : 'gt', [l, r]),
        ]);
      case '>=':
        return YulFunctionCall('iszero', [
          YulFunctionCall(signed ? 'slt' : 'lt', [l, r]),
        ]);

      // ── Bitwise & logical ──
      case '&':
        return YulFunctionCall('and', [l, r]);
      case '|':
        return YulFunctionCall('or', [l, r]);
      case '^':
        return YulFunctionCall('xor', [l, r]);
      // NOTE: `&&`/`||` are value-correct for booleans (always 0/1) but are not
      // yet short-circuited; an operand with side effects is always evaluated.
      case '&&':
        return YulFunctionCall('and', [l, r]);
      case '||':
        return YulFunctionCall('or', [l, r]);

      // ── Shifts: Yul takes shl/shr/sar(shift, value) ──
      case '<<':
        return YulFunctionCall('shl', [r, l]);
      case '>>':
        return YulFunctionCall(signed ? 'sar' : 'shr', [r, l]);
      case '>>>':
        return YulFunctionCall('shr', [r, l]);
    }
    _diagnostics.error('Unsupported binary operator "$op"', location: location);
    return YulLiteral('0', YulLiteralKind.number);
  }

  static String _rawArith(String op) => switch (op) {
    '+' => 'add',
    '-' => 'sub',
    '*' => 'mul',
    _ => 'add',
  };

  /// Lowers a unary operator to a Yul expression.
  ///
  /// `++`/`--` return the updated value here; their store side-effect is only
  /// emitted when they appear as a statement ([_generateExpressionStatement]).
  YulExpression _unaryOp(String op, Expression sub, SourceLocation location) {
    switch (op) {
      case '!':
        return YulFunctionCall('iszero', [_generateExpression(sub)]);
      case '~':
        return YulFunctionCall('not', [_generateExpression(sub)]);
      case '-':
        return YulFunctionCall('sub', [
          YulLiteral('0', YulLiteralKind.number),
          _generateExpression(sub),
        ]);
      case '+':
        return _generateExpression(sub); // unary plus: no-op
      case '++':
      case '--':
        return _binaryOp(
          op == '++' ? '+' : '-',
          _readLValue(sub),
          YulLiteral('1', YulLiteralKind.number),
          _intTypeOf(sub),
          location,
        );
    }
    _diagnostics.error('Unsupported unary operator "$op"', location: location);
    return YulLiteral('0', YulLiteralKind.number);
  }

  // ── ABI helpers ───────────────────────────────────────────────────────────

  /// `return(0, size)` — hands back the ABI-encoded head region.
  YulStatement _abiReturn(int size) => YulExpressionStatement(
    YulFunctionCall('return', [
      YulLiteral('0', YulLiteralKind.number),
      YulLiteral('$size', YulLiteralKind.number),
    ]),
  );

  /// Whether [p] is a `string` or `bytes` (dynamic) parameter.
  static bool _isDynamicStringParam(Parameter p) {
    final tn = p.typeName;
    if (tn is! ElementaryTypeName) return false;
    return tn.name == 'string' || tn.name == 'bytes';
  }

  /// Decodes the [index]-th ABI-encoded argument.
  ///
  /// Value types: `calldataload(4 + i*32)`.
  /// Dynamic types (`string`/`bytes`): the head word is an offset from byte 4;
  /// the data starts at `4 + offset` with a 32-byte length prefix.
  /// We copy the data to a fresh scratch area in memory and leave a memory
  /// pointer on the Yul stack — for now the pointer is what gets stored as the
  /// "value" (actual string ops are limited, but storage via mstore works for
  /// short strings).
  YulExpression _decodeParam(Parameter p, int index) {
    if (_isDynamicStringParam(p)) {
      // The head word is the offset from byte 4 in the ABI tail.
      // Actual data: 4 + offset bytes in calldata.
      // For now we expose the calldata offset of the length word as the value.
      // This is sufficient for passing to storage helpers.
      final offsetPtr = YulFunctionCall('calldataload', [
        YulLiteral('${4 + index * 32}', YulLiteralKind.number),
      ]);
      // Return the absolute calldata offset of the length word.
      return YulFunctionCall('add', [
        YulLiteral('4', YulLiteralKind.number),
        offsetPtr,
      ]);
    }
    return YulFunctionCall('calldataload', [
      YulLiteral('${4 + index * 32}', YulLiteralKind.number),
    ]);
  }

  // ── Type inference for code generation ─────────────────────────────────────

  /// The integer type that governs a binary operation over [left]/[right], or
  /// `null` if it is not over modelled integers. A non-literal operand's type
  /// is preferred because number literals are typed `uint256` by the checker
  /// and would otherwise mask the real width and signedness.
  IntType? _opIntType(Expression left, Expression right) {
    final lt = _intTypeOf(left);
    final rt = _intTypeOf(right);
    if (left is! Literal && lt != null) return lt;
    if (right is! Literal && rt != null) return rt;
    return lt ?? rt;
  }

  IntType? _intTypeOf(Expression e) {
    final t = e.annotation;
    return t is IntType ? t : null;
  }

  // ── Global members (msg.sender, block.timestamp, …) ────────────────────────

  /// Lowers `base.member` for built-in globals, or null if not a known global.
  YulExpression? _globalMember(Expression base, String member) {
    if (base is! Identifier) return null;
    final builtin = _globalMembers['${base.name}.$member'];
    return builtin == null ? null : YulFunctionCall(builtin, const []);
  }

  static const _globalMembers = {
    'msg.sender': 'caller',
    'msg.value': 'callvalue',
    'tx.origin': 'origin',
    'tx.gasprice': 'gasprice',
    'block.number': 'number',
    'block.timestamp': 'timestamp',
    'block.coinbase': 'coinbase',
    'block.gaslimit': 'gaslimit',
    'block.chainid': 'chainid',
    'block.basefee': 'basefee',
    'block.difficulty': 'prevrandao',
    'block.prevrandao': 'prevrandao',
  };

  // ── Storage slot computation (state vars, mappings, arrays) ─────────────────

  /// Whether [e] ultimately refers to contract storage (a state variable or an
  /// index/member into one), so reads/writes lower to `sload`/`sstore`.
  bool _isStorageIndex(Expression e) {
    if (e is Identifier) return _isStateVar(e.name);
    if (e is IndexAccess) return _isStorageIndex(e.base);
    if (e is MemberAccess) return _isStorageMemberAccess(e);
    return false;
  }

  /// True when [e] is a struct member access rooted at a storage variable.
  bool _isStorageMemberAccess(MemberAccess e) {
    // If the base is a storage variable or index, treat as storage.
    return _isStorageIndex(e.expression);
  }

  /// The storage slot of an l-value rooted at a state variable.
  ///
  ///  * state variable `v`               → its assigned base slot
  ///  * `m[k]` where `m : mapping`       → `keccak256(k . slot(m))`
  ///  * `a[i]` where `a : T[]` (dynamic) → `keccak256(slot(a)) + i`
  ///  * `a[i]` where `a : T[N]` (fixed)  → `slot(a) + i * slotSize(T)`
  ///  * `s.field` where `s : struct`     → `slot(s) + memberOffset(field)`
  YulExpression _storageSlotOf(Expression target) {
    if (target is Identifier && _isStateVar(target.name)) {
      return _slot(target.name);
    }
    if (target is IndexAccess) {
      final baseSlot = _storageSlotOf(target.base);
      final index = target.index != null
          ? _generateExpression(target.index!)
          : YulLiteral('0', YulLiteralKind.number);
      final baseType = target.base.annotation;
      if (baseType is MappingType) {
        return YulFunctionCall(_mappingSlotHelper(), [index, baseSlot]);
      }
      if (baseType is ArrayType && baseType.length == null) {
        return YulFunctionCall(_dynArraySlotHelper(), [baseSlot, index]);
      }
      // Fixed-size array: elements are laid out contiguously.
      // Element stride = slot size of element type.
      if (baseType is ArrayType && baseType.length != null) {
        final elemSize = _slotSizeOf(
          _typeNameOf(target.base) ??
              ElementaryTypeName(SourceLocation.invalid, 'uint256'),
        );
        if (elemSize == 1) {
          return YulFunctionCall('add', [baseSlot, index]);
        }
        return YulFunctionCall('add', [
          baseSlot,
          YulFunctionCall('mul', [
            index,
            YulLiteral('$elemSize', YulLiteralKind.number),
          ]),
        ]);
      }
      return YulFunctionCall('add', [baseSlot, index]);
    }
    if (target is MemberAccess) {
      return _structMemberSlot(target);
    }
    _diagnostics.warning(
      'Unsupported storage location ${target.runtimeType} in IR generator',
      location: target.location,
    );
    return YulLiteral('0', YulLiteralKind.number);
  }

  /// Computes the storage slot for a struct member access `expr.memberName`.
  YulExpression _structMemberSlot(MemberAccess access) {
    final baseSlot = _storageSlotOf(access.expression);
    // Find the struct definition from the base expression's type annotation.
    final structDef = _resolveStructType(access.expression);
    if (structDef == null) {
      _diagnostics.warning(
        'Cannot resolve struct type for member access ".${access.memberName}"',
        location: access.location,
      );
      return baseSlot;
    }
    final offset = _structMemberOffset(structDef, access.memberName);
    if (offset < 0) {
      _diagnostics.warning(
        'Struct "${structDef.name}" has no member "${access.memberName}"',
        location: access.location,
      );
      return baseSlot;
    }
    if (offset == 0) return baseSlot;
    return YulFunctionCall('add', [
      baseSlot,
      YulLiteral('$offset', YulLiteralKind.number),
    ]);
  }

  /// Attempts to resolve the [StructDefinition] for [expr]'s storage type.
  StructDefinition? _resolveStructType(Expression expr) {
    // Fall back to looking at the TypeName in the AST.
    final typeName = _typeNameOf(expr);
    if (typeName is UserDefinedTypeName) {
      return _structs[typeName.name];
    }
    return null;
  }

  /// Extracts the [TypeName] AST node associated with [expr], if available.
  TypeName? _typeNameOf(Expression expr) {
    // We can reach the TypeName for identifiers that are state variables.
    if (expr is Identifier && _isStateVar(expr.name)) {
      // Find the state variable declaration.
      // (We can't easily recover the AST here without more bookkeeping,
      //  so return null for now.)
      return _stateVarTypeNames[expr.name];
    }
    if (expr is IndexAccess) {
      final baseType = _typeNameOf(expr.base);
      if (baseType is ArrayTypeName) return baseType.baseType;
      if (baseType is MappingTypeName) return baseType.valueType;
    }
    return null;
  }

  /// `keccak256(key . slot)` — the value slot of `mapping[key]`.
  String _mappingSlotHelper() => _register(
    'mapping_slot',
    () => YulFunctionDefinition(
      'mapping_slot',
      ['key', 'slot'],
      ['result'],
      YulBlock([
        _callStmt('mstore', [_n('0'), _id('key')]),
        _callStmt('mstore', [_n('0x20'), _id('slot')]),
        YulAssignment(['result'], _c('keccak256', [_n('0'), _n('0x40')])),
      ]),
    ),
  );

  /// Generates the Yul for `array.push(value)` or `array.pop()`.
  YulStatement _generateArrayPushPop(
    String memberName,
    Expression arrayExpr,
    List<Expression> arguments,
  ) {
    final slot = _storageSlotOf(arrayExpr);
    final lenTmp = _tmp();
    if (memberName == 'push') {
      return YulBlock([
        YulVariableDeclaration([lenTmp], YulFunctionCall('sload', [slot])),
        YulExpressionStatement(
          YulFunctionCall('sstore', [
            YulFunctionCall(_dynArraySlotHelper(), [
              slot,
              YulIdentifier(lenTmp),
            ]),
            arguments.isNotEmpty
                ? _generateExpression(arguments.first)
                : _n('0'),
          ]),
        ),
        YulExpressionStatement(
          YulFunctionCall('sstore', [
            slot,
            YulFunctionCall('add', [YulIdentifier(lenTmp), _n('1')]),
          ]),
        ),
      ]);
    } else {
      // pop()
      final newLenTmp = _tmp();
      return YulBlock([
        YulVariableDeclaration([lenTmp], YulFunctionCall('sload', [slot])),
        YulIf(
          YulFunctionCall('iszero', [YulIdentifier(lenTmp)]),
          YulBlock([_callStmt(_panic(0x31), const [])]),
        ),
        YulVariableDeclaration([
          newLenTmp,
        ], YulFunctionCall('sub', [YulIdentifier(lenTmp), _n('1')])),
        YulExpressionStatement(
          YulFunctionCall('sstore', [
            YulFunctionCall(_dynArraySlotHelper(), [
              slot,
              YulIdentifier(newLenTmp),
            ]),
            _n('0'),
          ]),
        ),
        YulExpressionStatement(
          YulFunctionCall('sstore', [slot, YulIdentifier(newLenTmp)]),
        ),
      ]);
    }
  }

  /// `keccak256(slot) + index` — the element slot of a dynamic array.
  String _dynArraySlotHelper() => _register(
    'dyn_array_slot',
    () => YulFunctionDefinition(
      'dyn_array_slot',
      ['slot', 'index'],
      ['result'],
      YulBlock([
        _callStmt('mstore', [_n('0'), _id('slot')]),
        YulAssignment(
          ['result'],
          _c('add', [
            _c('keccak256', [_n('0'), _n('0x20')]),
            _id('index'),
          ]),
        ),
      ]),
    ),
  );

  // ── Built-in value functions ───────────────────────────────────────────────

  /// Maps an expression-position built-in to its Yul/EVM builtin, or `null`
  /// if [name] is not a (supported) value-returning built-in.
  static String? _valueBuiltin(String name, int argc) {
    switch (name) {
      case 'addmod':
        return argc == 3 ? 'addmod' : null;
      case 'mulmod':
        return argc == 3 ? 'mulmod' : null;
      case 'gasleft':
        return argc == 0 ? 'gas' : null;
      case 'blockhash':
        return argc == 1 ? 'blockhash' : null;
      default:
        return null;
    }
  }

  // ── Type conversions (casts) ───────────────────────────────────────────────

  /// Lowers `T(x)` for elementary value types. Widening (or same-width) casts
  /// are no-ops on the 256-bit word; narrowing masks (unsigned/address) or
  /// sign-extends (signed) down to the target width.
  YulExpression _typeConversion(TypeName typeName, Expression expr) {
    final value = _generateExpression(expr);
    if (typeName is! ElementaryTypeName) return value;
    final name = typeName.name;
    if (name == 'bool') return value;
    if (name == 'address' || name == 'address payable') {
      return YulFunctionCall('and', [
        value,
        YulLiteral(_maskHex(160), YulLiteralKind.number),
      ]);
    }
    if (name.startsWith('uint')) {
      final bits = typeName.intWidth == 0 ? 256 : typeName.intWidth;
      if (bits >= 256) return value;
      return YulFunctionCall('and', [
        value,
        YulLiteral(_maskHex(bits), YulLiteralKind.number),
      ]);
    }
    if (name.startsWith('int')) {
      final bits = typeName.intWidth == 0 ? 256 : typeName.intWidth;
      if (bits >= 256) return value;
      return YulFunctionCall('signextend', [
        YulLiteral('${bits ~/ 8 - 1}', YulLiteralKind.number),
        value,
      ]);
    }
    // bytesN / string / bytes: keep as-is for the value-type subset.
    return value;
  }

  // ── Checked arithmetic & panics ────────────────────────────────────────────

  String _register(String name, YulFunctionDefinition Function() build) {
    if (!_helpers.containsKey(name)) _helpers[name] = build();
    return name;
  }

  /// Name of the Panic(uint256) helper for [code] (e.g. 0x11 overflow,
  /// 0x12 division by zero), registering it on first use.
  String _panic(int code) {
    final name = 'panic_0x${code.toRadixString(16)}';
    return _register(
      name,
      () => YulFunctionDefinition(
        name,
        const [],
        const [],
        YulBlock([
          _callStmt('mstore', [_n('0'), _n(_selectorWord(0x4e487b71))]),
          _callStmt('mstore', [_n('4'), _n('0x${code.toRadixString(16)}')]),
          _callStmt('revert', [_n('0'), _n('0x24')]),
        ]),
      ),
    );
  }

  /// Registers and names the overflow-checked add/sub/mul routine for [t].
  String _checkedArith(String op, IntType t) {
    final kind = op == '+'
        ? 'add'
        : op == '-'
        ? 'sub'
        : 'mul';
    final name = 'checked_${kind}_${t.abiType}';
    return _register(name, () => _buildCheckedArith(name, kind, t));
  }

  YulFunctionDefinition _buildCheckedArith(
    String name,
    String kind,
    IntType t,
  ) {
    final w = t.bits;
    final panic = _panic(0x11);
    final body = <YulStatement>[
      YulAssignment(['r'], YulFunctionCall(kind, [_id('x'), _id('y')])),
    ];
    if (!t.signed) {
      switch (kind) {
        case 'add':
          body.add(
            w == 256
                ? _ifPanic(_c('gt', [_id('x'), _id('r')]), panic) // r < x
                : _ifPanic(_c('gt', [_id('r'), _n(_maxHex(t))]), panic),
          );
        case 'sub':
          body.add(_ifPanic(_c('gt', [_id('y'), _id('x')]), panic)); // y > x
        case 'mul':
          body.add(
            _ifPanic(
              _c('and', [
                _c('iszero', [
                  _c('iszero', [_id('x')]),
                ]),
                _c('iszero', [
                  _c('eq', [
                    _c('div', [_id('r'), _id('x')]),
                    _id('y'),
                  ]),
                ]),
              ]),
              panic,
            ),
          );
          if (w < 256) {
            body.add(_ifPanic(_c('gt', [_id('r'), _n(_maxHex(t))]), panic));
          }
      }
    } else {
      switch (kind) {
        case 'add':
          body.add(
            w == 256
                ? _ifPanic(
                    _c('or', [
                      _c('and', [
                        _c('sgt', [_id('y'), _n('0')]),
                        _c('slt', [_id('r'), _id('x')]),
                      ]),
                      _c('and', [
                        _c('slt', [_id('y'), _n('0')]),
                        _c('sgt', [_id('r'), _id('x')]),
                      ]),
                    ]),
                    panic,
                  )
                : _ifPanic(_signedOutOfRange('r', t), panic),
          );
        case 'sub':
          body.add(
            w == 256
                ? _ifPanic(
                    _c('or', [
                      _c('and', [
                        _c('iszero', [
                          _c('slt', [_id('y'), _n('0')]),
                        ]),
                        _c('sgt', [_id('r'), _id('x')]),
                      ]),
                      _c('and', [
                        _c('slt', [_id('y'), _n('0')]),
                        _c('slt', [_id('r'), _id('x')]),
                      ]),
                    ]),
                    panic,
                  )
                : _ifPanic(_signedOutOfRange('r', t), panic),
          );
        case 'mul':
          body.add(
            _ifPanic(
              _c('and', [
                _c('iszero', [
                  _c('iszero', [_id('x')]),
                ]),
                _c('iszero', [
                  _c('eq', [
                    _c('sdiv', [_id('r'), _id('x')]),
                    _id('y'),
                  ]),
                ]),
              ]),
              panic,
            ),
          );
          body.add(
            w == 256
                ? _ifPanic(
                    _c('and', [
                      _c('eq', [_id('x'), _n(_minusOneHex)]),
                      _c('eq', [_id('y'), _n(_minHex(t))]),
                    ]),
                    panic,
                  )
                : _ifPanic(_signedOutOfRange('r', t), panic),
          );
      }
    }
    return YulFunctionDefinition(name, ['x', 'y'], ['r'], YulBlock(body));
  }

  /// Registers and names the checked division/modulo routine for [t]
  /// (Panic(0x12) on a zero divisor, Panic(0x11) on `type(T).min / -1`).
  String _checkedDivMod(String op, IntType t) {
    final yulOp = op == '/'
        ? (t.signed ? 'sdiv' : 'div')
        : (t.signed ? 'smod' : 'mod');
    final name = 'checked_${yulOp}_${t.abiType}';
    return _register(name, () => _buildCheckedDivMod(name, op, yulOp, t));
  }

  YulFunctionDefinition _buildCheckedDivMod(
    String name,
    String op,
    String yulOp,
    IntType t,
  ) {
    final isDiv = op == '/';
    final body = <YulStatement>[
      _ifPanic(_c('iszero', [_id('y')]), _panic(0x12)),
    ];
    if (t.signed && isDiv && t.bits == 256) {
      body.add(
        _ifPanic(
          _c('and', [
            _c('eq', [_id('x'), _n(_minHex(t))]),
            _c('eq', [_id('y'), _n(_minusOneHex)]),
          ]),
          _panic(0x11),
        ),
      );
    }
    body.add(YulAssignment(['r'], _c(yulOp, [_id('x'), _id('y')])));
    if (t.signed && isDiv && t.bits < 256) {
      body.add(_ifPanic(_signedOutOfRange('r', t), _panic(0x11)));
    }
    return YulFunctionDefinition(name, ['x', 'y'], ['r'], YulBlock(body));
  }

  /// Registers and returns the name of the checked exponentiation helper.
  ///
  /// Uses exponentiation by squaring and checked_mul for overflow detection.
  String _checkedExp(IntType t) {
    final name = 'checked_exp_${t.abiType}';
    return _register(name, () {
      final mulName = _checkedArith('*', t);
      return YulFunctionDefinition(
        name,
        ['base', 'exp'],
        ['result'],
        YulBlock([
          YulAssignment(['result'], _n('1')),
          YulVariableDeclaration(['b'], _id('base')),
          YulVariableDeclaration(['e'], _id('exp')),
          YulForLoop(
            YulBlock([]),
            _c('gt', [_id('e'), _n('0')]),
            YulBlock([]),
            YulBlock([
              YulIf(
                _c('and', [_id('e'), _n('1')]),
                YulBlock([
                  YulAssignment([
                    'result',
                  ], _c(mulName, [_id('result'), _id('b')])),
                ]),
              ),
              YulAssignment(['e'], _c('shr', [_n('1'), _id('e')])),
              YulIf(
                _c('gt', [_id('e'), _n('0')]),
                YulBlock([
                  YulAssignment(['b'], _c(mulName, [_id('b'), _id('b')])),
                ]),
              ),
            ]),
          ),
        ]),
      );
    });
  }

  YulExpression _signedOutOfRange(String v, IntType t) => _c('or', [
    _c('sgt', [_id(v), _n(_maxHex(t))]),
    _c('slt', [_id(v), _n(_minHex(t))]),
  ]);

  // ── Revert helpers ─────────────────────────────────────────────────────────

  /// `revert(off, len)` as a statement.
  YulStatement _revertCall(int off, int len) =>
      _callStmt('revert', [_n('$off'), _n('$len')]);

  /// Encodes `Error(string)` revert data for [message] and reverts with it.
  List<YulStatement> _revertWithReason(String message) {
    final msg = _unquote(message);
    final bytes = msg.codeUnits;
    final len = bytes.length;
    final chunks = (len + 31) ~/ 32;
    final stmts = <YulStatement>[
      _callStmt('mstore', [_n('0'), _n(_selectorWord(0x08c379a0))]),
      _callStmt('mstore', [_n('4'), _n('0x20')]),
      _callStmt('mstore', [_n('0x24'), _n('$len')]),
      for (var i = 0; i < chunks; i++)
        _callStmt('mstore', [
          _n('${0x44 + i * 32}'),
          _n(_dataWord(bytes, i * 32)),
        ]),
      _revertCall(0, 0x44 + chunks * 0x20),
    ];
    return stmts;
  }

  static String _unquote(String s) {
    if (s.length >= 2 &&
        ((s.startsWith('"') && s.endsWith('"')) ||
            (s.startsWith("'") && s.endsWith("'")))) {
      return s.substring(1, s.length - 1);
    }
    return s;
  }

  // ── Yul construction shorthands ─────────────────────────────────────────────

  static YulIdentifier _id(String name) => YulIdentifier(name);
  static YulLiteral _n(String value) =>
      YulLiteral(value, YulLiteralKind.number);
  static YulFunctionCall _c(String name, List<YulExpression> args) =>
      YulFunctionCall(name, args);
  static YulStatement _callStmt(String name, List<YulExpression> args) =>
      YulExpressionStatement(YulFunctionCall(name, args));
  static YulIf _ifPanic(YulExpression cond, String panicFn) =>
      YulIf(cond, YulBlock([_callStmt(panicFn, const [])]));

  // ── Numeric literal formatting ──────────────────────────────────────────────

  static String _maskHex(int bits) =>
      '0x${((BigInt.one << bits) - BigInt.one).toRadixString(16)}';

  static String _maxHex(IntType t) => '0x${t.max.toRadixString(16)}';

  /// 256-bit two's-complement representation of the (negative) signed minimum.
  static String _minHex(IntType t) =>
      '0x${((BigInt.one << 256) + t.min).toRadixString(16)}';

  static final String _minusOneHex =
      '0x${((BigInt.one << 256) - BigInt.one).toRadixString(16)}';

  /// A 4-byte selector left-aligned in a 32-byte word (e.g. for `mstore(0, …)`).
  static String _selectorWord(int selector) =>
      '0x${selector.toRadixString(16).padLeft(8, '0')}${'0' * 56}';

  /// 32 bytes of [bytes] starting at [start], right-padded, as a `0x…` word.
  static String _dataWord(List<int> bytes, int start) {
    final sb = StringBuffer('0x');
    for (var i = 0; i < 32; i++) {
      final b = (start + i) < bytes.length ? bytes[start + i] & 0xff : 0;
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  String _tmp() => '__tmp${_tmpCounter++}';

  /// Clears and returns any pending pre-statements.
  List<YulStatement> _drainPre() {
    final stmts = List<YulStatement>.from(_preStmts);
    _preStmts.clear();
    return stmts;
  }

  /// Wraps [stmt] in a block that first emits any pending pre-statements.
  YulStatement _wrapPre(YulStatement stmt) {
    if (_preStmts.isEmpty) return stmt;
    return YulBlock([..._drainPre(), stmt]);
  }
}
