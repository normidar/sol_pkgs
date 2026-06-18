import 'package:sol_abi/sol_abi.dart';
import 'package:sol_ast/sol_ast.dart';
import 'package:sol_support/sol_support.dart';
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

  YulObject generateContract(ContractDefinition contract) {
    final runtimeBlock = _generateRuntimeCode(contract);
    final deployBlock = _generateDeploymentCode(contract.name);

    final runtimeObj = YulObject(
      '${contract.name}_deployed',
      runtimeBlock,
      [],
      {},
    );

    return YulObject(
      contract.name,
      deployBlock,
      [runtimeObj],
      {},
    );
  }

  // ── Deployment code ───────────────────────────────────────────────────────

  YulBlock _generateDeploymentCode(String contractName) {
    // Simplified: copy runtime object to memory and return it.
    // Real codegen runs the constructor and then returns the runtime code.
    return YulBlock([
      YulExpressionStatement(
        YulFunctionCall('codecopy', [
          YulLiteral('0', YulLiteralKind.number),
          YulFunctionCall('dataoffset', [
            YulLiteral('"${contractName}_deployed"', YulLiteralKind.string),
          ]),
          YulFunctionCall('datasize', [
            YulLiteral('"${contractName}_deployed"', YulLiteralKind.string),
          ]),
        ]),
      ),
      YulExpressionStatement(
        YulFunctionCall('return', [
          YulLiteral('0', YulLiteralKind.number),
          YulFunctionCall('datasize', [
            YulLiteral('"${contractName}_deployed"', YulLiteralKind.string),
          ]),
        ]),
      ),
    ]);
  }

  // ── Runtime code ──────────────────────────────────────────────────────────

  YulBlock _generateRuntimeCode(ContractDefinition contract) {
    final stmts = <YulStatement>[];

    // Dispatcher: read selector and route to functions.
    stmts.add(_generateDispatcher(contract));

    // Function implementations.
    for (final member in contract.members) {
      if (member is FunctionDefinition && member.body != null) {
        stmts.add(_generateFunction(member));
      }
    }

    // Revert if no selector matched.
    stmts.add(YulExpressionStatement(
      YulFunctionCall('revert', [
        YulLiteral('0', YulLiteralKind.number),
        YulLiteral('0', YulLiteralKind.number),
      ]),
    ));

    return YulBlock(stmts);
  }

  YulStatement _generateDispatcher(ContractDefinition contract) {
    final publicFns = contract.members
        .whereType<FunctionDefinition>()
        .where((fn) =>
            fn.visibility == Visibility.public ||
            fn.visibility == Visibility.external)
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
      } else {
        // Capture the return value(s), ABI-encode them into memory at 0x00,
        // then RETURN the head region (one 32-byte word per static value).
        final captures = [
          for (var i = 0; i < returnCount; i++) 'abi_ret_${fn.name}_$i',
        ];
        body.add(YulVariableDeclaration(captures, call));
        for (var i = 0; i < returnCount; i++) {
          body.add(YulExpressionStatement(
            YulFunctionCall('mstore', [
              YulLiteral('${i * 32}', YulLiteralKind.number),
              YulIdentifier(captures[i]),
            ]),
          ));
        }
        body.add(_abiReturn(returnCount * 32));
      }

      return YulCase(
        YulLiteral(selector, YulLiteralKind.number),
        YulBlock(body),
      );
    }).toList();

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
    _returnSlots
      ..clear()
      ..addAll(rets);
    final body = fn.body != null ? _generateBlock(fn.body!) : YulBlock([]);
    _returnSlots
      ..clear()
      ..addAll(savedReturnSlots);

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
              stmts.add(YulAssignment(
                [_returnSlots[i]],
                _generateExpression(component),
              ));
            }
          }
          stmts.add(YulLeave());
          return YulBlock(stmts);
        }
        return YulBlock([
          YulAssignment(
            [_returnSlots.first],
            _generateExpression(expression),
          ),
          YulLeave(),
        ]);

      case ExpressionStatement(:final expression):
        return YulExpressionStatement(_generateExpression(expression));

      case Block():
        return _generateBlock(stmt);

      case IfStatement(:final condition, :final trueBody, :final falseBody):
        if (falseBody == null) {
          return YulIf(_generateExpression(condition), _generateBlock2(trueBody));
        }
        final tmp = _tmp();
        return YulBlock([
          YulVariableDeclaration([tmp], _generateExpression(condition)),
          YulIf(YulIdentifier(tmp), _generateBlock2(trueBody)),
          YulIf(
            YulFunctionCall('iszero', [YulIdentifier(tmp)]),
            _generateBlock2(falseBody),
          ),
        ]);

      case VariableDeclarationStatement(:final declarations, :final initialValue):
        final names = declarations
            .map((d) => d != null ? 'var_${d.name}' : '_')
            .toList();
        return YulVariableDeclaration(
          names,
          initialValue != null ? _generateExpression(initialValue) : null,
        );

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

  YulExpression _generateExpression(Expression expr) {
    switch (expr) {
      case Literal(:final kind, :final value):
        return YulLiteral(
          value,
          kind == LiteralKind.bool$
              ? YulLiteralKind.bool$
              : kind == LiteralKind.string || kind == LiteralKind.unicodeString
                  ? YulLiteralKind.string
                  : YulLiteralKind.number,
        );

      case Identifier(:final name):
        return YulIdentifier('var_$name');

      case BinaryOperation(:final operator$, :final left, :final right):
        final yulFn = _binaryOpToYul[operator$];
        if (yulFn == null) {
          _diagnostics.error('Unsupported binary operator "${operator$}"',
              location: expr.location);
          return YulLiteral('0', YulLiteralKind.number);
        }
        return YulFunctionCall(yulFn, [
          _generateExpression(left),
          _generateExpression(right),
        ]);

      case FunctionCall(:final expression, :final arguments):
        final name = expression is Identifier ? 'fun_${expression.name}' : _tmp();
        return YulFunctionCall(
          name,
          arguments.map(_generateExpression).toList(),
        );

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

  static const _binaryOpToYul = {
    '+': 'add',
    '-': 'sub',
    '*': 'mul',
    '/': 'div',
    '%': 'mod',
    '**': 'exp',
    '&': 'and',
    '|': 'or',
    '^': 'xor',
    '<<': 'shl',
    '>>': 'shr',
    '>>>': 'shr', // Solidity has no unsigned shift at Yul level
    '==': 'eq',
    '<': 'lt',
    '>': 'gt',
  };

  // ── ABI helpers ───────────────────────────────────────────────────────────

  /// `return(0, size)` — hands back the ABI-encoded head region.
  YulStatement _abiReturn(int size) => YulExpressionStatement(
        YulFunctionCall('return', [
          YulLiteral('0', YulLiteralKind.number),
          YulLiteral('$size', YulLiteralKind.number),
        ]),
      );

  /// Decodes the [index]-th statically-encoded argument.
  ///
  /// Each value type occupies one 32-byte head word; argument `i` lives at
  /// `calldataload(4 + i*32)` (4 = selector). Dynamic types (string/bytes/
  /// dynamic arrays) need offset+length decoding and are not yet handled.
  YulExpression _decodeParam(Parameter p, int index) {
    return YulFunctionCall('calldataload', [
      YulLiteral('${4 + index * 32}', YulLiteralKind.number),
    ]);
  }

  String _tmp() => '__tmp${_tmpCounter++}';
}
