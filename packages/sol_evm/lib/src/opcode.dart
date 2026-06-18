// ignore_for_file: constant_identifier_names
/// EVM opcode definitions (Shanghai / Cancun baseline).
enum Opcode {
  // ── Stop & arithmetic ─────────────────────────────────────────────────────
  STOP(0x00, 0, 0, gas: 0),
  ADD(0x01, 2, 1, gas: 3),
  MUL(0x02, 2, 1, gas: 5),
  SUB(0x03, 2, 1, gas: 3),
  DIV(0x04, 2, 1, gas: 5),
  SDIV(0x05, 2, 1, gas: 5),
  MOD(0x06, 2, 1, gas: 5),
  SMOD(0x07, 2, 1, gas: 5),
  ADDMOD(0x08, 3, 1, gas: 8),
  MULMOD(0x09, 3, 1, gas: 8),
  EXP(0x0A, 2, 1, gas: 10),
  SIGNEXTEND(0x0B, 2, 1, gas: 5),

  // ── Comparison & bitwise ──────────────────────────────────────────────────
  LT(0x10, 2, 1, gas: 3),
  GT(0x11, 2, 1, gas: 3),
  SLT(0x12, 2, 1, gas: 3),
  SGT(0x13, 2, 1, gas: 3),
  EQ(0x14, 2, 1, gas: 3),
  ISZERO(0x15, 1, 1, gas: 3),
  AND(0x16, 2, 1, gas: 3),
  OR(0x17, 2, 1, gas: 3),
  XOR(0x18, 2, 1, gas: 3),
  NOT(0x19, 1, 1, gas: 3),
  BYTE(0x1A, 2, 1, gas: 3),
  SHL(0x1B, 2, 1, gas: 3),
  SHR(0x1C, 2, 1, gas: 3),
  SAR(0x1D, 2, 1, gas: 3),

  // ── SHA3 ──────────────────────────────────────────────────────────────────
  KECCAK256(0x20, 2, 1, gas: 30),

  // ── Environment ───────────────────────────────────────────────────────────
  ADDRESS(0x30, 0, 1, gas: 2),
  BALANCE(0x31, 1, 1, gas: 100),
  ORIGIN(0x32, 0, 1, gas: 2),
  CALLER(0x33, 0, 1, gas: 2),
  CALLVALUE(0x34, 0, 1, gas: 2),
  CALLDATALOAD(0x35, 1, 1, gas: 3),
  CALLDATASIZE(0x36, 0, 1, gas: 2),
  CALLDATACOPY(0x37, 3, 0, gas: 3),
  CODESIZE(0x38, 0, 1, gas: 2),
  CODECOPY(0x39, 3, 0, gas: 3),
  GASPRICE(0x3A, 0, 1, gas: 2),
  EXTCODESIZE(0x3B, 1, 1, gas: 100),
  EXTCODECOPY(0x3C, 4, 0, gas: 100),
  RETURNDATASIZE(0x3D, 0, 1, gas: 2),
  RETURNDATACOPY(0x3E, 3, 0, gas: 3),
  EXTCODEHASH(0x3F, 1, 1, gas: 100),

  // ── Block ─────────────────────────────────────────────────────────────────
  BLOCKHASH(0x40, 1, 1, gas: 20),
  COINBASE(0x41, 0, 1, gas: 2),
  TIMESTAMP(0x42, 0, 1, gas: 2),
  NUMBER(0x43, 0, 1, gas: 2),
  PREVRANDAO(0x44, 0, 1, gas: 2),
  GASLIMIT(0x45, 0, 1, gas: 2),
  CHAINID(0x46, 0, 1, gas: 2),
  SELFBALANCE(0x47, 0, 1, gas: 5),
  BASEFEE(0x48, 0, 1, gas: 2),
  BLOBHASH(0x49, 1, 1, gas: 3),
  BLOBBASEFEE(0x4A, 0, 1, gas: 2),

