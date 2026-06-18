# sol_pkgs — 実装状況と今後のプラン

最終更新: 2026-06-18

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
| `keccak256` (純Dart実装, Ethereum版 0x01 サフィックス) | ✅ |
| テスト (14件通過 — keccak ベクタ含む: 空/"abc"/transfer=a9059cbb/approve=095ea7b3) | ✅ |

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
| **シンボルに実型を割当 (パラメータ/戻り値/ローカル/状態変数を宣言型名から解決)** | ✅ |
| **数値リテラルの型適応 (`int256 x` に対し `x - 1` を許可)・シフトは左辺型** | ✅ |
| **明示的型変換 `T(x)` の結果型注釈 (`visitTypeConversion`)** | ✅ |
| **共有ユーティリティ `solTypeFromTypeName` / `elementarySolType`** | ✅ |
| テスト (30件通過) | ✅ |
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
| `pushDeployedOffset()` — 連結ランタイムの開始オフセット解決 (`dataoffset` 用) | ✅ |
| 2パスのオフセット計算修正 (JUMP=4バイト / JUMPDEST=1バイト) | ✅ |
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
| 組み込み void 関数 (mstore/sstore/log*/pop/return 等) の POP 抑制 | ✅ |
| サブオブジェクト連結 (creation コード + ランタイムコード) / `generateDeployed` | ✅ |
| `dataoffset` / `datasize` の解決 (デプロイラッパからランタイム参照) | ✅ |
| 関数の返り値個数を記録 (void 関数呼び出しの余分な POP を防止) | ✅ |
| `let` 宣言のフレーム二重カウント修正 / `leave` でローカルを掃除 | ✅ |
| テスト (17件通過) | ✅ |
| Yul パーサ (`assembly { … }` ブロック) | ❌ |
| 複数返り値関数 (M>1) のホイスト | ❌ |
| Yul オプティマイザ | ❌ |

---

### `sol_codegen` ✅ 完成度: 高 (値型コントラクトを Solidity ≥0.8 セマンティクスで実行可能なバイトコードに)

| 機能 | 状態 |
|---|---|
| デプロイメントコード (codecopy + return, dataoffset/datasize 解決) | ✅ |
| ABI ディスパッチャ (switch on selector) | ✅ |
| 関数定義 → Yul 関数変換 (`return` → `leave` 含む) | ✅ |
| パラメータ/戻り値のスロット名整合 (`var_<name>` で本体から参照可能) | ✅ |
| 関数セレクタ = keccak256(canonical signature)[:4] (`sol_abi` 共有) | ✅ |
| ABI パラメータデコード (引数 `i` → `calldataload(4 + i*32)`) | ✅ |
| ABI 戻り値エンコード (MSTORE 連続 + `return(0, M*32)`) | ✅ |
| `if` / `for` / `while` / `do-while` / `break` / `continue` 文 | ✅ |
| 状態変数のスロット割当 + 読み (`sload`) / 書き (`sstore`) | ✅ |
| 代入 (`=`) / 複合代入 (`+=` 等) / 前置・後置 `++`・`--` | ✅ |
| 二項演算子 全対応 (`!=`/`<=`/`>=` は `iszero` 合成, シフトは引数順補正) | ✅ |
| 単項演算子 (`!` / `~` / 単項 `-` / 単項 `+`) | ✅ |
| **チェック付き算術 (Solidity ≥0.8): `+`/`-`/`*` が桁あふれで `Panic(0x11)` revert** | ✅ |
| **`unchecked { … }` ブロック内ではラップ (raw `add`/`sub`/`mul`)** | ✅ |
| **符号付き整数の比較 (`slt`/`sgt`)・除算 (`sdiv`/`smod`)・右シフト (`sar`)** | ✅ |
| **ゼロ除算/剰余 → `Panic(0x12)` / 符号付き `MIN/-1` → `Panic(0x11)`** | ✅ |
| **`require(c)` / `require(c, "msg")` (`Error(string)` エンコード) / `assert(c)` (`Panic(0x01)`)** | ✅ |
| **`revert()` / `revert("msg")`** | ✅ |
| **明示的型変換 (`uintN(x)`/`intN(x)`/`address(x)`): マスク / `signextend`** | ✅ |
| 値型契約を最小EVMで実行検証 (overflow revert / unchecked wrap / 符号付き / require / cast) | ✅ |
| テスト (7件 codegen + 23件 driver 実行検証) | ✅ |
| `emit` (イベント/ログ) / コンストラクタ本体 | ❌ |
| `revert CustomError(args)` のセレクタ付きデータ (今は bare revert) | ❌ |
| 動的型 (string/bytes/動的配列/mapping) の ABI・ストレージ対応 | ❌ |
| `&&`・`||` の短絡評価 (値は正しいが副作用は常に評価) | ❌ |
| `**` の桁あふれチェック | ❌ |

