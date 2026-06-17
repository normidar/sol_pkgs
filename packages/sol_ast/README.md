# sol_ast

Solidity AST node definitions and double-dispatch visitor framework for the `sol_pkgs` compiler.

This package is the shared data model that the parser writes into, and that `sol_sema`, `sol_codegen`, and `sol_abi` read from.

## Node hierarchy

```
AstNode
├── SourceFile
├── PragmaDirective / ImportDirective
├── ContractDefinition
│   ├── FunctionDefinition
│   ├── ModifierDefinition
│   ├── StateVariableDeclaration
│   ├── EventDefinition / CustomErrorDefinition
│   ├── StructDefinition / EnumDefinition
│   └── VariableDeclaration
├── TypeName
│   ├── ElementaryTypeName   (uint256, address, bool …)
│   ├── ArrayTypeName        (T[] / T[N])
│   ├── MappingTypeName      (mapping(K => V))
│   ├── UserDefinedTypeName  (IERC20, SafeMath.add)
│   └── FunctionTypeName
├── Statement
│   ├── Block
│   ├── ReturnStatement / BreakStatement / ContinueStatement
│   ├── IfStatement / WhileStatement / ForStatement / DoWhileStatement
│   ├── ExpressionStatement / VariableDeclarationStatement
│   ├── EmitStatement / RevertStatement
│   └── AssemblyStatement
└── Expression
    ├── Literal              (number, string, bool)
    ├── Identifier
    ├── MemberAccess / IndexAccess / IndexRangeAccess
    ├── FunctionCall / FunctionCallOptions / NewExpression
    ├── UnaryOperation / BinaryOperation / Assignment
    ├── Conditional          (ternary)
    ├── TypeConversion
    └── TupleExpression
```

## Usage

```dart
import 'package:sol_ast/sol_ast.dart';
import 'package:sol_support/sol_support.dart';

class IdentifierCollector extends AstVisitor {
  final names = <String>[];

  @override
  void visitIdentifier(Identifier node) => names.add(node.name);
}

void main() {
  // Normally built by sol_parser; constructed manually here for illustration.
  const loc = SourceLocation(sourceIndex: 0, offset: 0, length: 0);
  final expr = BinaryOperation(loc, '+', Identifier(loc, 'a'), Identifier(loc, 'b'));

  final collector = IdentifierCollector();
  expr.accept(collector);
  print(collector.names); // [a, b]
}
```

## Annotation slot

Every `AstNode` has an `annotation` field (`Object?`) that later passes use to attach type information or IR references without coupling the AST to sema/codegen types.

## Dependencies

- `sol_support` — `SourceLocation`