  // ── Stack / memory / storage ──────────────────────────────────────────────
  POP(0x50, 1, 0, gas: 2),
  MLOAD(0x51, 1, 1, gas: 3),
  MSTORE(0x52, 2, 0, gas: 3),
  MSTORE8(0x53, 2, 0, gas: 3),
  SLOAD(0x54, 1, 1, gas: 100),
  SSTORE(0x55, 2, 0, gas: 100),
  JUMP(0x56, 1, 0, gas: 8),
  JUMPI(0x57, 2, 0, gas: 10),
  PC(0x58, 0, 1, gas: 2),
  MSIZE(0x59, 0, 1, gas: 2),
  GAS(0x5A, 0, 1, gas: 2),
  JUMPDEST(0x5B, 0, 0, gas: 1),
  TLOAD(0x5C, 1, 1, gas: 100),
  TSTORE(0x5D, 2, 0, gas: 100),
  MCOPY(0x5E, 3, 0, gas: 3),

  // ── Push ──────────────────────────────────────────────────────────────────
  PUSH0(0x5F, 0, 1, gas: 2),
  PUSH1(0x60, 0, 1, gas: 3, immediateBytes: 1),
  PUSH2(0x61, 0, 1, gas: 3, immediateBytes: 2),
  PUSH3(0x62, 0, 1, gas: 3, immediateBytes: 3),
  PUSH4(0x63, 0, 1, gas: 3, immediateBytes: 4),
  PUSH5(0x64, 0, 1, gas: 3, immediateBytes: 5),
  PUSH6(0x65, 0, 1, gas: 3, immediateBytes: 6),
  PUSH7(0x66, 0, 1, gas: 3, immediateBytes: 7),
  PUSH8(0x67, 0, 1, gas: 3, immediateBytes: 8),
  PUSH9(0x68, 0, 1, gas: 3, immediateBytes: 9),
  PUSH10(0x69, 0, 1, gas: 3, immediateBytes: 10),
  PUSH11(0x6A, 0, 1, gas: 3, immediateBytes: 11),
  PUSH12(0x6B, 0, 1, gas: 3, immediateBytes: 12),
  PUSH13(0x6C, 0, 1, gas: 3, immediateBytes: 13),
  PUSH14(0x6D, 0, 1, gas: 3, immediateBytes: 14),
  PUSH15(0x6E, 0, 1, gas: 3, immediateBytes: 15),
  PUSH16(0x6F, 0, 1, gas: 3, immediateBytes: 16),
  PUSH17(0x70, 0, 1, gas: 3, immediateBytes: 17),
  PUSH18(0x71, 0, 1, gas: 3, immediateBytes: 18),
  PUSH19(0x72, 0, 1, gas: 3, immediateBytes: 19),
  PUSH20(0x73, 0, 1, gas: 3, immediateBytes: 20),
  PUSH21(0x74, 0, 1, gas: 3, immediateBytes: 21),
  PUSH22(0x75, 0, 1, gas: 3, immediateBytes: 22),
  PUSH23(0x76, 0, 1, gas: 3, immediateBytes: 23),
  PUSH24(0x77, 0, 1, gas: 3, immediateBytes: 24),
  PUSH25(0x78, 0, 1, gas: 3, immediateBytes: 25),
  PUSH26(0x79, 0, 1, gas: 3, immediateBytes: 26),
  PUSH27(0x7A, 0, 1, gas: 3, immediateBytes: 27),
  PUSH28(0x7B, 0, 1, gas: 3, immediateBytes: 28),
  PUSH29(0x7C, 0, 1, gas: 3, immediateBytes: 29),
  PUSH30(0x7D, 0, 1, gas: 3, immediateBytes: 30),
  PUSH31(0x7E, 0, 1, gas: 3, immediateBytes: 31),
  PUSH32(0x7F, 0, 1, gas: 3, immediateBytes: 32),

