import 'package:sol_evm/sol_evm.dart';
import 'package:test/test.dart';

void main() {
  group('Opcode table', () {
    test('ADD is opcode 0x01', () {
      expect(Opcode.ADD.byte, 0x01);
    });

    test('PUSH1 has 1 immediate byte', () {
      expect(Opcode.PUSH1.immediateBytes, 1);
    });

    test('fromByte roundtrip', () {
      expect(Opcode.fromByte(0xF3), Opcode.RETURN);
    });

    test('pushForSize(2) == PUSH2', () {
      expect(Opcode.pushForSize(2), Opcode.PUSH2);
    });
  });

  group('Assembler', () {
    test('emits STOP bytecode', () {
      final asm = Assembler()..emit(Opcode.STOP);
      expect(asm.assemble(), [0x00]);
    });

    test('emits PUSH1 0x01 ADD', () {
      final asm = Assembler()
        ..push1(1)
        ..push1(2)
        ..add();
      final bytes = asm.assemble();
      expect(bytes[0], Opcode.PUSH1.byte);
      expect(bytes[1], 1);
      expect(bytes[2], Opcode.PUSH1.byte);
      expect(bytes[3], 2);
      expect(bytes[4], Opcode.ADD.byte);
    });

    test('label/jump resolution', () {
      final asm = Assembler()
        ..jump('target')
        ..emit(Opcode.INVALID)
        ..label('target')
        ..emit(Opcode.STOP);
      final bytes = asm.assemble();
      // Should not throw and should contain JUMPDEST (0x5B)
      expect(bytes.contains(Opcode.JUMPDEST.byte), isTrue);
    });
  });

  group('BytecodeLinker', () {
    const linker = BytecodeLinker();
    const name = 'contracts/Math.sol:SafeMath';

    test('placeholder is the modern 40-char __\$..\$__ token', () {
      final ph = BytecodeLinker.placeholderFor(name);
      expect(ph.length, 40);
      expect(ph.startsWith(r'__$'), isTrue);
      expect(ph.endsWith(r'$__'), isTrue);
      expect(RegExp(r'^__\$[0-9a-f]{34}\$__$').hasMatch(ph), isTrue);
    });

    test('links placeholder to a 20-byte address', () {
      final ph = BytecodeLinker.placeholderFor(name);
      final unlinked =
          '6080$ph'
          '00';
      final linked = linker.link(unlinked, {
        name: '0x1234567890123456789012345678901234567890',
      });
      expect(
        linked,
        '60801234567890123456789012345678901234567890'
        '00',
      );
      expect(linker.isLinked(linked), isTrue);
    });

    test('left-pads a short address to 20 bytes', () {
      final ph = BytecodeLinker.placeholderFor(name);
      final linked = linker.link(ph, {name: '0xabcd'});
      expect(linked, '000000000000000000000000000000000000abcd');
    });

    test('isLinked / unresolved detect leftover placeholders', () {
      final ph = BytecodeLinker.placeholderFor(name);
      expect(linker.isLinked(ph), isFalse);
      expect(linker.unresolved(ph), {ph});
      expect(linker.isLinked('6080'), isTrue);
      expect(linker.unresolved('6080'), isEmpty);
    });

    test('rejects an over-long address', () {
      final ph = BytecodeLinker.placeholderFor(name);
      expect(
        () => linker.link(ph, {name: '0x${'1' * 42}'}),
        throwsArgumentError,
      );
    });
  });
}
