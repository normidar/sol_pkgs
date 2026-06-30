/// Pure-Dart Ethereum JSON-RPC client, transaction signing, and contract
/// deployment — the "last mile" that turns compiled EVM bytecode (e.g. from
/// `sol_driver`) into a transaction confirmed on a real chain.
///
/// No solc, no web3.js, no Node.js: secp256k1, ECDSA, RLP, and the JSON-RPC
/// transport are all hand-rolled in Dart, matching the rest of `sol_pkgs`.
library;

export 'src/codec.dart';
export 'src/crypto/ecdsa.dart';
export 'src/crypto/eth_private_key.dart';
export 'src/crypto/secp256k1.dart';
export 'src/deployer.dart';
export 'src/eth_address.dart';
export 'src/eth_client.dart';
export 'src/event_log_decoder.dart';
export 'src/json_rpc_client.dart';
export 'src/json_rpc_transport.dart';
export 'src/rlp.dart';
export 'src/transaction.dart';
export 'src/websocket_json_rpc_client.dart';
