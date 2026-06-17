// ignore_for_file: constant_identifier_names
enum TokenKind {
  // ── Literals ──────────────────────────────────────────────────────────────
  NumberLiteral,
  StringLiteral,
  UnicodeStringLiteral,
  HexStringLiteral,
  TrueLiteral,
  FalseLiteral,

  // ── Identifiers ────────────────────────────────────────────────────────────
  Identifier,

  // ── Control flow ───────────────────────────────────────────────────────────
  kIf,
  kElse,
  kFor,
  kWhile,
  kDo,
  kBreak,
  kContinue,
  kReturn,
  kRevert,
  kTry,
  kCatch,

  // ── Contract structure ─────────────────────────────────────────────────────
  kContract,
  kInterface,
  kLibrary,
  kAbstract,
  kIs,

  // ── Member kinds ───────────────────────────────────────────────────────────
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
  kReturns,   // ← was missing

  // ── Elementary types ───────────────────────────────────────────────────────
  kAddress,
  kBool,
  kString,
  kBytes,
  kInt,
  kUint,
  /// `intN`  — [Token.intWidth] carries the bit width (8..256).
  IntN,
  /// `uintN` — [Token.intWidth] carries the bit width (8..256).
  UintN,
  /// `bytesN` — [Token.intWidth] carries the byte count (1..32).
  BytesN,

  // ── Storage / visibility ────────────────────────────────────────────────────
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

  // ── Special values ─────────────────────────────────────────────────────────
  kNew,
  kDelete,
  kThis,
  kSuper,

  // ── Ether / time units ─────────────────────────────────────────────────────
  kWei,
  kGwei,
  kEther,
  kSeconds,
  kMinutes,
  kHours,
  kDays,
  kWeeks,

  // ── Inline assembly / Yul ──────────────────────────────────────────────────
  kAssembly,
  kLet,
  kLeave,
  kSwitch,
  kCase,
  kDefault,

  // ── Arithmetic safety ──────────────────────────────────────────────────────
  kUnchecked,

  // ── Import ─────────────────────────────────────────────────────────────────
  kImport,
  kFrom,
  kAs,

  // ── Misc declarations ──────────────────────────────────────────────────────
  kEmit,
  kType,
  kUsing,
  kPragma,
  kSolidity,

  // ── Event parameter modifier ───────────────────────────────────────────────
  kIndexed,
  kAnonymous,

  // ── Operators ─────────────────────────────────────────────────────────────
  Plus,         // +
  Minus,        // -
  Star,         // *
  Slash,        // /
  Percent,      // %
  StarStar,     // **

  Ampersand,    // &
  Pipe,         // |
  Caret,        // ^
  Tilde,        // ~
  LtLt,         // <<
  GtGt,         // >>
  GtGtGt,       // >>>

  AmpAmp,       // &&
  PipePipe,     // ||
  Bang,         // !

  EqEq,         // ==
  BangEq,       // !=
  Lt,           // <
  LtEq,         // <=
  Gt,           // >
  GtEq,         // >=

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

  PlusPlus,     // ++
  MinusMinus,   // --

  Arrow,        // =>
  RightArrow,   // ->
  Question,     // ?
  Colon,        // :
  ColonColon,   // ::
  Dot,          // .
  DotDotDot,    // ...

  // ── Delimiters ─────────────────────────────────────────────────────────────
  LParen,       // (
  RParen,       // )
  LBracket,     // [
  RBracket,     // ]
  LBrace,       // {
  RBrace,       // }
  Semicolon,    // ;
  Comma,        // ,

  // ── Trivia & special ───────────────────────────────────────────────────────
  NatSpecLine,   // /// …
  NatSpecBlock,  // /** … */
  Comment,       // // … or /* … */
  Whitespace,
  Eof,
  Error,
}

const Map<String, TokenKind> _keywords = {
  'if': TokenKind.kIf,
  'else': TokenKind.kElse,
  'for': TokenKind.kFor,
  'while': TokenKind.kWhile,
  'do': TokenKind.kDo,
  'break': TokenKind.kBreak,
  'continue': TokenKind.kContinue,
  'return': TokenKind.kReturn,
  'returns': TokenKind.kReturns,
  'revert': TokenKind.kRevert,
  'try': TokenKind.kTry,
  'catch': TokenKind.kCatch,
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
  'unchecked': TokenKind.kUnchecked,
  'import': TokenKind.kImport,
  'from': TokenKind.kFrom,
  'as': TokenKind.kAs,
  'emit': TokenKind.kEmit,
  'type': TokenKind.kType,
  'using': TokenKind.kUsing,
  'pragma': TokenKind.kPragma,
  'solidity': TokenKind.kSolidity,
  'indexed': TokenKind.kIndexed,
  'anonymous': TokenKind.kAnonymous,
};

/// Returns the keyword [TokenKind] for [text], or [TokenKind.Identifier].
///
/// Handles the sized variants `intN`, `uintN`, `bytesN`.
TokenKind keywordOrIdentifier(String text) {
  final kw = _keywords[text];
  if (kw != null) return kw;

  if (text.startsWith('uint') && text.length > 4) {
    final n = int.tryParse(text.substring(4));
    if (n != null && n >= 8 && n <= 256 && n % 8 == 0) return TokenKind.UintN;
  }
  if (text.startsWith('int') && text.length > 3) {
    final n = int.tryParse(text.substring(3));
    if (n != null && n >= 8 && n <= 256 && n % 8 == 0) return TokenKind.IntN;
  }
  if (text.startsWith('bytes') && text.length > 5) {
    final n = int.tryParse(text.substring(5));
    if (n != null && n >= 1 && n <= 32) return TokenKind.BytesN;
  }

  return TokenKind.Identifier;
}
