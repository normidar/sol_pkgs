# 01 安装 CLI

在 monorepo 根目录执行一次，将 `solc` 命令安装到全局：

```sh
dart pub global activate --source path packages/sol_cli
```

安装后确认可用：

```sh
solc --version
# solc-dart 0.1.0

solc --help
```

不想全局安装时也可以直接 `dart run`：

```sh
dart run sol_cli:solc --bin MyContract.sol
```
