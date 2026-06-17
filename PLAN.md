# sol_pkgs — 実装状況と今後のプラン

最終更新: 2026-06-17

---

## 凡例

| 記号 | 意味 |
|---|---|
| ✅ | 実装済み（テスト通過） |
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
| `LineColumn` — `==` / `hashCode` 実装済み | ✅ |
| `SourceUnit` / `SourceUnitRegistry` | ✅ |
| `DiagnosticCollector` (info/warning/error/fatal) | ✅ |
| `FatalErrorException` | ✅ |
| `ImportRemapping` / `ImportRemapper` (コンテキスト優先修正済み) | ✅ |
| テスト (8件通過) | ✅ |

---

### `sol_lexer` ✅ 完成度: 高

| 機能 | 状態 |
|---|---|
| キーワード全量 (returns/try/catch/unchecked/indexed/anonymous 含む) | ✅ |
| `uint8`〜`uint256` / `int8`〜`int256` / `bytes1`〜`bytes32` | ✅ |
| 10進数・16進数・アンダースコア区切り (`0x1_000`) | ✅ |
| 文字列 `"…"` / `unicode"…"` / `hex"…"` (開始引用符スキップ修正済み) | ✅ |
| 全演算子 (`**`, `>>>`, `<<=`, `>>>=` 含む) — lexeme 設定修正済み | ✅ |
| 単行 `//` / ブロック `/* */` コメント | ✅ |
| NatSpec `///` → `NatSpecLine` / `/** */` → `NatSpecBlock` | ✅ |
| テスト (13件通過) | ✅ |

---

### `sol_ast` ✅ 完成度: 高

| 機能 | 状態 |
|---|---|
| 共有 enum を `enums.dart` に分離 (DataLocation/Visibility/StateMutability 等) | ✅ |
| `AstVisitor` の二重定義問題を解消 (`ast_node.dart` に stub なし) | ✅ |
| 全宣言ノード — `FunctionKind` (function/constructor/fallback/receive) 付き | ✅ |
| `UsingDirective` / `UserDefinedValueTypeDefinition` | ✅ |
| 全文ノード — `UncheckedStatement` / `TryStatement` / `CatchClause` 追加 | ✅ |
| 全式ノード — `DeleteExpression` / `TypeExpression` / `FunctionCallOptions` 追加 | ✅ |
| 型名ノード (elementary/array/mapping/user-defined/function) | ✅ |
| `Parameter.indexed` (イベントパラメータ用) | ✅ |
| `AstVisitor` — 全新規ノードの visit メソッド (子ウォーク実装付き) | ✅ |
| `AstNode.annotation` (後段フェーズが型情報を書き込むスロット) | ✅ |
| テスト (2件通過) | ✅ |

---

### `sol_parser` ✅ 完成度: 高

| 機能 | 状態 |
|---|---|
| `pragma` / `import` (plain/alias/named/star) | ✅ |
| `contract` / `interface` / `library` / `abstract` (継承込み) | ✅ |
| `function` 全修飾子 (visibility/mutability/virtual/override/modifiers) | ✅ |
| `constructor` / `fallback` / `receive` | ✅ |
| `modifier` / `event` (indexed) / `error` | ✅ |
| `struct` / `enum` | ✅ |
| `using X for Y` / `using X for *` | ✅ |
| `type T is uint256` (ユーザー定義値型) | ✅ |
| 状態変数宣言 (immutable/constant) | ✅ |
| 全文 (if/for/while/do/return/break/continue/emit/revert) | ✅ |
| `unchecked { }` ブロック | ✅ |
| `try/catch` 文 | ✅ |
| `assembly "evmasm" { … }` (本体は rawYul として保存) | ✅ |
| 全式 (三項演算子・代入・後置++/--・タプル) | ✅ |
| 呼び出しオプション `f{value: v, gas: g}(args)` | ✅ |
| スライスアクセス `arr[1:2]` | ✅ |
| 配列リテラル `[a, b, c]` | ✅ |
| `delete x` / `type(T)` / `new T(…)` | ✅ |
| 名前付き引数 `f({key: val})` | ✅ |
| `address payable` 型名 | ✅ |
| NatSpec (`///` / `/** */`) トークン保持 | ✅ |
| エラーリカバリ (パニックモード + `_synchronize`) | ✅ |
| 型名ヒューリスティック (`_looksLikeTypeName`) | ✅ |
| テスト (7件通過) | ✅ |

