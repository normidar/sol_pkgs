# 04 查看部署信息

从当前目录的 `deployments.json` 中读取并展示指定合约的部署记录。

## 用法

```sh
solc --info Counter
```

## 输出示例

```
────────────────────────────────────────────────────────────
  Contract : Counter
────────────────────────────────────────────────────────────
  Address  : 0x5FbDB2315678afecb367f032d93F642f64180aa3
  Chain ID : 31337
  Tx hash  : 0xabc123...
  RPC URL  : http://127.0.0.1:8545
  Deployed : 2026-06-30T10:00:00.000Z

  Public functions:
    set(uint256 v)
    get() → uint256  [view]
    value() → uint256  [view]

  Events:
    Transfer(address from, address to, uint256 value)
────────────────────────────────────────────────────────────
```

同一合约名多次部署时，会按顺序依次显示所有记录（标注「Deployment 1 of N」）。
