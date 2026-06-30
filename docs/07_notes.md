# 07 注意事项

## 本地测试链

建议先在本地测试链上验证，再部署到公共网络。推荐工具：

- **Anvil**（Foundry）：`anvil`
- **Hardhat Node**：`npx hardhat node`

两者默认监听 `http://127.0.0.1:8545`，并提供若干预充值账户。

## 私钥安全

- 始终通过环境变量（`PRIVATE_KEY`）传递，不要写死在代码或 shell 历史中
- 本文档示例中出现的私钥（`0xac0974b...`）是 Anvil/Hardhat 的公开测试账户，仅供本地测试使用

## secp256k1 / ECDSA 实现说明

`sol_web3` 中的 secp256k1 和 ECDSA 实现已采取以下安全措施：

- **Montgomery ladder 标量乘法**：每个比特位均执行相同数量的椭圆曲线运算（一次倍点 + 一次加点），消除了 double-and-add 算法因数据驱动的分支导致的简单时序泄漏。
- **RFC 6979 确定性 nonce**：签名 nonce `k` 通过 HMAC-SHA-256 从私钥和消息哈希确定性派生，完全消除了随机 nonce 重用（ECDSA 最危险的失败模式）的可能性，且不依赖 CSPRNG 质量。

**残余限制**：Dart VM 的 `BigInt` 运算在机器字级别不保证恒定时间（运行时大数库内部仍可能存在缓存/分支时序差异）。上述措施显著提高了安全门槛，但纯 Dart 实现无法替代经过硬件级加固的库（如 libsecp256k1）。对于极高安全要求的主网生产环境，建议通过 `dart:ffi` 绑定 libsecp256k1。

## 已知限制

| 功能 | 状态 |
|------|------|
| 带构造函数参数的合约部署 | 需自行 ABI 编码后拼接到 bytecode 末尾 |
| `eth_getLogs` / 事件日志解码 | 未实现 |
| `CREATE2` 地址计算 | 未实现 |
| WebSocket 订阅（`eth_subscribe`） | 未实现 |

## deployments.json 的作用范围

`--deploy`、`--info`、`--call` 均读写**命令执行时的当前目录**下的 `deployments.json`。在不同目录下操作同名合约时，记录是相互独立的。
