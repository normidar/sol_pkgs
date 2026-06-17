# sol_pkgs — Solidity Compiler in Pure Dart

A from-scratch Solidity compiler written entirely in Dart, structured as a
[melos](https://melos.invertase.dev/) monorepo.

## Architecture

```
sol_cli          (CLI front-end)
   └── sol_driver      (CompilerStack / standard-JSON I/O)
         ├── sol_abi        (ABI / metadata / NatSpec JSON)
         ├── sol_codegen    (AST → Yul IR)
         │     ├── sol_sema      (name resolution, type checking)
         │     │     ├── sol_types   (Solidity type system)
         │     │     └── sol_ast     (AST nodes + visitor)
         │     └── sol_yul      (Yul IR + optimiser + EVM dialect)
         │           └── sol_evm  (opcodes, assembler, bytecode)
         └── sol_parser    (source → AST)
               ├── sol_lexer   (tokeniser)
               └── sol_ast
                     └── sol_support  (SourceLocation, diagnostics, remapping)
```

All arrows read "depends on".  `sol_support` is the universal foundation.

## Packages

| Package | Description |
|---|---|
| [`sol_support`](packages/sol_support) | Source locations, diagnostics, import remapping |
| [`sol_lexer`](packages/sol_lexer) | Tokeniser / scanner |
| [`sol_ast`](packages/sol_ast) | AST node definitions + visitor framework |
| [`sol_parser`](packages/sol_parser) | Recursive-descent parser (tokens → AST) |
| [`sol_types`](packages/sol_types) | Solidity type system |
| [`sol_sema`](packages/sol_sema) | Name resolution, scope, type checking |
| [`sol_evm`](packages/sol_evm) | EVM opcodes, assembler, bytecode linker |
| [`sol_yul`](packages/sol_yul) | Yul IR, optimiser, EVM dialect |
| [`sol_codegen`](packages/sol_codegen) | Solidity AST → Yul IR lowering |
| [`sol_abi`](packages/sol_abi) | ABI JSON, metadata JSON, NatSpec |
| [`sol_driver`](packages/sol_driver) | Compiler orchestration, standard-JSON |
| [`sol_cli`](packages/sol_cli) | `solc` command-line interface |

## Recommended Build Order

```
sol_support → sol_lexer → sol_ast → sol_parser   (parse milestone)
           └→ sol_evm → sol_yul                   (Yul → bytecode milestone)
sol_types → sol_sema → sol_codegen                (Solidity front-end)
sol_abi → sol_driver → sol_cli                    (output + CLI)
```

## Prerequisites

- Dart SDK `>=3.4.0`
- [melos](https://melos.invertase.dev/) `>=6.0.0`

```sh
dart pub global activate melos
```

## Getting Started

```sh
# bootstrap all packages
melos bootstrap

# analyse
melos run analyze

# test everything
melos run test
```

## First Milestone

Compile a minimal `pure` function to EVM bytecode:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Adder {
    function getSum(uint256 a, uint256 b) public pure returns (uint256) {
        return a + b;
    }
}
```

```sh
dart run sol_cli:solc --bin Adder.sol
```

## License

MIT
