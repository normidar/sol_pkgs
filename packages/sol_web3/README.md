# sol_web3

The "last mile" of the `sol_pkgs` Solidity compiler: a pure-Dart Ethereum
JSON-RPC client, transaction signer, and contract deployer. It takes the
bytecode `sol_driver` compiles and gets it onto an actual EVM chain — no
`solc`, no `web3.js`, no Node.js, and no third-party crypto packages. The
only `sol_pkgs` dependency is `sol_support`, used for its pure-Dart
`keccak256`.

## Pipeline

```
EthPrivateKey                 secp256k1 keypair + Ethereum address (EIP-55)
    │
    ▼ EthereumTransaction.sign()
RLP-encoded, signed transaction   (legacy/EIP-155 or EIP-1559)
    │
    ▼ EthereumClient.sendRawTransaction()
JsonRpcClient                 JSON-RPC 2.0 over dart:io HttpClient
    │
    ▼ ContractDeployer.deploy()
nonce/fee lookup → gas estimate (+20%) → sign → send → poll for receipt
```

## What's implemented

- **secp256k1**: affine point addition/doubling/scalar multiplication
  (`ECPoint`).
- **ECDSA**: signing with a CSPRNG nonce and low-`s` normalization (EIP-2),
  public-key/address recovery from a signature (`signEcdsa`,
  `recoverPublicKey`, `recoverEthAddress`).
- **Keys & addresses**: `EthPrivateKey` (range-checked, `createRandom()`),
  `EthAddress` (EIP-55 mixed-case checksums).
- **RLP**: encode/decode for both the short and long string/list forms
  (`rlpEncode`, `rlpDecode`, `rlpUint`).
- **Transactions**: `EthereumTransaction` for legacy (EIP-155 replay
  protection) and EIP-1559 (dynamic fee, `0x02`-typed) transactions, signing
  hash construction, and signed encoding.
- **JSON-RPC**: a minimal `JsonRpcClient` (no `package:http`), and a typed
  `EthereumClient` wrapping `eth_chainId`, `eth_getTransactionCount`,
  `eth_gasPrice`, `eth_maxPriorityFeePerGas`, `eth_estimateGas`,
  `eth_getBalance`, `eth_sendRawTransaction`, `eth_getTransactionReceipt`.
- **Deployment**: `ContractDeployer.deploy()` orchestrates nonce/fee
  lookup, gas estimation, signing, broadcast, and receipt polling, throwing
  `DeploymentException` on revert or timeout. `computeCreateAddress`
  derives the `CREATE` address independently as a fallback.

Not implemented: `CREATE2` address computation, `eth_getLogs` /
event-log decoding, WebSocket subscriptions (`eth_subscribe` — HTTP
request/response only). RFC 6979 deterministic nonces were a deliberate
omission in favor of a CSPRNG, to avoid pulling in an HMAC/SHA-256
implementation for a property (deterministic signatures) this library
doesn't need.

## Usage

```dart
import 'package:sol_web3/sol_web3.dart';

void main() async {
  final credentials = EthPrivateKey.fromHex('0x...');
  final client = EthereumClient(Uri.parse('http://127.0.0.1:8545'));

  final result = await ContractDeployer(client).deploy(
    credentials: credentials,
    bytecode: compiledInitCode, // from sol_driver's CompilationResult
  );

  print('deployed at ${result.contractAddress.toChecksumHex()}');
  print('tx hash: ${result.transactionHash}');
  client.close();
}
```

See [`example/full_pipeline_example.dart`](example/full_pipeline_example.dart)
for a complete compile-then-deploy example, and
[`test/deploy_loopback_test.dart`](test/deploy_loopback_test.dart) for an
end-to-end test that runs the entire signing/RLP/JSON-RPC path against a
local `dart:io HttpServer` standing in for a real node.

## Security notes

- The secp256k1/ECDSA implementation is a from-scratch reference
  implementation, written for correctness rather than constant-time
  resistance to timing side channels. Don't use it to manage keys
  guarding real assets — use an audited library (e.g. libsecp256k1)
  for that.
- Nothing in this package has been exercised against a real testnet or
  mainnet node; `test/deploy_loopback_test.dart`'s local-loopback
  simulation is the extent of this repository's own verification.
  Broadcasting to a real network is the integrating application's
  responsibility.

## Dependencies

`sol_support` (runtime). `sol_driver` is a dev-dependency only, used by
the example and by `test/deploy_loopback_test.dart` to produce real
bytecode to deploy.