---

### `sol_abi` ✅ 完成度: 中〜高

| 機能 | 状態 |
|---|---|
| `function` / `event` / `error` エントリの ABI JSON 生成 | ✅ |
| ABI エンコード: uint/int/bool/address/bytes1〜32/bytes/string/T[]/T[N] | ✅ |
| 正準型名 / シグネチャ / 4バイトセレクタ (`abi_signature.dart`, keccak256 利用) | ✅ |
| 型エイリアス正規化 (`uint`→`uint256`, `address payable`→`address` 等) | ✅ |
| `event` の `indexed` フラグ (`Parameter.indexed` を反映) | ✅ |
| 固定長配列の ABI 型文字列 (`uint256[3]` — 長さリテラル評価) | ✅ |
| テスト (7件通過) | ✅ |
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
| `deployedBytecode` (ランタイム/デプロイ分離 — `generateDeployed`) | ✅ |
| テスト (8件通過 — 最小EVMで実行し戻り値を検証: Adder/Counter/Loop/比較) | ✅ |
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

## 解決済みバグ（B-4〜B-6 追加）

| # | 場所 | 内容 | 修正日 |
|---|---|---|---|
| B-4 | `sol_yul/yul_codegen.dart` | `YulIdentifier` が常に `PUSH0` — `_Frame` + DUP(depth) で修正 | 2026-06-17 |
| B-5 | `sol_codegen/ir_generator.dart` | 関数セレクタが `hashCode` プレースホルダ → 純Dart keccak256 で実セレクタ計算 | 2026-06-18 |
| B-6 | `sol_codegen/ir_generator.dart` | `calldataload` オフセット固定値 `4` → 引数 `i` ごとに `4 + i*32` | 2026-06-18 |
| B-14 | `sol_codegen/ir_generator.dart` | パラメータ/戻り値スロット名が本体参照 (`var_<name>`) と不一致でバイトコード生成が失敗 → スロット名を整合 | 2026-06-18 |
| B-15 | `sol_yul/yul_codegen.dart` | `return(...)` が非 void 扱いで `RETURN` 後にデッドコード `POP` 混入 → void 集合に追加 | 2026-06-18 |
| B-16 | `sol_evm/assembler.dart` | pass1 が JUMP を 3 バイトと誤計算 (実際は PUSH2+2+JUMP=4) → 全ジャンプ先がずれる | 2026-06-18 |
| B-17 | `sol_evm/assembler.dart` | pass1 が `JUMPDEST` バイト(ラベル1バイト)を数えず、ラベル後のジャンプ先がずれる | 2026-06-18 |
| B-18 | `sol_yul/yul_codegen.dart` | `let x := e` がフレームを二重 push しローカルの DUP 深さが破綻 → 匿名スロットをリネーム | 2026-06-18 |
| B-19 | `sol_yul/yul_codegen.dart` | void 関数呼び出しが返り値 1 個を仮定し余分な POP でアンダーフロー → 返り値個数を記録 | 2026-06-18 |

> B-16〜B-19 は「バイトコードを実際に EVM 実行する」テスト (`sol_driver/test/evm_exec_test.dart`) を
> 追加して初めて顕在化した。生成物の構造検証だけでは捕捉できない実行時バグだった。

## 解決済みバグ（B-20〜B-26: Solidity ≥0.8 セマンティクス対応）

