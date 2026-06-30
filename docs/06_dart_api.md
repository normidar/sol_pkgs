# 06 Dart API 用法

CLI 不满足需求时，可直接使用各包的 Dart API 编写自定义脚本或集成到应用中。

## 编译（sol_driver）

```dart
import 'dart:io';
import 'package:sol_driver/sol_driver.dart';

final source = File('MyContract.sol').readAsStringSync();

final compilation = (CompilerStack()
  ..addSource('MyContract.sol', source))
  .compile();

if (!compilation.success) {
  for (final d in compilation.diagnostics) print(d);
  return;
}

final contract = compilation.contracts['MyContract']!;
print('ABI: ${contract.abi}');
print('Bytecode: ${contract.bytecodeHex}');
```

`compilation.contracts` 的键是合约名，不是文件名。

## 部署（sol_web3）

```dart
import 'package:sol_web3/sol_web3.dart';

final credentials = EthPrivateKey.fromHex('0x...');
final client = EthereumClient(Uri.parse('http://127.0.0.1:8545'));

try {
  final result = await ContractDeployer(client).deploy(
    credentials: credentials,
    bytecode: contract.bytecode,
  );
  print('合约地址: ${result.contractAddress.toChecksumHex()}');
  print('交易哈希: ${result.transactionHash}');
  print('Gas 消耗: ${result.receipt.gasUsed}');
} on DeploymentException catch (e) {
  print('部署失败: $e');
} finally {
  client.close();
}
```

## 完整编译 + 部署示例

项目内有可直接运行的示例文件：

```
packages/sol_web3/example/full_pipeline_example.dart
```

运行方式：

```sh
# 使用本地测试链（anvil / hardhat node 默认监听 8545）
dart run packages/sol_web3/example/full_pipeline_example.dart

# 自定义节点和私钥
RPC_URL=http://127.0.0.1:8545 PRIVATE_KEY=0x... \
  dart run packages/sol_web3/example/full_pipeline_example.dart
```

## 包结构速查

| 包 | 职责 |
|----|------|
| `sol_lexer` | 词法分析，生成 Token 流 |
| `sol_parser` | 语法分析，生成 AST |
| `sol_sema` | 语义分析、类型检查 |
| `sol_codegen` | IR 代码生成（Yul） |
| `sol_yul` | Yul 打印与 EVM 字节码生成 |
| `sol_abi` | ABI JSON 生成、编码/解码、函数选择器 |
| `sol_types` | Solidity 类型系统 |
| `sol_driver` | 编译流程编排（等价于 solc 的 CompilerStack） |
| `sol_web3` | JSON-RPC 客户端、签名、交易、部署 |
| `sol_cli` | 命令行界面 |
