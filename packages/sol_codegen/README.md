# sol_codegen

Lowers semantically-analysed Solidity AST to Yul IR for the `sol_pkgs` compiler.

Corresponds to solc's `IRGenerator` and `IRGeneratorForStatements` subsystem.

## What it produces

For each contract, `IRGenerator` emits a two-level `YulObject`:

```
object "Adder" {
    code {
        // deployment code: copy runtime object to memory, return it
        codecopy(0, dataoffset("Adder_deployed"), datasize("Adder_deployed"))
        return(0, datasize("Adder_deployed"))
    }
    object "Adder_deployed" {
        code {
            // ABI dispatcher (switch on selector)
            switch shr(224, calldataload(0))
            case 0xdeadbeef { … }  // getSum selector
            revert(0, 0)

            // function implementations
            function fun_getSum(param_a, param_b) -> ret_0 {
                ret_0 := add(var_a, var_b)
                leave
            }
        }
    }
}
```

## Usage

```dart
import 'package:sol_codegen/sol_codegen.dart';
import 'package:sol_support/sol_support.dart';
import 'package:sol_yul/sol_yul.dart';

void compile(ContractDefinition contract) {
  final diagnostics = DiagnosticCollector();
  final yulObj = IRGenerator(diagnostics).generateContract(contract);

  // Print IR
  print(YulPrinter().print(yulObj));

  // Compile to bytecode
  final bytecode = YulCodeGenerator().generate(yulObj);
  print(bytecode.map((b) => b.toRadixString(16).padLeft(2, '0')).join());
}
```

## Current status

- [x] Deployment skeleton (codecopy + return)
- [x] ABI dispatcher (switch on selector)
- [x] Function definition lowering
- [x] `return` statement with `leave`
- [x] Binary arithmetic operators
- [ ] Full ABI encoding/decoding
- [ ] Storage read/write
- [ ] Struct / array access
- [ ] Events / errors

## Dependencies

- `sol_support` — diagnostics
- `sol_ast` — source AST nodes
- `sol_types` — type information
- `sol_yul` — Yul IR
