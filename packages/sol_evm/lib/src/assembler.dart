import 'dart:typed_data';
import 'opcode.dart';

/// A single instruction in the assembly buffer.
sealed class Instruction {
  const Instruction();
}

class SimpleInstruction extends Instruction {
  const SimpleInstruction(this.opcode);
  final Opcode opcode;
}

class PushInstruction extends Instruction {
  const PushInstruction(this.data);
  final Uint8List data; // 1–32 bytes
}

class LabelInstruction extends Instruction {
  const LabelInstruction(this.name);
  final String name;
}

class JumpInstruction extends Instruction {
  const JumpInstruction(this.label, {this.conditional = false});
  final String label;
  final bool conditional;
}

/// Pushes the byte-offset of [name] as a PUSH2 value (for return addresses).
class PushLabelInstruction extends Instruction {
  const PushLabelInstruction(this.name);
  final String name;
}

/// Pushes the byte-offset at which the appended deployed (runtime) code begins.
///
/// Resolves to the total length of the creation code, since the runtime code is
/// concatenated immediately after it. Used to lower Yul's `dataoffset(...)`.
class PushDeployedOffsetInstruction extends Instruction {
  const PushDeployedOffsetInstruction();
}

/// Linear assembler that resolves labels in two passes and produces bytecode.
class Assembler {
  final List<Instruction> _instructions = [];

  // ── Emit helpers ──────────────────────────────────────────────────────────

  void emit(Opcode op) => _instructions.add(SimpleInstruction(op));

  void push(BigInt value) {
    final bytes = _bigIntToBytes(value);
    _instructions.add(PushInstruction(bytes));
  }

  void push1(int value) => push(BigInt.from(value));

  void label(String name) => _instructions.add(LabelInstruction(name));

  void jump(String target) =>
      _instructions.add(JumpInstruction(target));

  void jumpi(String target) =>
      _instructions.add(JumpInstruction(target, conditional: true));

  /// Pushes the byte offset of [name] onto the stack (for use as a return address).
  void pushLabel(String name) =>
      _instructions.add(PushLabelInstruction(name));

  /// Pushes the offset where the appended runtime code begins
  /// (= total creation-code length). Lowers Yul's `dataoffset(...)`.
  void pushDeployedOffset() =>
      _instructions.add(const PushDeployedOffsetInstruction());

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

  /// Two-pass assembly: first compute offsets, then emit bytes.
  Uint8List assemble() {
    // Pass 1: compute label offsets assuming 3-byte PUSH2 for jumps.
    final labelOffsets = <String, int>{};
    int offset = 0;
    for (final instr in _instructions) {
      switch (instr) {
        case LabelInstruction(:final name):
          labelOffsets[name] = offset;
        case SimpleInstruction(:final opcode):
          offset += opcode.totalBytes;
        case PushInstruction(:final data):
          offset += 1 + data.length; // PUSHn + n bytes
        case JumpInstruction():
          offset += 3; // PUSH2 target + JUMP/JUMPI
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
