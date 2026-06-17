// ignore_for_file: constant_identifier_names
enum TokenKind {
  // ── Literals ──────────────────────────────────────────────────────────────
  NumberLiteral,
  StringLiteral,
  UnicodeStringLiteral,
  HexStringLiteral,
  TrueLiteral,
  FalseLiteral,

  // ── Identifiers & keywords ────────────────────────────────────────────────
  Identifier,

  // Control flow
  kIf,
  kElse,
  kFor,
  kWhile,
  kDo,
  kBreak,
  kContinue,
  kReturn,
  kRevert,

  // Contract structure
  kContract,
  kInterface,
  kLibrary,
  kAbstract,
  kIs,
  kInheritance, // placeholder for future use

  // Declarations
  kFunction,
  kConstructor,
  kFallback,
  kReceive,
  kModifier,
  kEvent,
  kError,
  kStruct,
  kEnum,
  kMapping,

  // Types – elementary
  kAddress,
  kBool,
  kString,
  kBytes,
  kInt,
  kUint,
  // int8…int256 / uint8…uint256 are emitted as IntN / UintN variants
  IntN,   // carries the bit width in Token.intWidth
  UintN,  // carries the bit width in Token.intWidth
  BytesN, // carries the byte count in Token.intWidth

  // Storage / visibility
  kPublic,
  kPrivate,
  kInternal,
  kExternal,
  kPure,
  kView,
  kPayable,
  kNonpayable,
  kStorage,
  kMemory,
  kCalldata,
  kImmutable,
  kConstant,
  kOverride,
  kVirtual,

  // Special values
  kNew,
  kDelete,
  kThis,
  kSuper,

  // Ether / time units
  kWei,
  kGwei,
  kEther,
  kSeconds,
  kMinutes,
  kHours,
  kDays,
  kWeeks,

  // Assembly
  kAssembly,
  kLet,
  kLeave,
  kSwitch,
  kCase,
  kDefault,

  // Imports
  kImport,
  kFrom,
  kAs,

  // Emit / type
  kEmit,
  kType,
  kUsing,
  kFor2, // 'for' in using…for

  // Pragma
  kPragma,
  kSolidity,

  // ── Operators ─────────────────────────────────────────────────────────────
  // Arithmetic
  Plus,         // +
  Minus,        // -
  Star,         // *
  Slash,        // /
  Percent,      // %
  StarStar,     // **

  // Bitwise
  Ampersand,    // &
  Pipe,         // |
  Caret,        // ^
  Tilde,        // ~
  LtLt,         // <<
  GtGt,         // >>
  GtGtGt,       // >>>

  // Logical
  AmpAmp,       // &&
  PipePipe,     // ||
  Bang,         // !

  // Comparison
  EqEq,         // ==
  BangEq,       // !=
  Lt,           // <
  LtEq,         // <=
  Gt,           // >
  GtEq,         // >=

  // Assignment
  Eq,           // =
  PlusEq,       // +=
  MinusEq,      // -=
  StarEq,       // *=
  SlashEq,      // /=
  PercentEq,    // %=
  AmpEq,        // &=
  PipeEq,       // |=
  CaretEq,      // ^=
  LtLtEq,       // <<=
  GtGtEq,       // >>=
  GtGtGtEq,     // >>>=

  // Increment / decrement
  PlusPlus,     // ++
  MinusMinus,   // --

  // Other
  Arrow,        // =>
  RightArrow,   // ->
  Question,     // ?
  Colon,        // :
  ColonColon,   // ::
  Dot,          // .
  DotDotDot,    // ...

  // ── Delimiters ────────────────────────────────────────────────────────────
  LParen,       // (
  RParen,       // )
  LBracket,     // [
  RBracket,     // ]
  LBrace,       // {
  RBrace,       // }
  Semicolon,    // ;
  Comma,        // ,

  // ── Special ───────────────────────────────────────────────────────────────
  Comment,      // single/multi-line, usually skipped
  Whitespace,   // usually skipped
  Eof,
  Error,        // scan error
}

