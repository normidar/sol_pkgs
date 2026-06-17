/// Shared enumerations used across AST node types.
library;

enum DataLocation { storage, memory, calldata }

enum Visibility { external, public, internal, private, defaultVisibility }

enum StateMutability { pure, view, payable, nonpayable }

enum VariableMutability { mutable, immutable, constant }

enum ContractKind { contract, interface, library }

enum LiteralKind { number, string, unicodeString, hexString, bool$ }
