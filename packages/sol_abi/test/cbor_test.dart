import 'dart:typed_data';

import 'package:sol_abi/sol_abi.dart';
import 'package:test/test.dart';

void main() {
  group('encodeCbor', () {
    test('small unsigned ints use a single byte', () {
      expect(encodeCbor(0), Uint8List.fromList([0x00]));
      expect(encodeCbor(23), Uint8List.fromList([0x17]));
    });

    test('uint up to 255 uses 1+1 bytes', () {
      expect(encodeCbor(24), Uint8List.fromList([0x18, 24]));
      expect(encodeCbor(255), Uint8List.fromList([0x18, 0xff]));
    });

    test('uint up to 65535 uses 1+2 bytes', () {
      expect(encodeCbor(256), Uint8List.fromList([0x19, 0x01, 0x00]));
      expect(encodeCbor(0xffff), Uint8List.fromList([0x19, 0xff, 0xff]));
    });

    test('text string', () {
      // "solc" → major 3, length 4, then ASCII.
      expect(
        encodeCbor('solc'),
        Uint8List.fromList([0x64, 0x73, 0x6f, 0x6c, 0x63]),
      );
    });

    test('byte string', () {
      // Three bytes → major 2, length 3, then payload.
      expect(
        encodeCbor(<int>[1, 2, 3]),
        Uint8List.fromList([0x43, 0x01, 0x02, 0x03]),
      );
    });

    test('rejects non-ASCII text', () {
      expect(() => encodeCbor('café'), throwsArgumentError);
    });

    test('rejects negative integers', () {
      expect(() => encodeCbor(-1), throwsArgumentError);
    });

    test('map of two text→bytes entries (solc-style trailer body)', () {
      // {"solc": h'030400', "v": h'01'} → 0xa2 ...
      final out = encodeCbor(<String, Object>{
        'solc': Uint8List.fromList([3, 4, 0]),
        'v': Uint8List.fromList([1]),
      });
      expect(
        out,
        Uint8List.fromList([
          0xa2, // map(2)
          0x64, 0x73, 0x6f, 0x6c, 0x63, // "solc"
          0x43, 0x03, 0x04, 0x00, // bytes(3) 03 04 00
          0x61, 0x76, // "v"
          0x41, 0x01, // bytes(1) 01
        ]),
      );
    });
  });
}