---

### `sol_types` ✅ 完成度: 高

| 機能 | 状態 |
|---|---|
| `IntType` (int8〜int256, uint8〜uint256) min/max | ✅ |
| `BoolType` / `AddressType` / `BytesNType` | ✅ |
| `BytesType` / `StringType` (動的) | ✅ |
| `ArrayType` (固定長・動的) / `MappingType` / `TupleType` | ✅ |
| `FunctionType` / `TypeType` / `ErrorType` (番兵) | ✅ |
| `isImplicitlyConvertible` / `isExplicitlyConvertible` / `commonType` | ✅ |
| テスト (11件通過) | ✅ |
| 有理数リテラル型 (`RationalNumberType`) | ❌ |
| `FixedType` / `UFixedType` (固定小数点) | ❌ |

---

### `sol_sema` ✅ 完成度: 中〜高

| 機能 | 状態 |
|---|---|
| C3 多重継承線形化 (サイクル検出修正済み) | ✅ |
| スコープチェーン (`Scope` / `Symbol`) | ✅ |
| コントラクト内全メンバの巻き上げ (関数・状態変数・イベント・エラー・struct・enum・modifier・UDVT) | ✅ |
| ローカル変数の宣言と登録 | ✅ |
| 名前付き返り値パラメータのスコープ登録 | ✅ |
| `Identifier` の名前解決と `annotation` 書き込み | ✅ |
| 組み込み名 (msg/block/tx/this/super/require 等) の偽陽性抑制 | ✅ |
| 全文を再帰ウォーク (if/while/for/do-while/try-catch/return/emit/revert/unchecked) | ✅ |
| 全式を再帰ウォーク (binary/unary/assign/call/member/index/conditional/tuple) | ✅ |
| `Modifier` 本体の名前解決 | ✅ |
| `TypeChecker.check(SourceFile)` エントリポイント | ✅ |
| 型検査: Literal/BinaryOp/UnaryOp/Assignment/Conditional + 全文 | ✅ |
| `visitVariableDeclarationStatement`: 宣言変数の型アノテーション | ✅ |
| テスト (28件通過) | ✅ |
| FunctionCall の型解決 | ❌ |
| MemberAccess の型解決 | ❌ |
| override 整合性チェック / 可視性チェック / pure/view ルール | ❌ |
| 未使用変数の警告 / 循環 import 検出 | ❌ |

---

### `sol_evm` ✅ 完成度: 高

| 機能 | 状態 |
|---|---|
| 全オペコード (Shanghai + Cancun: TLOAD/TSTORE/MCOPY/BLOBHASH/PUSH0 等) | ✅ |
| スタック消費数 / 生成数 / ベースガスコスト | ✅ |
| `Assembler`: `emit` / `push(BigInt)` / `label` / `jump` / `jumpi` | ✅ |
| `pushLabel(name)` — ラベルオフセットをスタック値として PUSH2 生成 | ✅ |
| 2パスラベル解決 (`PushLabelInstruction` 対応済み) | ✅ |
| テスト (7件通過) | ✅ |
| バイトコードリンカ (library address placeholder) | ❌ |

---

### `sol_yul` ✅ 完成度: 高

