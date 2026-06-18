/// Pure-Dart Keccak-256 (the variant used by Ethereum / Solidity).
///
/// This is the original Keccak submission with the `0x01` domain-separation
/// suffix — **not** NIST SHA3-256 (which uses `0x06`). Solidity's `keccak256`
/// built-in and the 4-byte function/event/error selectors are computed with
/// this function.
///
/// Implementation follows the compact reference of Keccak-f[1600] operating on
/// 25 little-endian 64-bit lanes. Runs on the Dart VM, where `int` is a 64-bit
/// two's-complement value and shifts wrap modulo 2^64.
library;

import 'dart:typed_data';

/// Computes the Keccak-256 digest of [input] and returns 32 bytes.
Uint8List keccak256(List<int> input) =>
    _keccak(136, Uint8List.fromList(input), 0x01, 32);

/// Computes Keccak-256 of the UTF-8/Latin-1 code units of [s].
///
/// ABI signatures only contain ASCII, so the code units coincide with UTF-8.
Uint8List keccak256OfString(String s) => keccak256(_asciiBytes(s));

/// Returns the lowercase hex (no `0x` prefix) of `keccak256(input)`.
String keccak256Hex(List<int> input) => _toHex(keccak256(input));

/// Returns the lowercase hex (no `0x` prefix) of `keccak256` of [s].
String keccak256HexOfString(String s) => _toHex(keccak256OfString(s));

// ── Sponge ────────────────────────────────────────────────────────────────────

Uint8List _keccak(int rateBytes, Uint8List input, int delimiter, int outBytes) {
  final st = List<int>.filled(25, 0);

  // Absorb.
  var offset = 0;
  var remaining = input.length;
  var blockSize = 0;
  while (remaining > 0) {
    blockSize = remaining < rateBytes ? remaining : rateBytes;
    for (var i = 0; i < blockSize; i++) {
      st[i >> 3] ^= (input[offset + i] & 0xff) << (8 * (i & 7));
    }
    offset += blockSize;
    remaining -= blockSize;
    if (blockSize == rateBytes) {
      _keccakF1600(st);
      blockSize = 0;
    }
  }

  // Pad (multi-rate padding 10*1 with the Keccak domain suffix).
  st[blockSize >> 3] ^= delimiter << (8 * (blockSize & 7));
  st[(rateBytes - 1) >> 3] ^= 0x80 << (8 * ((rateBytes - 1) & 7));
  _keccakF1600(st);

  // Squeeze (single block suffices for a 32-byte digest at rate 136).
  final out = Uint8List(outBytes);
  var produced = 0;
  while (produced < outBytes) {
    blockSize = (outBytes - produced) < rateBytes
        ? (outBytes - produced)
        : rateBytes;
    for (var i = 0; i < blockSize; i++) {
      out[produced + i] = (st[i >> 3] >>> (8 * (i & 7))) & 0xff;
    }
    produced += blockSize;
    if (produced < outBytes) _keccakF1600(st);
  }
  return out;
}

// ── Keccak-f[1600] permutation ──────────────────────────────────────────────

const List<int> _roundConstants = [
  0x0000000000000001, 0x0000000000008082, 0x800000000000808a,
  0x8000000080008000, 0x000000000000808b, 0x0000000080000001,
  0x8000000080008081, 0x8000000000008009, 0x000000000000008a,
  0x0000000000000088, 0x0000000080008009, 0x000000008000000a,
  0x000000008000808b, 0x800000000000008b, 0x8000000000008089,
  0x8000000000008003, 0x8000000000008002, 0x8000000000000080,
  0x000000000000800a, 0x800000008000000a, 0x8000000080008081,
  0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
];

const List<int> _rotationOffsets = [
  1, 3, 6, 10, 15, 21, 28, 36, 45, 55, 2, 14, //
  27, 41, 56, 8, 25, 43, 62, 18, 39, 61, 20, 44,
];

const List<int> _piLane = [
  10, 7, 11, 17, 18, 3, 5, 16, 8, 21, 24, 4, //
  15, 23, 19, 13, 12, 2, 20, 14, 22, 9, 6, 1,
];

void _keccakF1600(List<int> st) {
  final bc = List<int>.filled(5, 0);
  for (var round = 0; round < 24; round++) {
    // Theta.
    for (var i = 0; i < 5; i++) {
      bc[i] = st[i] ^ st[i + 5] ^ st[i + 10] ^ st[i + 15] ^ st[i + 20];
    }
    for (var i = 0; i < 5; i++) {
      final t = bc[(i + 4) % 5] ^ _rotl64(bc[(i + 1) % 5], 1);
      for (var j = 0; j < 25; j += 5) {
        st[j + i] ^= t;
      }
    }

    // Rho and Pi.
    var t = st[1];
    for (var i = 0; i < 24; i++) {
      final j = _piLane[i];
      final tmp = st[j];
      st[j] = _rotl64(t, _rotationOffsets[i]);
      t = tmp;
    }

    // Chi.
    for (var j = 0; j < 25; j += 5) {
      for (var i = 0; i < 5; i++) {
        bc[i] = st[j + i];
      }
      for (var i = 0; i < 5; i++) {
        st[j + i] ^= (~bc[(i + 1) % 5]) & bc[(i + 2) % 5];
      }
    }

    // Iota.
    st[0] ^= _roundConstants[round];
  }
}

int _rotl64(int x, int n) {
  if (n == 0) return x;
  return (x << n) | (x >>> (64 - n));
}

// ── Helpers ──────────────────────────────────────────────────────────────────

List<int> _asciiBytes(String s) {
  final out = Uint8List(s.length);
  for (var i = 0; i < s.length; i++) {
    out[i] = s.codeUnitAt(i) & 0xff;
  }
  return out;
}

String _toHex(Uint8List bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}
