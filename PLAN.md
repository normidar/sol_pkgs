# sol_pkgs — 実装状況と今後のプラン

最終更新: 2026-06-17

---

## 凡例

| 記号 | 意味 |
|---|---|
| ✅ | 実装済み（動作する） |
| 🟡 | 骨格のみ（コンパイルは通るが機能が不完全） |
| ❌ | 未実装 |
| 🐛 | 既知のバグ・不整合 |

---

## パッケージ別ステータス

### `sol_support` ✅ 完成度: 高

| 機能 | 状態 |
|---|---|
| `SourceLocation` (オフセット+長さ) | ✅ |
| `SourceMap` (オフセット → 行/列) | ✅ |
| `SourceUnit` / `SourceUnitRegistry` | ✅ |
| `DiagnosticCollector` (info/warning/error/fatal) | ✅ |
| `FatalErrorException` | ✅ |
| `ImportRemapping` / `ImportRemapper` | ✅ |
| テスト | ✅ |

---

### `sol_lexer` ✅ 完成度: 高

| 機能 | 状態 |
|---|---|
| キーワード全量 (contract/function/pure/view … ) | ✅ |
| `uint8`〜`uint256` / `int8`〜`int256` / `bytes1`〜`bytes32` | ✅ |
| 10進数・16進数・浮動小数点リテラル | ✅ |
| 文字列 `"…"` / `unicode"…"` / `hex"…"` | ✅ |
| 全演算子 (`**`, `>>>`, `<<=`, `>>>=` 含む) | ✅ |
| 単行 `//` / ブロック `/* */` コメント | ✅ |
| テスト | ✅ |
| **`returns` キーワードが `TokenKind` に未定義** | 🐛 |

> **Bug:** `sol_parser` は `TokenKind.kReturns` を参照しているが、`sol_lexer/src/token_kind.dart` の `TokenKind` enum と `_keywords` マップに `returns` エントリが存在しない。パーサは `returns` をIdentifierとして読むため `_tryConsume(TokenKind.kReturns)` が常に失敗し、戻り型が正しく解析されない。

---

### `sol_ast` 🟡 完成度: 中（設計は完成、クラス重複あり）

| 機能 | 状態 |
|---|---|
| 全宣言ノード (contract/function/event/error/struct/enum/state var) | ✅ |
| 全文ノード (block/if/for/while/return/emit/revert/assembly …) | ✅ |
| 全式ノード (literal/identifier/binary/call/conditional …) | ✅ |
| 型名ノード (elementary/array/mapping/user-defined/function) | ✅ |
| `AstVisitor` (ダブルディスパッチ) | ✅ |
| `AstNode.annotation` (後段フェーズが型情報を書き込むスロット) | ✅ |
| テスト | ✅ |
| **`VariableDeclaration` が2箇所に重複定義** | 🐛 |
| **`Expression` / `Parameter` が `type_names.dart` に前方参照として重複定義** | 🐛 |

> **Bug (重大):** `VariableDeclaration` クラスが `declarations.dart` と `statements.dart` の両方に定義されており、`lib/sol_ast.dart` でエクスポートするとコンパイルエラーになる可能性がある。同様に `Expression` と `Parameter` が `type_names.dart` にも前方参照として定義されており、`expressions.dart` と重複する。ファイルを整理してクラスを単一定義にまとめる必要がある。

---

### `sol_parser` 🟡 完成度: 中

| 機能 | 状態 |
|---|---|
| `pragma` / `import` | ✅ |
| `contract` / `interface` / `library` (継承込み) | ✅ |
| `function` 全修飾子 (visibility/mutability/virtual/override) | ✅ |
| `modifier` / `event` / `error` | ✅ |
| `struct` / `enum` | ✅ |
| 状態変数宣言 | ✅ |
| 全文 (if/for/while/do/return/break/continue/emit/revert/assembly) | ✅ |
| 全式 (三項演算子・代入・後置++/--・タプル・named args) | ✅ |
| 型名 (mapping/function type/配列) | ✅ |
| エラーリカバリ | 🟡 基本的な同期のみ |
| **`returns` キーワード未定義により戻り型の解析が壊れる** | 🐛 |
| `using X for Y` 構文 | ❌ |
| `unchecked { }` ブロック | ❌ |
| `try/catch` 文 | ❌ |
| NatSpec コメント (`///` / `/** */`) | ❌ |
| テスト | 🟡 主要パスのみ |

---

### `sol_types` ✅ 完成度: 高

| 機能 | 状態 |
|---|---|
| `IntType` (int8〜int256, uint8〜uint256) min/max | ✅ |
| `BoolType` / `AddressType` / `BytesNType` | ✅ |
| `BytesType` / `StringType` (動的) | ✅ |
| `ArrayType` (固定長・動的) | ✅ |
| `MappingType` | ✅ |
| `TupleType` | ✅ |
| `FunctionType` (stateMutability 付き) | ✅ |
| `TypeType` / `ErrorType` (番兵) | ✅ |
| `isImplicitlyConvertible` / `isExplicitlyConvertible` | ✅ |
| `commonType` (二項演算の共通型) | ✅ |
| テスト | ✅ |
| 有理数リテラル型 (`RationalNumberType`) | ❌ |
| `FixedType` / `UFixedType` (固定小数点) | ❌ |