| 機能 | 状態 |
|---|---|
| Yul AST 全ノード (sealed class) | ✅ |
| `YulPrinter` (AST → Yul テキスト) | ✅ |
| `YulCodeGenerator` — if/for/switch/組み込み関数/リテラル | ✅ |
| `_Frame` クラス — EVM スタックスロットを名前付きで管理 | ✅ |
| `YulVariableDeclaration` — 値を push し名前スロットとして登録 | ✅ |
| `YulIdentifier` — DUP(depth) で変数参照 | ✅ |
| `YulAssignment` — SWAP(d)+POP で指定スロットを上書き | ✅ |
| `YulFunctionDefinition` — ホイスト、フレーム設定、leave 生成 (M=0,1) | ✅ |
| `YulBreak` / `YulContinue` — ループラベルスタック | ✅ |
| 組み込み void 関数 (mstore/sstore/log*/pop 等) の POP 抑制 | ✅ |
| テスト (17件通過) | ✅ |
| Yul パーサ (`assembly { … }` ブロック) | ❌ |
| 複数返り値関数 (M>1) のホイスト | ❌ |
| Yul オプティマイザ | ❌ |

---

### `sol_codegen` 🟡 完成度: 低〜中

| 機能 | 状態 |
|---|---|
| デプロイメントコード骨格 (codecopy + return) | ✅ |
| ABI ディスパッチャ骨格 (switch on selector) | ✅ |
| 関数定義 → Yul 関数変換 (`return` → `leave` 含む) | ✅ |
| `if` 文 / 二項算術演算子 | ✅ |
| テスト (3件通過) | 🟡 |
| **関数セレクタが `hashCode` プレースホルダ (keccak256 未実装)** | 🐛 |
| **ABI パラメータデコードが常に `calldataload(4)` のみ** | 🐛 |
| for/while/do-while 文 | ❌ |
| 状態変数 SLOAD/SSTORE | ❌ |
| `emit` / `revert` / コンストラクタ | ❌ |
| ABI 戻り値エンコード (MSTORE + RETURN) | ❌ |

---

### `sol_abi` 🟡 完成度: 中

| 機能 | 状態 |
|---|---|
| `function` / `event` / `error` エントリの ABI JSON 生成 | ✅ |
| ABI エンコード: uint/int/bool/address/bytes1〜32/bytes/string/T[]/T[N] | ✅ |
| テスト (4件通過) | 🟡 |
| **`event` の `indexed` フラグが常に `false`** | 🐛 |
| **固定長配列の ABI 型文字列が `T[TODO]`** | 🐛 |
| ABI エンコード: tuple/struct | ❌ |
| ABI デコード | ❌ |
| NatSpec (devdoc/userdoc) / メタデータ JSON | ❌ |

---

### `sol_driver` 🟡 完成度: 低〜中

| 機能 | 状態 |
|---|---|
| `CompilerStack.addSource` / `compile` パイプライン | ✅ |
| `CompilationResult` / `ContractOutput` データ構造 | ✅ |
| standard-JSON 入出力インターフェース | ✅ |
| テスト (3件通過) | ✅ |
| **`deployedBytecode` が常に空 (ランタイム/デプロイ分離未実装)** | 🐛 |
| import 解決 (複数ファイル) / remapping 適用 | ❌ |
| `settings.optimizer` フラグ | ❌ |

---

### `sol_cli` 🟡 完成度: 高 (フロントエンドのみ)

| 機能 | 状態 |
|---|---|
| `--bin` / `--abi` / `--ir` / `--standard-json` / `--version` / `--help` | ✅ |
| ファイル複数指定 | ✅ |
| `dart run sol_cli:solc` エントリポイント | ✅ |
| `--optimize` / `--remappings` / `--base-path` / `--include-path` | ❌ |
| テスト | ❌ |

---

## 解決済みバグ

