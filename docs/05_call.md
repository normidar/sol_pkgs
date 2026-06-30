# 05 调用合约函数

自动从当前目录的 `deployments.json` 读取合约地址和 ABI，无需手动指定。

## view / pure 函数（只读，无需私钥）

```sh
solc --call "Counter.get()"
solc --call "Counter.getSum(3,5)"
```

底层使用 `eth_call`，不消耗 Gas，立即返回结果。

输出示例：

```
────────────────────────────────────────────────────────────
  Result: get()  [view]
────────────────────────────────────────────────────────────
  uint256 = 42
────────────────────────────────────────────────────────────
```

## 状态变更函数（需要私钥签名）

```sh
PRIVATE_KEY=0x... solc --call "Counter.set(123)"
PRIVATE_KEY=0x... RPC_URL=http://127.0.0.1:8545 solc --call "Counter.increment()"
```

底层签名并广播交易，返回交易哈希。

输出示例：

```
────────────────────────────────────────────────────────────
  Called: Counter.set(uint256)
────────────────────────────────────────────────────────────
  Tx hash : 0xdef456...
  Status  : pending (state-changing call)
────────────────────────────────────────────────────────────
```

## 调用格式

```
solc --call "ContractName.functionName(arg1,arg2,...)"
```

合约名必须与 `deployments.json` 中的记录名一致（即 Solidity 合约名，不是文件名）。

## 参数类型格式

| Solidity 类型 | CLI 写法示例 |
|---------------|-------------|
| `uint256` / `int256` | `123` 或 `0x7b` |
| `address` | `0x5FbDB2315678afecb367f032d93F642f64180aa3` |
| `bool` | `true` / `false` |
| `string` | `"hello"` |
| `bytes32` | `0xabcd...` |

## RPC 节点配置

`--call` 同样支持 `--rpc-url` 参数和 `RPC_URL` 环境变量，默认使用 `http://127.0.0.1:8545`。