---

### `sol_sema` 🟡 完成度: 低〜中

| 機能 | 状態 |
|---|---|
| C3 多重継承線形化 | ✅ |
| スコープチェーン (`Scope` / `Symbol`) | ✅ |
| コントラクト内メンバの巻き上げ (関数・状態変数・イベント) | ✅ |
| ローカル変数の宣言と登録 | ✅ |
| `Identifier` の名前解決と `annotation` 書き込み | ✅ |
| テスト | 🟡 C3 のみ |
| **if/while/for/return 文中の Identifier を再帰的にウォークしない** | 🐛 |
| 型検査 (BinaryOperation, Literal) | 🟡 最小限 |
| FunctionCall の型解決 | ❌ |
| Identifier の型注釈 (sema→types バインディング) | ❌ |
| override 整合性チェック | ❌ |
| 可視性チェック | ❌ |
| `pure`/`view` ルール検証 | ❌ |
| 未使用変数の警告 | ❌ |
| 循環 import 検出 | ❌ |

---

### `sol_evm` ✅ 完成度: 高

| 機能 | 状態 |
|---|---|
| 全オペコード (Shanghai + Cancun: TLOAD/TSTORE/MCOPY/BLOBHASH/BLOBBASEFEE/PUSH0) | ✅ |
| スタック消費数 / 生成数 / ベースガスコスト | ✅ |
| `Opcode.fromByte()` / `Opcode.pushForSize()` | ✅ |
| `Assembler`: `emit` / `push(BigInt)` / `push1` | ✅ |
| `Assembler`: `label` / `jump` / `jumpi` (2パスラベル解決) | ✅ |
| `Assembler`: `dup(n)` / `swap(n)` / `add` / `ret` 等の便利メソッド | ✅ |
| テスト | ✅ |
| バイトコードリンカ (library address placeholder) | ❌ |
| ガス見積もりユーティリティ | ❌ |

---

### `sol_yul` 🟡 完成度: 中

| 機能 | 状態 |
|---|---|
| Yul AST 全ノード (sealed class) | ✅ |
| `YulPrinter` (AST → Yul テキスト) | ✅ |
| `YulCodeGenerator` — `if` / `for` / `switch` 文 | ✅ |
| `YulCodeGenerator` — 全組み込みオペコード関数 (`add`, `sload` …) | ✅ |
| `YulCodeGenerator` — 数値リテラル / bool リテラル | ✅ |
| テスト | 🟡 |
| **変数 (`YulIdentifier`) は常に `PUSH0` を返す (スタックスロット未実装)** | 🐛 |
| **`YulVariableDeclaration` / `YulAssignment` でスタックへのストアなし** | 🐛 |
| **`YulFunctionDefinition` がスキップされる (ホイスト未実装)** | 🐛 |
| Yul オプティマイザ (定数畳み込み / DCE / インライン展開) | ❌ |
| Yul パーサ (`assembly { … }` ブロックのパース) | ❌ |

---

### `sol_codegen` 🟡 完成度: 低〜中

| 機能 | 状態 |
|---|---|
| デプロイメントコード骨格 (codecopy + return) | ✅ |
| ABI ディスパッチャ骨格 (switch on selector) | ✅ |
| 関数定義の Yul 関数への変換 | ✅ |
| `return` 文 → `leave` | ✅ |
| `if` 文 | ✅ |
| 二項算術演算子 (`+`, `-`, `*`, `/` 等) | ✅ |
| **関数セレクタが `hashCode` のプレースホルダ (keccak256 未実装)** | 🐛 |
| **ABI パラメータデコードが常に `calldataload(4)` を返すだけ** | 🐛 |
| **複数引数の `calldataload` オフセットが計算されない** | 🐛 |
| `for` / `while` / `do-while` 文 | ❌ |
| `WhileStatement` / `ForStatement` のコード生成 | ❌ |
| `MemberAccess` (状態変数 SLOAD/SSTORE) | ❌ |
| 構造体 / 配列アクセス | ❌ |
| `emit` / `revert` 文 | ❌ |
| コンストラクタ実行 | ❌ |
| ABI 戻り値エンコード (MSTORE + RETURN) | ❌ |
| テスト | 🟡 |

---

### `sol_abi` 🟡 完成度: 中

