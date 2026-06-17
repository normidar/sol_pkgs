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

    // switch calldataload(0)
    final cases = publicFns.map((fn) {
      final selector = _functionSelector(fn);
      return YulCase(
        YulLiteral(selector, YulLiteralKind.number),
        YulBlock([
          YulExpressionStatement(
            YulFunctionCall(
              'fun_${fn.name}',
              fn.parameters.map((p) => _decodeParam(p)).toList(),
            ),
          ),
          YulExpressionStatement(
            YulFunctionCall('return', [
              YulLiteral('0', YulLiteralKind.number),
              YulLiteral('32', YulLiteralKind.number),
            ]),
          ),
        ]),
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
    final params = fn.parameters.map((p) => 'param_${p.name ?? _tmp()}').toList();
    final rets = fn.returnParameters.map((p) => 'ret_${p.name ?? _tmp()}').toList();

    final body = fn.body != null
        ? _generateBlock(fn.body!)
        : YulBlock([]);

    return YulFunctionDefinition('fun_${fn.name}', params, rets, body);
  }

  YulBlock _generateBlock(Block block) {
    return YulBlock(block.statements.map(_generateStatement).toList());
  }

  YulStatement _generateStatement(Statement stmt) {
    switch (stmt) {
      case ReturnStatement(:final expression):
        if (expression == null) return YulLeave();
        return YulBlock([
          YulAssignment(
            ['ret_0'],
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
          _diagnostics.error('Unsupported binary operator "$operator$"',
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

      case Assignment(:final leftHandSide, :final rightHandSide):
        // Side-effectful; wrap in a block expression via a temp.
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

  /// Keccak256 of `"name(type,type,…)"` truncated to 4 bytes → hex.
  /// Real implementation needs a keccak library; this is a placeholder.
  String _functionSelector(FunctionDefinition fn) {
    // TODO: compute real keccak256 selector.
    final sig = '${fn.name}(${fn.parameters.map((p) => p.typeName.toString()).join(',')})';
    final hash = sig.hashCode & 0xFFFFFFFF;
    return '0x${hash.toRadixString(16).padLeft(8, '0')}';
  }

  YulExpression _decodeParam(Parameter p) {
    // TODO: proper ABI decoding for complex types.
    return YulFunctionCall('calldataload', [
      YulLiteral('4', YulLiteralKind.number),
    ]);
  }

  String _tmp() => '__tmp${_tmpCounter++}';
}