  // ── Dup ───────────────────────────────────────────────────────────────────
  DUP1(0x80, 1, 2, gas: 3),
  DUP2(0x81, 2, 3, gas: 3),
  DUP3(0x82, 3, 4, gas: 3),
  DUP4(0x83, 4, 5, gas: 3),
  DUP5(0x84, 5, 6, gas: 3),
  DUP6(0x85, 6, 7, gas: 3),
  DUP7(0x86, 7, 8, gas: 3),
  DUP8(0x87, 8, 9, gas: 3),
  DUP9(0x88, 9, 10, gas: 3),
  DUP10(0x89, 10, 11, gas: 3),
  DUP11(0x8A, 11, 12, gas: 3),
  DUP12(0x8B, 12, 13, gas: 3),
  DUP13(0x8C, 13, 14, gas: 3),
  DUP14(0x8D, 14, 15, gas: 3),
  DUP15(0x8E, 15, 16, gas: 3),
  DUP16(0x8F, 16, 17, gas: 3),

  // ── Swap ──────────────────────────────────────────────────────────────────
  SWAP1(0x90, 2, 2, gas: 3),
  SWAP2(0x91, 3, 3, gas: 3),
  SWAP3(0x92, 4, 4, gas: 3),
  SWAP4(0x93, 5, 5, gas: 3),
  SWAP5(0x94, 6, 6, gas: 3),
  SWAP6(0x95, 7, 7, gas: 3),
  SWAP7(0x96, 8, 8, gas: 3),
  SWAP8(0x97, 9, 9, gas: 3),
  SWAP9(0x98, 10, 10, gas: 3),
  SWAP10(0x99, 11, 11, gas: 3),
  SWAP11(0x9A, 12, 12, gas: 3),
  SWAP12(0x9B, 13, 13, gas: 3),
  SWAP13(0x9C, 14, 14, gas: 3),
  SWAP14(0x9D, 15, 15, gas: 3),
  SWAP15(0x9E, 16, 16, gas: 3),
  SWAP16(0x9F, 17, 17, gas: 3),

  // ── Log ───────────────────────────────────────────────────────────────────
  LOG0(0xA0, 2, 0, gas: 375),
  LOG1(0xA1, 3, 0, gas: 375),
  LOG2(0xA2, 4, 0, gas: 375),
  LOG3(0xA3, 5, 0, gas: 375),
  LOG4(0xA4, 6, 0, gas: 375),

  // ── System ────────────────────────────────────────────────────────────────
  CREATE(0xF0, 3, 1, gas: 32000),
  CALL(0xF1, 7, 1, gas: 100),
  CALLCODE(0xF2, 7, 1, gas: 100),
  RETURN(0xF3, 2, 0, gas: 0),
  DELEGATECALL(0xF4, 6, 1, gas: 100),
  CREATE2(0xF5, 4, 1, gas: 32000),
  STATICCALL(0xFA, 6, 1, gas: 100),
  REVERT(0xFD, 2, 0, gas: 0),
  INVALID(0xFE, 0, 0, gas: 0),
  SELFDESTRUCT(0xFF, 1, 0, gas: 5000);

  const Opcode(
    this.byte,
    this.stackConsumed,
    this.stackProduced, {
    required this.gas,
    this.immediateBytes = 0,
  });

  final int byte;
  final int stackConsumed;
  final int stackProduced;
  final int gas;
  final int immediateBytes;

  int get totalBytes => 1 + immediateBytes;

  static final Map<int, Opcode> _byByte = {
    for (final op in values) op.byte: op,
  };

  static Opcode? fromByte(int b) => _byByte[b];

  /// Returns the appropriate PUSHn opcode for [byteCount] immediate bytes.
  static Opcode pushForSize(int byteCount) {
    assert(byteCount >= 1 && byteCount <= 32);
    return Opcode.values.firstWhere((op) => op.name == 'PUSH$byteCount');
  }
}
