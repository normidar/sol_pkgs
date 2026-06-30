# 07 注意事项

## 本地测试链

建议先在本地测试链上验证，再部署到公共网络。推荐工具：

- **Anvil**（Foundry）：`anvil`
- **Hardhat Node**：`npx hardhat node`

两者默认监听 `http://127.0.0.1:8545`，并提供若干预充值账户。

## 私钥安全

- 始终通过环境变量（`PRIVATE_KEY`）传递，不要写死在代码或 shell 历史中
- 本文档示例中出现的私钥（`0xac0974b...`）是 Anvil/Hardhat 的公开测试账户，仅供本地测试使用

## secp256k1 / ECDSA 实现警告

`sol_web3` 中的 secp256k1 和 ECDSA 实现是从零编写的参考实现，**未经过侧信道攻击（timing attack）加固**。不建议用于管理真实主网资产；生产环境请使用经过审计的库（如 libsecp256k1）。

## 已知限制

| 功能 | 状态 |
|------|------|
| 带构造函数参数的合约部署 | 需自行 ABI 编码后拼接到 bytecode 末尾 |
| `eth_getLogs` / 事件日志解码 | 未实现 |
| `CREATE2` 地址计算 | 未实现 |
| WebSocket 订阅（`eth_subscribe`） | 未实现 |

## deployments.json 的作用范围

`--deploy`、`--info`、`--call` 均读写**命令执行时的当前目录**下的 `deployments.json`。在不同目录下操作同名合约时，记录是相互独立的。