| 機能 | 状態 |
|---|---|
| `function` エントリの ABI JSON 生成 | ✅ |
| `event` エントリの ABI JSON 生成 | ✅ |
| `error` エントリの ABI JSON 生成 | ✅ |
| ABI エンコード: uint/int (任意幅) | ✅ |
| ABI エンコード: bool / address | ✅ |
| ABI エンコード: bytes1〜bytes32 | ✅ |
| ABI エンコード: bytes / string (動的) | ✅ |
| ABI エンコード: T[] / T[N] | ✅ |
| **`event` の `indexed` フラグが常に `false`** | 🐛 |
| **固定長配列の ABI 型文字列が `T[TODO]` になる** | 🐛 |
| **UserDefinedType が `nameParts.last` のみを返す** | 🐛 |
| ABI エンコード: tuple / struct | ❌ |
| ABI デコード | ❌ |
| ABI エンコード: mapping | ❌ (spec 上は不可だが型判定が必要) |
| NatSpec (devdoc / userdoc) 生成 | ❌ |
| メタデータ JSON 生成 | ❌ |
| テスト | 🟡 |

---

### `sol_driver` 🟡 完成度: 低〜中

| 機能 | 状態 |
|---|---|
| `CompilerStack.addSource` / `compile` のパイプライン接続 | ✅ |
| `CompilationResult` / `ContractOutput` データ構造 | ✅ |
| standard-JSON 入出力インターフェース | ✅ |
| **`deployedBytecode` が常に空 (ランタイムバイトコード分離未実装)** | 🐛 |
| import 解決 (複数ファイルのつなぎ) | ❌ |
| remapping 適用 | ❌ |
| `settings.optimizer` / 最適化フラグ | ❌ |
| テスト | 🟡 |

---

### `sol_cli` 🟡 完成度: 高 (フロントエンドのみ)

| 機能 | 状態 |
|---|---|
| `--bin` / `--abi` / `--ir` フラグ | ✅ |
| `--standard-json` (stdin→stdout) | ✅ |
| `--version` / `--help` | ✅ |
| ファイル複数指定 | ✅ |
| `dart run sol_cli:solc` でのエントリポイント | ✅ |
| `--optimize` / `--optimize-runs` | ❌ |
| `--remappings` | ❌ |
| `--base-path` / `--include-path` | ❌ |
| テスト | ❌ |

---

## 既知の重大バグ（修正しないと動かない）

| # | 場所 | 内容 |
|---|---|---|
| B-1 | `sol_lexer/token_kind.dart` | `TokenKind.kReturns` が enum に存在しない。`sol_parser` が参照しているため関数の戻り型が全て解析失敗になる |
| B-2 | `sol_ast/statements.dart` | `VariableDeclaration` が `declarations.dart` と重複定義。`sol_ast.dart` でエクスポートするとコンパイルエラー |
| B-3 | `sol_ast/type_names.dart` | `Expression` / `Parameter` が前方参照として重複定義されている |
| B-4 | `sol_yul/yul_codegen.dart` | `YulIdentifier` が常に `PUSH0` を返す。変数のスタックスロット管理が未実装なため正しいバイトコードを生成できない |
| B-5 | `sol_codegen/ir_generator.dart` | 関数セレクタが `hashCode` ベースのプレースホルダ。実際のkeccak256ハッシュライブラリの追加が必要 |
| B-6 | `sol_codegen/ir_generator.dart` | `calldataload` のオフセット計算が固定値 `4`。複数引数は正しく読めない |

---

## 推奨修正順序（第1マイルストーン: Adder.sol をバイトコードまで通す）

```
Step 1: B-2, B-3 を修正 → sol_ast をコンパイル可能にする
Step 2: B-1 を修正     → sol_parser が returns を認識できるようにする
Step 3: B-4 を修正     → Yul 変数のスタックスロット管理を実装
Step 4: B-5 を修正     → keccak256 パッケージ (dart pub add pointycastle 等) でセレクタ計算
Step 5: B-6 を修正     → ABI calldataload オフセット計算
Step 6: ABI 戻り値エンコード (MSTORE + RETURN) を sol_codegen に追加
Step 7: melos bootstrap → melos run test で全テスト通過確認
```

---

## 第2マイルストーン以降（優先度順）

| 優先度 | タスク |
|---|---|
| 高 | `sol_sema`: if/while/for 文中の Identifier を再帰ウォーク |
| 高 | `sol_codegen`: for/while 文のコード生成 |
| 高 | `sol_codegen`: 状態変数 SLOAD/SSTORE |
| 中 | `sol_sema`: 型検査の全式対応 (FunctionCall, MemberAccess …) |
| 中 | `sol_codegen`: emit / revert / コンストラクタ |
| 中 | `sol_abi`: tuple エンコード / ABI デコード |
| 中 | `sol_parser`: `using X for Y` / `unchecked` / `try/catch` |
| 低 | `sol_yul`: Yul パーサ (インライン assembly の完全サポート) |
| 低 | `sol_yul`: オプティマイザ (定数畳み込み / DCE / インライン) |
| 低 | `sol_abi`: NatSpec / メタデータ JSON |
| 低 | `sol_cli`: `--remappings` / `--base-path` |
