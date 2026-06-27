import 'dart:typed_data';
import 'package:sol_support/sol_support.dart';
import 'opcode.dart';

/// A single instruction in the assembly buffer.
sealed class Instruction {
  Instruction({this.location});

  /// Source range this instruction was lowered from. Used to build source
  /// maps; `null` for synthetic instructions (label dispatch, helpers).
  SourceLocation? location;
}

class SimpleInstruction extends Instruction {
  SimpleInstruction(this.opcode, {super.location});
  final Opcode opcode;
}

class PushInstruction extends Instruction {
  PushInstruction(this.data, {super.location});
  final Uint8List data; // 1–32 bytes
}

class LabelInstruction extends Instruction {
  LabelInstruction(this.name, {super.location});
  final String name;
}

class JumpInstruction extends Instruction {
  JumpInstruction(this.label, {this.conditional = false, super.location});
  final String label;
  final bool conditional;
}

/// Pushes the byte-offset of [name] as a PUSH2 value (for return addresses).
class PushLabelInstruction extends Instruction {
  PushLabelInstruction(this.name, {super.location});
  final String name;
}

/// Pushes the byte-offset at which the appended deployed (runtime) code begins.
///
/// Resolves to the total length of the creation code, since the runtime code is
/// concatenated immediately after it. Used to lower Yul's `dataoffset(...)`.
class PushDeployedOffsetInstruction extends Instruction {
  PushDeployedOffsetInstruction({super.location});
}

/// A single entry in a generated source map.
///
/// Each entry corresponds to one EVM instruction (1+ bytes) and points at the
/// Solidity source range that lowered to it.
class SourceMapEntry {
  const SourceMapEntry({
    required this.start,
    required this.length,
    required this.fileIndex,
  });

  /// Byte offset of the source range start; `-1` when unknown.
  final int start;

  /// Length of the source range in bytes; `-1` when unknown.
  final int length;

  /// Index of the source file the range lives in; `-1` when unknown.
  final int fileIndex;

  static const unknown = SourceMapEntry(start: -1, length: -1, fileIndex: -1);
}

/// Bytecode + source map produced by [Assembler.assembleWithSourceMap].
class AssembledOutput {
  AssembledOutput(this.bytecode, this.sourceMap);

  final Uint8List bytecode;

  /// One entry per assembled instruction, in emission order.
  final List<SourceMapEntry> sourceMap;
}

/// Linear assembler that resolves labels in two passes and produces bytecode.
class Assembler {
  final List<Instruction> _instructions = [];

  /// Source location attached to every instruction emitted while non-null.
  /// Use [withLocation] to scope it.
  SourceLocation? currentLocation;

  /// Runs [body] with [currentLocation] set to [location], restoring the
  /// previous value afterwards.
  T withLocation<T>(SourceLocation? location, T Function() body) {
    final prev = currentLocation;
    currentLocation = location;
    try {
      return body();
    } finally {
      currentLocation = prev;
    }
  }

  // ── Emit helpers ──────────────────────────────────────────────────────────

  void emit(Opcode op) =>
      _instructions.add(SimpleInstruction(op, location: currentLocation));

  void push(BigInt value) {
    if (value == BigInt.zero) {
      _instructions.add(
        SimpleInstruction(Opcode.PUSH0, location: currentLocation),
      );
      return;
    }
    final bytes = _bigIntToBytes(value);
    _instructions.add(PushInstruction(bytes, location: currentLocation));
  }

  void push1(int value) => push(BigInt.from(value));

  void label(String name) =>
      _instructions.add(LabelInstruction(name, location: currentLocation));

  void jump(String target) =>
      _instructions.add(JumpInstruction(target, location: currentLocation));

  void jumpi(String target) => _instructions.add(
    JumpInstruction(target, conditional: true, location: currentLocation),
  );

  /// Pushes the byte offset of [name] onto the stack (for use as a return address).
  void pushLabel(String name) =>
      _instructions.add(PushLabelInstruction(name, location: currentLocation));

  /// Pushes the offset where the appended runtime code begins
  /// (= total creation-code length). Lowers Yul's `dataoffset(...)`.
  void pushDeployedOffset() => _instructions.add(
    PushDeployedOffsetInstruction(location: currentLocation),
  );

