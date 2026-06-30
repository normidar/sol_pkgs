# 02 编译合约

## 基本输出

```sh
# 输出 EVM 字节码（十六进制）
solc --bin MyContract.sol

# 输出 ABI JSON
solc --abi MyContract.sol

# 输出 Yul IR
solc --ir MyContract.sol

# 同时输出多项
solc --bin --abi --ir MyContract.sol
```

`--bin` 输出示例：

```
======= MyContract =======
Binary:
6080604052...
```

## 输出到目录

```sh
solc --bin --abi --output-dir ./out MyContract.sol
# 生成 out/MyContract.bin 和 out/MyContract.abi
```

## 编译选项

```sh
# 启用 Yul 优化器
solc --optimize --bin MyContract.sol

# 将警告视为错误
solc --warnings-as-errors MyContract.sol
```

## Standard-JSON 模式

兼容 solc 标准 JSON 接口，从 stdin 读取、结果写到 stdout：

```sh
echo '{
  "language": "Solidity",
  "sources": { "A.sol": { "content": "..." } },
  "settings": { "outputSelection": { "*": { "*": ["abi", "evm.bytecode"] } } }
}' | solc --standard-json
```

## 合约名称说明

同一个 `.sol` 文件可以定义多个合约，输出时以合约名（不是文件名）区分：

```
======= Foo =======
Binary: ...

======= Bar =======
Binary: ...
```

`--output-dir` 时生成 `Foo.bin`、`Bar.bin`，以此类推。
