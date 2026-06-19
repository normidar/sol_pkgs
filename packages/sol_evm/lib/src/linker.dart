import 'package:sol_support/sol_support.dart';

/// Resolves library address placeholders in (unlinked) bytecode.
///
/// When a contract calls into a `library`, the compiler cannot know the
/// library's deployed address at compile time, so it emits a 20-byte
/// placeholder where a `PUSH20 <address>` operand would go. The placeholder is
/// only filled in once the library has been deployed — this is *linking*.
///
/// This implements the modern (solc ≥ 0.5.0) placeholder scheme:
///
/// ```text
/// __$<34 hex chars>$__
/// ```
///
/// where the 34 hex characters are the first 17 bytes of
/// `keccak256(fullyQualifiedLibraryName)`. The whole token is exactly 40
/// characters long, occupying the position of a 20-byte (40 hex char) address
/// in the hex-encoded bytecode string.
class BytecodeLinker {
  const BytecodeLinker();

  /// Length of a placeholder / address in hex characters (20 bytes).
  static const int _addressHexLen = 40;

  /// Computes the placeholder token for a fully qualified library name such as
  /// `"contracts/Math.sol:SafeMath"` (or a bare `"SafeMath"`).
  static String placeholderFor(String fullyQualifiedName) {
    final hash = keccak256HexOfString(fullyQualifiedName);
    return '__\$${hash.substring(0, 34)}\$__';
  }

  /// Links [hexBytecode] by replacing every library placeholder with the
  /// corresponding deployed address from [addresses] (keyed by fully qualified
  /// library name).
  ///
  /// Each address may be `0x`-prefixed or bare and is left-padded to 20 bytes.
  /// Throws [ArgumentError] for malformed addresses. Placeholders for libraries
  /// not present in [addresses] are left untouched — use [unresolved] to find
  /// them.
  String link(String hexBytecode, Map<String, String> addresses) {
    var out = hexBytecode;
    addresses.forEach((name, address) {
      final placeholder = placeholderFor(name);
      out = out.replaceAll(placeholder, _normaliseAddress(address));
    });
    return out;
  }

  /// Returns true when [hexBytecode] still contains any unresolved
  /// `__$...$__` placeholder.
  bool isLinked(String hexBytecode) => !_placeholder.hasMatch(hexBytecode);

  /// Returns the set of placeholder tokens still present in [hexBytecode].
  Set<String> unresolved(String hexBytecode) =>
      _placeholder.allMatches(hexBytecode).map((m) => m.group(0)!).toSet();

  static final RegExp _placeholder = RegExp(r'__\$[0-9a-fA-F]{34}\$__');

  static String _normaliseAddress(String address) {
    var hex = address.startsWith('0x') || address.startsWith('0X')
        ? address.substring(2)
        : address;
    if (hex.length > _addressHexLen) {
      throw ArgumentError('Address "$address" exceeds 20 bytes');
    }
    if (!RegExp(r'^[0-9a-fA-F]*$').hasMatch(hex)) {
      throw ArgumentError('Address "$address" is not valid hex');
    }
    return hex.padLeft(_addressHexLen, '0').toLowerCase();
  }
}