| # | 場所 | 内容 | 修正日 |
|---|---|---|---|
| B-20 | `sol_codegen/ir_generator.dart` | `unchecked { … }` がコード生成で握り潰され本体が消失 → `UncheckedStatement` を処理しブロックを生成 | 2026-06-18 |
| B-21 | `sol_codegen/ir_generator.dart` | `+`/`-`/`*` に桁あふれチェックがなく 0.8 のチェック付き算術と不一致 → 型幅・符号別の `checked_*` ヘルパで `Panic(0x11)` revert、`unchecked` 内は raw | 2026-06-18 |
| B-22 | `sol_codegen/ir_generator.dart` | 符号付き整数で常に無符号オペコード (`lt`/`gt`/`div`/`shr`) → 型注釈から `slt`/`sgt`/`sdiv`/`smod`/`sar` を選択 | 2026-06-18 |
| B-23 | `sol_codegen/ir_generator.dart` | `require`/`assert` が存在しない `fun_require` 等へジャンプ (offset 0 へ暴走) → 組み込みとして lower (`Error(string)` / `Panic(0x01)` エンコード) | 2026-06-18 |
| B-24 | `sol_codegen/ir_generator.dart` | `revert(...)` 文 (`RevertStatement`) がコード生成で握り潰され消失 → revert を生成 | 2026-06-18 |
| B-25 | `sol_codegen/ir_generator.dart` | 明示的型変換 `T(x)` (`TypeConversion`) が `0` を生成 → マスク/`signextend` で正しく変換 | 2026-06-18 |
| B-26 | `sol_sema/{resolver,type_checker}.dart` | 全シンボルが `ErrorType` で型情報が下流に流れず → 宣言型名から実型を割当。併せて数値リテラルの型適応 (`int256 - 1` の偽陽性エラー) とシフト左辺型を修正 | 2026-06-18 |

> B-20〜B-25 はいずれも「コンパイルは通るが実行時に誤った/壊れたバイトコード」を生む
> 静かな正確性バグ。`sol_driver/test/evm_exec_test.dart` に overflow revert / unchecked wrap /
> 符号付き比較・除算 / `require`・`assert`・`revert` / キャストの実行検証を追加して回帰を固定。

## 残存バグ（未修正）

なし（既知のバグはすべて修正済み。未実装機能は各パッケージ表の ❌ を参照）。

---

## テスト通過状況 (2026-06-18 現在)

| パッケージ | テスト数 | 状態 |
|---|---|---|
| sol_support | 14 | ✅ 全通過 |
| sol_lexer | 13 | ✅ 全通過 |
| sol_ast | 2 | ✅ 全通過 |
| sol_types | 11 | ✅ 全通過 |
| sol_parser | 7 | ✅ 全通過 |
| sol_sema | 30 | ✅ 全通過 |
| sol_abi | 7 | ✅ 全通過 |
| sol_codegen | 7 | ✅ 全通過 |
| sol_evm | 7 | ✅ 全通過 |
| sol_yul | 17 | ✅ 全通過 |
| sol_driver | 23 | ✅ 全通過 (うち19件は最小EVMでの実行検証) |
| **合計** | **138** | **✅ 全通過** |

---

## 第1マイルストーン: Adder.sol をバイトコードまで通す ✅ 完了

```
Step 1 (完了): B-4 修正 — Yul 変数のスタックスロット管理 (_Frame + DUP/SWAP)
Step 2 (完了): B-5 修正 — 純Dart keccak256 (sol_support) でセレクタ計算
Step 3 (完了): B-6 修正 — ABI calldataload オフセット計算 (引数 i → 4 + i*32)
Step 4 (完了): ABI 戻り値エンコード (MSTORE + return(0, M*32)) を sol_codegen に追加
Step 5 (完了): サブオブジェクト連結 (creation + runtime) と dataoffset/datasize 解決
```

`CompilerStack` で `Adder.sol` が実バイトコードまでコンパイルされることを E2E テストで検証済み:

```
contract Adder {
  function getSum(uint256 a, uint256 b) public pure returns (uint256) { return a + b; }
}
```

生成されるランタイムコード (70 bytes) の逆アセンブル要点:

