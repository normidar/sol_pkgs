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
}