| # | 場所 | 内容 | 修正日 |
|---|---|---|---|
| B-1 | `sol_lexer/token_kind.dart` | `TokenKind.kReturns` が未定義 → 戻り型の解析が常に失敗 | 2026-06-17 |
| B-2 | `sol_ast/statements.dart` | `VariableDeclaration` が `declarations.dart` と重複定義 | 2026-06-17 |
| B-3 | `sol_ast/type_names.dart` | `Expression` / `Parameter` の前方参照重複定義 | 2026-06-17 |
| B-7 | `sol_ast/ast_node.dart` | `AstVisitor` stub と `visitor.dart` の二重定義による ambiguous_export | 2026-06-17 |
| B-8 | `sol_lexer/lexer.dart` | `_scanString` が開始引用符を終了引用符と誤認 → 文字列が空になる | 2026-06-17 |
| B-9 | `sol_lexer/lexer.dart` | `_tok()` が `lexeme` を設定しない → 演算子 lexeme が常に `''` | 2026-06-17 |
| B-10 | `sol_support/source_location.dart` | `LineColumn` に `==`/`hashCode` なし → テスト比較が常に失敗 | 2026-06-17 |
| B-11 | `sol_support/import_remapping.dart` | コンテキスト固有 remapping がグローバルに負ける | 2026-06-17 |
| B-12 | `sol_sema/c3_lineariser.dart` | サイクルで `C3LinearisationError` でなく無限再帰 / StackOverflow | 2026-06-17 |
| B-13 | `sol_codegen/ir_generator.dart` | `"$operator$"` の文字列補間エラー | 2026-06-17 |

---

## 解決済みバグ（B-4 追加）

| # | 場所 | 内容 | 修正日 |
|---|---|---|---|
| B-4 | `sol_yul/yul_codegen.dart` | `YulIdentifier` が常に `PUSH0` — `_Frame` + DUP(depth) で修正 | 2026-06-17 |

## 残存バグ（未修正）

| # | 場所 | 内容 |
|---|---|---|
| B-5 | `sol_codegen/ir_generator.dart` | 関数セレクタが `hashCode` プレースホルダ (keccak256 未実装) |
| B-6 | `sol_codegen/ir_generator.dart` | `calldataload` オフセット固定値 `4` (複数引数で不正) |

---

## テスト通過状況 (2026-06-17 現在)

| パッケージ | テスト数 | 状態 |
|---|---|---|
| sol_support | 8 | ✅ 全通過 |
| sol_lexer | 13 | ✅ 全通過 |
| sol_ast | 2 | ✅ 全通過 |
| sol_types | 11 | ✅ 全通過 |
| sol_parser | 7 | ✅ 全通過 |
| sol_sema | 28 | ✅ 全通過 |
| sol_abi | 4 | ✅ 全通過 |
| sol_codegen | 3 | ✅ 全通過 |
| sol_evm | 7 | ✅ 全通過 |
| sol_yul | 17 | ✅ 全通過 |
| sol_driver | 3 | ✅ 全通過 |
| **合計** | **103** | **✅ 全通過** |

---

## 第1マイルストーン: Adder.sol をバイトコードまで通す

残りタスク:

```
Step 1 (完了): B-4 修正 — Yul 変数のスタックスロット管理 (_Frame + DUP/SWAP)
Step 2 (残存): B-5 修正 — keccak256 パッケージ (pointycastle 等) でセレクタ計算
Step 3 (残存): B-6 修正 — ABI calldataload オフセット計算 (引数ごとに +32)
Step 4 (残存): ABI 戻り値エンコード (MSTORE + RETURN) を sol_codegen に追加
Step 5 (残存): sol_evm Assembler で生成したバイトコードの連結・検証
```

---

## 第2マイルストーン以降（優先度順）

| 優先度 | タスク |
|---|---|
| 高 | `sol_sema`: FunctionCall / MemberAccess の型解決 |
| 高 | `sol_codegen`: for/while 文のコード生成 |
| 高 | `sol_codegen`: 状態変数 SLOAD/SSTORE |
| 中 | `sol_sema`: 型検査の全式対応 (FunctionCall, MemberAccess …) |
| 中 | `sol_codegen`: emit / revert / コンストラクタ |
| 中 | `sol_abi`: tuple エンコード / ABI デコード |
| 低 | `sol_yul`: Yul パーサ (インライン assembly の完全サポート) |
| 低 | `sol_yul`: オプティマイザ (定数畳み込み / DCE / インライン展開) |
| 低 | `sol_abi`: NatSpec / メタデータ JSON |
| 低 | `sol_cli`: `--remappings` / `--base-path` |