```
5f 35 60 e0 1c           shr(224, calldataload(0))   ; セレクタ抽出
63 8e86b125 14 15 ...     case 0x8e86b125 (getSum)    ; keccak256 由来の実セレクタ
60 24 35 / 60 04 35       calldataload(36/4)          ; 引数 b / a を個別デコード
80 5f 52                  mstore(0, ret)              ; 戻り値を ABI エンコード
60 20 5f f3              return(0, 32)                ; 32 バイト返却
5f 5f fd                  revert(0, 0)                ; セレクタ不一致
```

creation コード (11 bytes) は `codecopy` + `return` でランタイムを返し、`dataoffset`=11
(=デプロイコード長), `datasize`=70 (=ランタイム長) が正しく解決される。

---

## 第2マイルストーン以降（優先度順）

第2マイルストーン（ループ・状態変数・代入・演算子）に加え、**Solidity ≥0.8 の
チェック付き算術・符号付き演算・`require`/`assert`/`revert`・明示的型変換・`unchecked`**
を実装し、値型コントラクトが**正しいセマンティクスの実行可能バイトコード**になることを
最小EVMでの実行テスト (19件) で確認済み。

| 優先度 | タスク | 状態 |
|---|---|---|
| 高 | `sol_codegen`: for/while/do-while 文のコード生成 | ✅ |
| 高 | `sol_codegen`: 状態変数 SLOAD/SSTORE + 代入 | ✅ |
| 高 | `sol_codegen`: チェック付き算術 + `unchecked` (0.8 セマンティクス) | ✅ |
| 高 | `sol_codegen`: 符号付き比較・除算・シフト (slt/sgt/sdiv/sar) | ✅ |
| 高 | `sol_codegen`: `require`/`assert`/`revert` + 明示的型変換 | ✅ |
| 高 | `sol_sema`: シンボルへの実型割当 (符号情報を codegen へ伝播) | ✅ |
| 高 | `sol_sema`: FunctionCall / MemberAccess の型解決 | ❌ |
| 中 | `sol_codegen`: emit (イベント/ログ) / コンストラクタ本体 | ❌ |
| 中 | `sol_codegen`: mapping / 配列 / struct のストレージレイアウト | ❌ |
| 中 | `sol_codegen`: `&&`・`||` の短絡評価 / `**` の桁あふれチェック | ❌ |
| 中 | `sol_codegen`: `revert CustomError(args)` のセレクタ付きデータ | ❌ |
| 中 | `sol_abi`: tuple エンコード / ABI デコード | ❌ |
| 低 | `sol_yul`: Yul パーサ (インライン assembly の完全サポート) | ❌ |
| 低 | `sol_yul`: オプティマイザ (定数畳み込み / DCE / インライン展開) | ❌ |
| 低 | `sol_abi`: NatSpec / メタデータ JSON | ❌ |
| 低 | `sol_cli`: `--remappings` / `--base-path` | ❌ |

---

## コントラクト検証 (Contract Verification) について

**現状: 未対応。** Etherscan/Sourcify 等での「ソース検証」は、提出したソースを
**公式 solc が再コンパイルしたバイトコードと一致**することを確認する仕組みであり、
本コンパイラはそれを満たせない。理由:

1. **バイトコードが solc 互換でない** — 本実装は独自の Yul 下げ・ディスパッチャ・
   スタック割当を持ち、最適化器もないため、同じソースでも solc と異なるバイト列になる。
2. **メタデータハッシュ未付与** — solc はバイトコード末尾に CBOR エンコードした
   メタデータ (ipfs/bzzr ハッシュ + コンパイラバージョン) を付ける。検証はこれに依存するが
   本実装は未生成 (`sol_abi`: メタデータ JSON が ❌)。
3. **standard-json の入出力が部分的** — 検証 API は standard-json 互換の
   入力/出力 (bytecode, deployedBytecode, sourceMap, metadata) を要求するが、
   sourceMap・metadata 等が未実装。

→ 「自前で出した bytecode と deployedBytecode が再現可能か」という意味での
   self-consistency は満たす（決定的に同じ出力を生成する）が、**第三者の検証
   サービスと突き合わせる検証は不可**。対応には (a) メタデータ CBOR 生成、
   (b) sourceMap 生成、(c) solc 互換の最適化・コード配置、が最低限必要。