/// Fast keyword lookup.  Called by the lexer after scanning an identifier.
const Map<String, TokenKind> _keywords = {
  'if': TokenKind.kIf,
  'else': TokenKind.kElse,
  'for': TokenKind.kFor,
  'while': TokenKind.kWhile,
  'do': TokenKind.kDo,
  'break': TokenKind.kBreak,
  'continue': TokenKind.kContinue,
  'return': TokenKind.kReturn,
  'revert': TokenKind.kRevert,
  'contract': TokenKind.kContract,
  'interface': TokenKind.kInterface,
  'library': TokenKind.kLibrary,
  'abstract': TokenKind.kAbstract,
  'is': TokenKind.kIs,
  'function': TokenKind.kFunction,
  'constructor': TokenKind.kConstructor,
  'fallback': TokenKind.kFallback,
  'receive': TokenKind.kReceive,
  'modifier': TokenKind.kModifier,
  'event': TokenKind.kEvent,
  'error': TokenKind.kError,
  'struct': TokenKind.kStruct,
  'enum': TokenKind.kEnum,
  'mapping': TokenKind.kMapping,
  'address': TokenKind.kAddress,
  'bool': TokenKind.kBool,
  'string': TokenKind.kString,
  'bytes': TokenKind.kBytes,
  'int': TokenKind.kInt,
  'uint': TokenKind.kUint,
  'true': TokenKind.TrueLiteral,
  'false': TokenKind.FalseLiteral,
  'public': TokenKind.kPublic,
  'private': TokenKind.kPrivate,
  'internal': TokenKind.kInternal,
  'external': TokenKind.kExternal,
  'pure': TokenKind.kPure,
  'view': TokenKind.kView,
  'payable': TokenKind.kPayable,
  'nonpayable': TokenKind.kNonpayable,
  'storage': TokenKind.kStorage,
  'memory': TokenKind.kMemory,
  'calldata': TokenKind.kCalldata,
  'immutable': TokenKind.kImmutable,
  'constant': TokenKind.kConstant,
  'override': TokenKind.kOverride,
  'virtual': TokenKind.kVirtual,
  'new': TokenKind.kNew,
  'delete': TokenKind.kDelete,
  'this': TokenKind.kThis,
  'super': TokenKind.kSuper,
  'wei': TokenKind.kWei,
  'gwei': TokenKind.kGwei,
  'ether': TokenKind.kEther,
  'seconds': TokenKind.kSeconds,
  'minutes': TokenKind.kMinutes,
  'hours': TokenKind.kHours,
  'days': TokenKind.kDays,
  'weeks': TokenKind.kWeeks,
  'assembly': TokenKind.kAssembly,
  'let': TokenKind.kLet,
  'leave': TokenKind.kLeave,
  'switch': TokenKind.kSwitch,
  'case': TokenKind.kCase,
  'default': TokenKind.kDefault,
  'import': TokenKind.kImport,
  'from': TokenKind.kFrom,
  'as': TokenKind.kAs,
  'emit': TokenKind.kEmit,
  'type': TokenKind.kType,
  'using': TokenKind.kUsing,
  'pragma': TokenKind.kPragma,
  'solidity': TokenKind.kSolidity,
};

/// Returns the keyword kind for [text], or [TokenKind.Identifier].
/// Handles `intN`, `uintN`, `bytesN` variants.
TokenKind keywordOrIdentifier(String text) {
  final kw = _keywords[text];
  if (kw != null) return kw;

  // uint8…uint256
  if (text.startsWith('uint')) {
    final n = int.tryParse(text.substring(4));
    if (n != null && n >= 8 && n <= 256 && n % 8 == 0) return TokenKind.UintN;
  }
  // int8…int256
  if (text.startsWith('int')) {
    final n = int.tryParse(text.substring(3));
    if (n != null && n >= 8 && n <= 256 && n % 8 == 0) return TokenKind.IntN;
  }
  // bytes1…bytes32
  if (text.startsWith('bytes')) {
    final n = int.tryParse(text.substring(5));
    if (n != null && n >= 1 && n <= 32) return TokenKind.BytesN;
  }

  return TokenKind.Identifier;
}
