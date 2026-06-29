# 将智能合约部署到链上

使用 `sol_driver` 编译 `.sol` 文件，再用 `sol_web3` 将字节码部署到 EVM 链。

## 完整流程

### 第一步：编译 `.sol` 文件

```dart
import 'dart:io';
import 'package:sol_driver/sol_driver.dart';

final source = File('MyContract.sol').readAsStringSync();

final compilation = (CompilerStack()
  ..addSource('MyContract.sol', source))
  .compile();

// 检查编译错误
if (!compilation.success) {
  for (final d in compilation.diagnostics) print(d);
  return;
}

final contract = compilation.contracts['MyContract']!;
final bytecode = contract.bytecode; // Uint8List，用于部署
print('ABI: ${contract.abi}');
```

### 第二步：部署到链上

```dart
import 'package:sol_web3/sol_web3.dart';

final credentials = EthPrivateKey.fromHex('0x你的私钥');
final client = EthereumClient(Uri.parse('http://127.0.0.1:8545')); // 替换为你的 RPC 节点

try {
  final result = await ContractDeployer(client).deploy(
    credentials: credentials,
    bytecode: bytecode, // 上一步的编译结果
  );

  print('合约地址: ${result.contractAddress.toChecksumHex()}');
  print('交易哈希: ${result.transactionHash}');
} on DeploymentException catch (e) {
  print('部署失败: $e');
} finally {
  client.close();
}
```

## 使用 CLI 部署

安装 `sol_cli` 后可以直接用命令行完成编译+部署，无需写 Dart 代码：

```sh
# 安装（monorepo 根目录执行一次）
dart pub global activate --source path packages/sol_cli
```

```sh
# 部署单合约文件（RPC 默认 http://127.0.0.1:8545）
solc --deploy MyContract.sol --private-key 0x...

# 用环境变量传递敏感参数（推荐）
RPC_URL=http://127.0.0.1:8545 PRIVATE_KEY=0x... solc --deploy MyContract.sol

# 文件中有多个合约时，用 --contract 指定
solc --deploy MyContract.sol --contract MyToken --private-key 0x...

# 同时输出 ABI 再部署
solc --abi --deploy MyContract.sol --private-key 0x...
```

参数优先级：命令行 > 环境变量 > 默认值。

| 参数 | 环境变量 | 默认值 |
|------|----------|--------|
| `--rpc-url` | `RPC_URL` | `http://127.0.0.1:8545` |
| `--private-key` | `PRIVATE_KEY` | 无（必填） |

---

### 完整示例（Dart API）

可以直接参考项目内的可运行示例：

```
packages/sol_web3/example/full_pipeline_example.dart
```

用法：

```sh
# 指向本地测试链（anvil 或 hardhat node 默认监听此地址）
dart run packages/sol_web3/example/full_pipeline_example.dart

# 自定义 RPC 和私钥
RPC_URL=http://127.0.0.1:8545 PRIVATE_KEY=0x... dart run packages/sol_web3/example/full_pipeline_example.dart
```

## 注意事项

| 事项 | 说明 |
|------|------|
| **本地测试链** | 推荐先用 `anvil`（Foundry）或 `npx hardhat node` 在 `http://127.0.0.1:8545` 本地测试 |
| **私钥安全** | 用环境变量传递，不要写死在代码里 |
| **secp256k1 安全警告** | 此实现未经过侧信道攻击加固，不建议用于管理真实资产 |
| **未实现功能** | 不支持 `eth_getLogs`、事件日志解码、WebSocket 订阅 |
| **构造函数参数** | 带构造函数参数的合约需自己 ABI 编码后追加到 bytecode |
| **合约名称** | `compilation.contracts['MyContract']` 中的键是合约名，不是文件名 |
