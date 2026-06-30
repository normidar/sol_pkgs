# 03 部署合约

部署成功后，合约地址、ABI、Chain ID 等信息会自动追加写入当前目录的 `deployments.json`，供 `--info` 和 `--call` 命令使用。

## 基本用法

```sh
solc --deploy MyContract.sol --private-key 0x...
```

## 推荐：通过环境变量传递敏感参数

```sh
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
export RPC_URL=http://127.0.0.1:8545

solc --deploy MyContract.sol
```

## 指定 RPC 节点

```sh
solc --deploy MyContract.sol --rpc-url https://rpc.sepolia.org --private-key 0x...
```

## 文件中有多个合约时，指定要部署的合约名

```sh
solc --deploy MyContract.sol --contract MyToken --private-key 0x...
```

## 同时输出 ABI 再部署

```sh
solc --bin --abi --deploy MyContract.sol --private-key 0x...
```

## 参数说明

| 参数 | 环境变量 | 默认值 | 说明 |
|------|----------|--------|------|
| `--rpc-url` | `RPC_URL` | `http://127.0.0.1:8545` | JSON-RPC 节点地址 |
| `--private-key` | `PRIVATE_KEY` | 无（必填） | 十六进制私钥，用于签名交易 |
| `--contract` | — | 自动（单合约时） | 文件含多合约时指定名称 |

命令行参数优先级高于环境变量。

## 部署成功输出示例

```
────────────────────────────────────────────────────────────
  Deployed: Counter
────────────────────────────────────────────────────────────
  Address  : 0x5FbDB2315678afecb367f032d93F642f64180aa3
  Tx hash  : 0xabc123...
  Gas used : 156432

  Public functions:
    set(uint256 v)
    get() → uint256  [view]
    value() → uint256  [view]
────────────────────────────────────────────────────────────
  Record saved → /your/project/deployments.json
```

## deployments.json 格式

每次部署追加一条记录，不覆盖旧记录：

```json
[
  {
    "name": "Counter",
    "address": "0x5FbDB2315678afecb367f032d93F642f64180aa3",
    "chainId": 31337,
    "txHash": "0xabc123...",
    "rpcUrl": "http://127.0.0.1:8545",
    "deployedAt": "2026-06-30T10:00:00.000Z",
    "abi": [...]
  }
]
```
