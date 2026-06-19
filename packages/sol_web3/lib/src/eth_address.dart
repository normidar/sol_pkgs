/// A 20-byte Ethereum address with EIP-55 mixed-case checksum support.
library;

import 'dart:typed_data';

import 'package:sol_support/sol_support.dart';

import 'codec.dart';

class EthAddress {
  EthAddress(this.bytes) {
    if (bytes.length != 20) {
      throw ArgumentError(
        'Ethereum address must be 20 bytes, got ${bytes.length}',
      );
    }
  }

  /// Parses a `0x`-prefixed or bare 40-hex-digit address. Case is ignored on
  /// input (EIP-55 checksum casing, if present, is not verified).
  factory EthAddress.fromHex(String hex) => EthAddress(hexToBytes(hex));

  /// The all-zero address (`0x000...000`), e.g. as a sentinel "no recipient".
  static final EthAddress zero = EthAddress(Uint8List(20));

  final Uint8List bytes;

  /// Lowercase hex with a `0x` prefix.
  String toHex() => bytesToHex(bytes, include0x: true);

  /// EIP-55 mixed-case checksum encoding, e.g. for display or for
  /// `eth_*` JSON-RPC parameters.
  String toChecksumHex() {
    final lower = bytesToHex(bytes);
    final hashHex = keccak256HexOfString(lower);
    final sb = StringBuffer('0x');
    for (var i = 0; i < lower.length; i++) {
      final c = lower[i];
      final isLetter = c.compareTo('a') >= 0 && c.compareTo('f') <= 0;
      sb.write(
        isLetter && int.parse(hashHex[i], radix: 16) >= 8 ? c.toUpperCase() : c,
      );
    }
    return sb.toString();
  }

  @override
  bool operator ==(Object other) =>
      other is EthAddress && toHex() == other.toHex();

  @override
  int get hashCode => toHex().hashCode;

  @override
  String toString() => toChecksumHex();
}
