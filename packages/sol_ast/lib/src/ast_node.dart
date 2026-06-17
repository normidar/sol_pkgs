import 'package:sol_support/sol_support.dart';
import 'visitor.dart';

/// Base class for every node in the Solidity AST.
abstract class AstNode {
  AstNode(this.location);

  SourceLocation location;

  /// Annotation slot used by later compiler phases (sema, codegen).
  Object? annotation;

  void accept(AstVisitor visitor);
}

/// Abstract base for expression nodes.
///
/// Defined here (not in expressions.dart) so that type_names.dart can
/// reference it without creating a circular import.
abstract class Expression extends AstNode {
  Expression(super.location);
}

/// Abstract base for statement nodes.
abstract class Statement extends AstNode {
  Statement(super.location);
}