  // Convenience wrappers for common sequences
  void add() => emit(Opcode.ADD);
  void sub() => emit(Opcode.SUB);
  void mul() => emit(Opcode.MUL);
  void div() => emit(Opcode.DIV);
  void ret() => emit(Opcode.RETURN);
  void revert() => emit(Opcode.REVERT);
  void pop() => emit(Opcode.POP);
  void dup(int n) {
    assert(n >= 1 && n <= 16);
    emit(Opcode.values.firstWhere((op) => op.name == 'DUP$n'));
  }

  void swap(int n) {
    assert(n >= 1 && n <= 16);
    emit(Opcode.values.firstWhere((op) => op.name == 'SWAP$n'));
  }

  // ── Assemble ──────────────────────────────────────────────────────────────

  /// Two-pass assembly that also produces a per-instruction source map.
  AssembledOutput assembleWithSourceMap() {
    final code = assemble();
    final map = <SourceMapEntry>[];
    for (final instr in _instructions) {
      final loc = instr.location;
      map.add(
        loc == null
            ? SourceMapEntry.unknown
            : SourceMapEntry(
                start: loc.offset,
                length: loc.length,
                fileIndex: loc.sourceIndex,
              ),
      );
    }
    return AssembledOutput(code, map);
  }

  /// Two-pass assembly: first compute offsets, then emit bytes.
  Uint8List assemble() {
    // Pass 1: compute label offsets (jumps use a fixed 2-byte PUSH2 operand).
    final labelOffsets = <String, int>{};
    int offset = 0;
    for (final instr in _instructions) {
      switch (instr) {
        case LabelInstruction(:final name):
          // The label resolves to the JUMPDEST byte emitted at this position.
          labelOffsets[name] = offset;
          offset += 1; // JUMPDEST byte (emitted in pass 2)
        case SimpleInstruction(:final opcode):
          offset += opcode.totalBytes;
        case PushInstruction(:final data):
          offset += 1 + data.length; // PUSHn + n bytes
        case JumpInstruction():
          offset += 4; // PUSH2 + 2 target bytes + JUMP/JUMPI
        case PushLabelInstruction():
          offset += 3; // PUSH2 label-offset
        case PushDeployedOffsetInstruction():
          offset += 3; // PUSH2 deployed-offset
      }
    }

    // After pass 1 the running offset equals the total creation-code length,
    // which is exactly where the appended runtime code will begin.
    final deployedOffset = offset;

    // Pass 2: emit bytes.
    final out = BytesBuilder();
    for (final instr in _instructions) {
      switch (instr) {
        case LabelInstruction():
          out.addByte(Opcode.JUMPDEST.byte);
        case SimpleInstruction(:final opcode):
          out.addByte(opcode.byte);
        // immediateBytes are emitted separately by PushInstruction
        case PushInstruction(:final data):
          final pushOp = Opcode.pushForSize(data.length);
          out.addByte(pushOp.byte);
          out.add(data);
        case JumpInstruction(:final label, :final conditional):
          final target = labelOffsets[label] ?? 0;
          out.addByte(Opcode.PUSH2.byte);
          out.addByte((target >> 8) & 0xFF);
          out.addByte(target & 0xFF);
          out.addByte(conditional ? Opcode.JUMPI.byte : Opcode.JUMP.byte);
        case PushLabelInstruction(:final name):
          final target = labelOffsets[name] ?? 0;
          out.addByte(Opcode.PUSH2.byte);
          out.addByte((target >> 8) & 0xFF);
          out.addByte(target & 0xFF);
        case PushDeployedOffsetInstruction():
          out.addByte(Opcode.PUSH2.byte);
          out.addByte((deployedOffset >> 8) & 0xFF);
          out.addByte(deployedOffset & 0xFF);
      }
    }
    return out.toBytes();
  }

  static Uint8List _bigIntToBytes(BigInt value) {
    if (value == BigInt.zero) return Uint8List(1);
    final hex = value.toRadixString(16).padLeft(2, '0');
    final padded = hex.length.isOdd ? '0$hex' : hex;
    final bytes = Uint8List(padded.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(padded.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }
}
