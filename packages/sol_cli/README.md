# sol_cli

Command-line interface for the `sol_pkgs` Solidity compiler.

Kept intentionally thin — all real work is delegated to `sol_driver`.

## Installation

```sh
# From the monorepo root after `melos bootstrap`:
dart pub global activate --source path packages/sol_cli
```

## Usage

```sh
# Compile and print EVM bytecode
solc --bin Adder.sol

# Print ABI JSON
solc --abi Adder.sol

# Print Yul IR
solc --ir Adder.sol

# All outputs at once
solc --bin --abi --ir Adder.sol

# Standard-JSON mode (pipe)
echo '{"language":"Solidity","sources":{"Adder.sol":{"content":"…"}}}' | solc --standard-json

# Version
solc --version
```

## Running without installing

```sh
dart run sol_cli:solc --bin Adder.sol
```

## Example output

```
======= Adder =======
Binary:
6080604052...
```

## Dependencies

- `sol_driver` — all compiler phases
- `args` — argument parsing
