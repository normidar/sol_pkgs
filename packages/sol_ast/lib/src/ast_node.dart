import 'package:sol_support/sol_support.dart';

/// Base class for every node in the Solidity AST.
abstract class AstNode {
  AstNode(this.location);

  SourceLocation location;

  /// Annotation slot used by later compiler phases (sema, codegen).
  Object? annotation;

  void accept(AstVisitor visitor);
}

// forward declaration so visitor.dart can be imported separately
abstract class AstVisitor {}
