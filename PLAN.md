# sol_pkgs — 実装状況と今後のプラン

最終更新: 2026-06-22

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
| **宣言 vs 式の曖昧性解消 (`_speculate`: 投機的パース + 診断抑制でバックトラック)** | ✅ |
| **NatSpec (`///` / `/** */`) を宣言に添付 (`AstNode.documentation`)** | ✅ |
| テスト (10件通過) | ✅ |

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
| 値型に値等価 (`==`/`hashCode`: Int/Address/BytesN/Array/Mapping/Tuple) | ✅ |
| **有理数リテラル型 (`RationalNumberType`: 約分・mobile 型解決・int/fixed 変換)** | ✅ |
| **`FixedType` / `UFixedType` (固定小数点 `fixedMxN`/`ufixedMxN`)** | ✅ |
| テスト (26件通過) | ✅ |

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
| **mapping/配列のインデックスアクセス型 (`m[k]`→値型, `a[i]`→要素型)** | ✅ |
| **グローバルメンバの型 (`msg.sender`→address, `block.timestamp`→uint256 等)** | ✅ |
| **共有ユーティリティ `solTypeFromTypeName` / `elementarySolType`** | ✅ |
| **FunctionCall の型解決 (関数シンボルから返り値型を引く / TupleType 対応)** | ✅ |
| **MemberAccess の型解決 (array/bytes/string の `.length` → uint256)** | ✅ |
| **override 整合性チェック / 可視性チェック / pure/view ルール (`ContractChecker`)** | ✅ |
| **未使用変数の警告 / 循環 import 検出 (`ImportGraph`)** | ✅ |
| テスト (45件通過) | ✅ |

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
| **バイトコードリンカ (`BytecodeLinker`: `__$<keccak[:17]>$__` placeholder 解決)** | ✅ |
| テスト (12件通過) | ✅ |

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
| **Yul パーサ (`YulParser`: object/block/let/if/switch/for/関数定義/break/continue/leave)** | ✅ |
| **複数返り値関数 (M>1) のホイスト (`_emitLeave`: SWAP1..SWAPM bubble+rotate)** | ✅ |
| **Yul オプティマイザ (`YulOptimizer`: 定数畳み込み / 代数簡約 / DCE)** | ✅ |
| テスト (45件通過) | ✅ |

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
| **mapping ストレージ (`m[k]` = `keccak256(k . slot)`, ネスト対応) の読み書き** | ✅ |
| **グローバルメンバ (`msg.sender`→caller, `msg.value`, `block.timestamp` 等)** | ✅ |
| **`emit Event(...)` → `log{n}` (topic0 = keccak署名, indexed→topic, それ以外→data)** | ✅ |
| **`revert CustomError(args)` → セレクタ + ABI 引数エンコード** | ✅ |
| **コンストラクタ本体の実行 (デプロイコードで state 初期化, 引数なし)** | ✅ |
| **`public` 状態変数の getter 自動生成 (スカラ / mapping / 配列)** | ✅ |
| 値型契約を最小EVMで実行検証 (ERC20風: constructor/transfer/event/error/getter) | ✅ |
| テスト (7件 codegen + 58件 driver 実行検証) | ✅ |
| **動的配列の `.length` (sload) / `.push(x)` / `.pop()` (Panic 0x31 on empty)** | ✅ |
| **コンストラクタ引数 (creation calldata `calldataload(add(codesize(), i*32))`)** | ✅ |
| **`&&`・`||` の短絡評価 (`_preStmts` リフト機構 + Yul if ブロック)** | ✅ |
| **`**` の桁あふれチェック (指数二乗法 + checked_mul で Panic 0x11)** | ✅ |
| string/bytes (動的型) の ABI エンコード/デコード・ストレージ | ✅ |
| 固定長配列の複数スロット割当 (現状 1 スロット/変数) / struct | ✅ |

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
| **ABI エンコード: tuple/struct (`TupleType` を再帰的に encode)** | ✅ |
| **ABI デコード (`AbiDecoder`: uint/int/bool/address/bytes/string/array/tuple)** | ✅ |
| **NatSpec タグ解析 (`NatSpec`) + devdoc/userdoc 生成 (`DocGenerator`)** | ✅ |
| **メタデータ JSON (`MetadataGenerator`: compiler/output/settings/sources+keccak)** | ✅ |
| テスト (24件通過) | ✅ |

---

### `sol_driver` ✅ 完成度: 中〜高

| 機能 | 状態 |
|---|---|
| `CompilerStack.addSource` / `compile` パイプライン | ✅ |
| `CompilationResult` / `ContractOutput` データ構造 (devdoc/userdoc/metadata 付き) | ✅ |
| standard-JSON 入出力 (abi/ir/bytecode/devdoc/userdoc/metadata) | ✅ |
| `deployedBytecode` (ランタイム/デプロイ分離 — `generateDeployed`) | ✅ |
| **import 解決 (複数ファイル — `_resolveImports` による推移的解決)** | ✅ |
| **`ContractChecker` 統合 (mutability/visibility/override/未使用変数)** | ✅ |
| **循環 import 警告 (`ImportGraph`)** | ✅ |
| **`settings.optimizer` フラグ (`CompilerStack(optimize:)` → `YulOptimizer`)** | ✅ |
| テスト (58件通過 — うち多数は最小EVMでの実行検証) | ✅ |

---

### `sol_cli` 🟡 完成度: 高 (フロントエンドのみ)

| 機能 | 状態 |
|---|---|
| `--bin` / `--abi` / `--ir` / `--standard-json` / `--version` / `--help` | ✅ |
| ファイル複数指定 | ✅ |
| `dart run sol_cli:solc` エントリポイント | ✅ |
| **`--optimize` / `--remappings` / `--base-path` / `--include-path` (フラグ追加)** | ✅ |
| **テスト (7件通過)** | ✅ |

---

### `sol_web3` ✅ 完成度: 中〜高 (NEW — フルパイプラインの「最後の1マイル」)

`sol_driver` が生成するバイトコードを実際のチェーンに乗せるための、純Dart製
Ethereum JSON-RPC クライアント・トランザクション署名・デプロイ機能。secp256k1/
ECDSA/RLP/JSON-RPC をすべて自前実装し、`sol_support` の keccak256 以外の追加依存
なし（solc/web3.js/Node.js 不要）。

| 機能 | 状態 |
|---|---|
| `codec.dart`: hex/bytes/BigInt 相互変換 (JSON-RPC quantity encoding 含む) | ✅ |
| **secp256k1 楕円曲線演算** (`ECPoint`: 加算・倍加・スカラー倍, アフィン座標) | ✅ |
| **ECDSA 署名** (`signEcdsa`: CSPRNG ノンス, low-s 正規化 EIP-2 準拠) | ✅ |
| **公開鍵/アドレスリカバリ** (`recoverPublicKey`/`recoverEthAddress`: `p≡3 mod 4` 平方根トリック) | ✅ |
| `EthPrivateKey` (鍵範囲検証・アドレス導出) / `EthAddress` (EIP-55 チェックサム) | ✅ |
| **RLP エンコード/デコード** (`rlpEncode`/`rlpDecode`/`rlpUint`, 短/長 string・list 全パターン) | ✅ |
| **`EthereumTransaction`**: legacy (EIP-155 リプレイ防止) + EIP-1559 (動的フィー) 署名/エンコード | ✅ |
| `JsonRpcClient` (`dart:io HttpClient` ベース JSON-RPC 2.0、`package:http` 不使用) | ✅ |
| `EthereumClient`: `eth_chainId`/`getTransactionCount`/`gasPrice`/`maxPriorityFeePerGas`/`estimateGas`/`sendRawTransaction`/`getTransactionReceipt` 等の型付きラッパー | ✅ |
| **`ContractDeployer.deploy()`**: nonce/フィー取得 → ガス推定(+20%) → 署名 → 送信 → レシート polling → revert 検出 | ✅ |
| `computeCreateAddress` (CREATE アドレス: `keccak256(rlp([sender, nonce]))[12:]`) | ✅ |
| テスト (57件通過 — ローカル `HttpServer` でノードを模した E2E デプロイシミュレーション含む) | ✅ |
| CREATE2 アドレス算出 / `eth_getLogs` (イベントログ取得・デコード) | ✅ |
| WebSocket subscription (`eth_subscribe`) — 対応は HTTP request/response のみ | ❌ |
| RFC 6979 決定的ノンス — 意図的に CSPRNG を採用 (HMAC/SHA-256 実装を増やさないため) | ❌ (意図的) |

> **重要な注意点**:
> 1. secp256k1/ECDSA は `sol_pkgs` 全体の方針通り「タイミング攻撃に対する
>    定数時間性を考慮しない、検証目的のリファレンス実装」。本番資産を扱う鍵管理には
>    audited なライブラリ (libsecp256k1 等) を使うべき。
> 2. 実チェーン（テストネット/メインネット）への実送信は本サンドボックスでは未検証
>    — ネットワークアクセスや資金提供済みアカウントがないため。`test/deploy_loopback_test.dart`
>    でローカル `HttpServer` を実ノード代わりに立て、署名・RLP・JSON-RPC往復・nonce/ガス取得・
>    レシート polling・CREATE アドレス算出までを一通り検証しているが、これは実ノードとの
>    互換性を保証するものではない。
> 3. B-34 (下記) の通り、楕円曲線の field prime 定数を手書き16進数リテラルで持つことの
>    危険性が実証された。`secp256k1P` は閉形式の式 (`2^256 - 2^32 - 977`) で定義し、
>    今後同種の定数を追加する場合も可能な限り閉形式 or 外部検証可能な形を優先すること。

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
| B-27 | `sol_parser/parser.dart` | `arr[i] = v;` 等が型名 (`Foo[] x;`) と誤認され「Expected identifier」で失敗 → `_speculate` で投機的に宣言を試し、失敗時は診断を捨てて式文へバックトラック | 2026-06-18 |

## 実装した未実装機能（B-28〜B-33: 実コントラクト対応）

| # | 場所 | 内容 | 実装日 |
|---|---|---|---|
| B-28 | `sol_codegen` + `sol_sema` | **mapping ストレージ**: `m[k]` を `keccak256(k . slot)` で読み書き、ネスト mapping も合成。型システムが mapping/配列の要素型を解決 | 2026-06-18 |
| B-29 | `sol_codegen` + `sol_yul` | **グローバルメンバ**: `msg.sender`→`caller()`, `msg.value`→`callvalue()`, `block.*`/`tx.*` を対応オペコードへ | 2026-06-18 |
| B-30 | `sol_codegen/ir_generator.dart` | **`emit Event(...)`**: topic0 = keccak署名 (compile-time), indexed→topic, それ以外→ABIエンコードして `log{n}` | 2026-06-18 |
| B-31 | `sol_codegen/ir_generator.dart` | **`revert CustomError(args)`**: 4バイトセレクタ + ABI 引数をメモリに置いて revert | 2026-06-18 |
| B-32 | `sol_codegen/ir_generator.dart` | **コンストラクタ本体**: デプロイコードで実行し state を初期化 (引数なし)。helper をオブジェクト別にスコープ | 2026-06-18 |
| B-33 | `sol_codegen/ir_generator.dart` | **`public` 状態変数の getter 自動生成**: スカラ/mapping/配列。署名からセレクタを算出 | 2026-06-18 |

> B-28〜B-33 により、**コンストラクタ・残高 mapping・`Transfer` イベント・カスタムエラー・
> getter を持つ ERC20 風トークン**が、実行可能な creation/runtime バイトコードまで通る。
> `sol_driver/test/evm_exec_test.dart` に creation コードを実行して constructor の storage 反映・
> transfer・ログ topic・revert を検証するテストを追加 (driver 計 30 件)。

> B-20〜B-25 はいずれも「コンパイルは通るが実行時に誤った/壊れたバイトコード」を生む
> 静かな正確性バグ。`sol_driver/test/evm_exec_test.dart` に overflow revert / unchecked wrap /
> 符号付き比較・除算 / `require`・`assert`・`revert` / キャストの実行検証を追加して回帰を固定。

## 実装した未実装機能（F-1〜F-7: 周辺機能の完成, 2026-06-19）

| # | パッケージ | 内容 |
|---|---|---|
| F-1 | `sol_types` | **有理数リテラル型** (`RationalNumberType`: 約分・mobile 型解決) と **固定小数点型** (`FixedType`/`UFixedType`)。値型に値等価を追加 |
| F-2 | `sol_evm` | **バイトコードリンカ** (`BytecodeLinker`): solc ≥0.5.0 の `__$<keccak[:17]>$__` placeholder を解決 |
| F-3 | `sol_yul` | **Yul パーサ** (`YulParser`: 字句解析+再帰下降)。インライン assembly / object をパース |
| F-4 | `sol_yul` | **複数返り値関数 (M>1) のホイスト**: `_emitLeave` を SWAP1..SWAPM の bubble+rotate で一般化。MiniEvm 実行で検証 |
| F-5 | `sol_yul` + `sol_driver` + `sol_cli` | **Yul オプティマイザ** (`YulOptimizer`: 定数畳み込み/代数簡約/DCE) と `settings.optimizer` フラグ連携 |
| F-6 | `sol_abi` + `sol_parser` + `sol_ast` | **NatSpec → devdoc/userdoc** (`NatSpec`/`DocGenerator`) と **メタデータ JSON** (`MetadataGenerator`)。パーサが `///`・`/** */` を宣言へ添付 |
| F-7 | `sol_sema` + `sol_driver` | **pure/view・可視性・override チェック** (`ContractChecker`)、**未使用変数警告**、**循環 import 検出** (`ImportGraph`) |

> F-4 は `sol_driver/test/evm_exec_test.dart` に手書き Yul の複数返り値関数 (identity/swap/
> 3-return/early-leave) を MiniEvm で実行するテストを追加して正当性を固定。F-5 の DCE は当初
> 終端後のホイスト関数定義まで除去して「Invalid jump destination 0」を誘発したため、関数定義
> (とそれを含む文) は到達不能でも保持するよう修正済み。テスト総数 187 → 263 件。

## 解決済みバグ（B-34〜B-35: sol_web3 実装中に発見）

| # | 場所 | 内容 | 修正日 |
|---|---|---|---|
| B-34 | `sol_web3/lib/src/crypto/secp256k1.dart` | `secp256k1P`（楕円曲線の field prime）の手書き16進数リテラルが2桁欠落（64桁中62桁）→ 素数ではない誤った法で楕円曲線演算が実行され、生成元 `G` 自身が曲線方程式を満たさず、ランダム鍵では `BigInt.modInverse` が断続的に `Not coprime` 例外を投げる/誤ったアドレスを導出する。閉形式の式 `2^256 - 2^32 - 977` に置換して修正 — 20,000件のランダムスカラーによる曲線所属ブルートフォース検証、および Node.js `crypto.createECDH('secp256k1')` による公開鍵の独立クロスチェックの両方で正しさを確認 | 2026-06-19 |
| B-35 | `sol_web3/test/transaction_test.dart` | EIP-155 `v` 検証テストが同じハッシュを2回（`key.sign(hash)` と `tx.sign(key)`）独立に署名し、両者の `recoveryId` が一致することを期待 → 署名はランダムノンス（RFC 6979 不使用）のため約50%の確率で `recoveryId` が異なり間欠的に失敗（`melos test` で実際に再現: `Expected: 62709, Actual: 62710`）。`tx.sign(key)` 側の実際の署名から `recoveryId` を逆算し、それで `recoverEthAddress` がキーのアドレスに一致することを検証する形に変更（二重署名を排除）→ 25回連続実行で再現せず | 2026-06-19 |

> B-34 は手で書いた暗号定数を目視レビューだけで信用してはならないことを直接示した例。
> 64桁の16進数リテラルから2文字欠落しても読んだだけでは気づけないが、結果は「動くことも
> あるが時々壊れる」という最悪のクラスの不正確さ（鍵によって発覚するかどうかが変わる）
> になる。`secp256k1P` は自己検証可能な閉形式の式で表現し、今後同種の定数を追加する場合も
> 可能な限り閉形式または外部ツールでクロスチェック可能な形を優先すること。同セッションでは
> 副次的に、テストフィクスチャ内の Hardhat 秘密鍵（末尾1桁欠落）と受信者アドレス
> （末尾1バイト欠落）という2件の独立した転記ミスも同じ検証プロセス中に発見・修正した。
> B-35 はバグの種類が異なる: ライブラリのコードは最初から正しく、`melos test` を
> 一度実行しただけでは気づけない間欠的なテストの誤りだった。「テストが通った」を
> 1回のグリーンランで判断せず、ランダム性に依存するテストは複数回実行して安定性を
> 確認すべきという教訓。

## 残存バグ（未修正）

| # | 場所 | 内容 |
|---|---|---|
| B-36 | `sol_codegen/ir_generator.dart:1127` | 呼び出し対象が `Identifier` でない関数呼び出し (`super.foo()` / `this.foo()` など `MemberAccess` 経由の呼び出し) が未対応 → エラーではなく警告を出して呼び出し式全体をリテラル `0` に置き換える。副作用（state 変更・イベント発行等）が静かに消える「コンパイルは通るが壊れたバイトコードを生む」クラスの正確性バグ。詳細・再現コードは下記「CLI でコンパイル → チェーンへアップロードは可能か」セクション参照 |

継承メンバー解決の未実装（`is` 継承した関数・状態変数が派生コントラクトから参照できない）は
B-36 と関連するが「バグ」ではなく未実装機能のため、下記の新規セクションで個別に説明する。
それ以外の未実装機能は各パッケージ表の ❌ を参照。

---

## テスト通過状況 (2026-06-19 現在)

| パッケージ | テスト数 | 状態 |
|---|---|---|
| sol_support | 14 | ✅ 全通過 |
| sol_lexer | 13 | ✅ 全通過 |
| sol_ast | 2 | ✅ 全通過 |
| sol_types | 26 | ✅ 全通過 |
| sol_parser | 10 | ✅ 全通過 |
| sol_sema | 45 | ✅ 全通過 |
| sol_abi | 24 | ✅ 全通過 |
| sol_codegen | 7 | ✅ 全通過 |
| sol_evm | 12 | ✅ 全通過 |
| sol_yul | 45 | ✅ 全通過 |
| sol_driver | 58 | ✅ 全通過 (うち多数は最小EVMでの実行検証) |
| sol_cli | 7 | ✅ 全通過 |
| sol_web3 | 57 | ✅ 全通過 (ローカル HttpServer での E2E デプロイ検証含む) |
| **合計** | **320** | **✅ 全通過** |

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
チェック付き算術・符号付き演算・`require`/`assert`/`revert`・明示的型変換・`unchecked`**、
さらに **mapping ストレージ・イベント・カスタムエラー・コンストラクタ・public getter**
を実装し、**ERC20 風トークン**が実行可能な creation/runtime バイトコードになることを
最小EVMでの実行テスト (26件) で確認済み。

| 優先度 | タスク | 状態 |
|---|---|---|
| 高 | `sol_codegen`: for/while/do-while 文のコード生成 | ✅ |
| 高 | `sol_codegen`: 状態変数 SLOAD/SSTORE + 代入 | ✅ |
| 高 | `sol_codegen`: チェック付き算術 + `unchecked` (0.8 セマンティクス) | ✅ |
| 高 | `sol_codegen`: 符号付き比較・除算・シフト (slt/sgt/sdiv/sar) | ✅ |
| 高 | `sol_codegen`: `require`/`assert`/`revert` + 明示的型変換 | ✅ |
| 高 | `sol_sema`: シンボルへの実型割当 (符号情報を codegen へ伝播) | ✅ |
| 高 | `sol_codegen`: mapping ストレージ (keccak slot) + グローバルメンバ | ✅ |
| 高 | `sol_codegen`: emit (イベント/ログ) / コンストラクタ本体 / public getter | ✅ |
| 高 | `sol_codegen`: `revert CustomError(args)` のセレクタ付きデータ | ✅ |
| 高 | `sol_sema`: FunctionCall / MemberAccess の完全な型解決 | ✅ |
| 中 | `sol_codegen`: 動的配列の length/push/pop / string・bytes / struct | ✅ (length/push/pop ✅ / string・bytes ✅ / struct ✅) |
| 中 | `sol_codegen`: コンストラクタ引数 (creation calldata デコード) | ✅ |
| 中 | `sol_codegen`: `&&`・`||` の短絡評価 / `**` の桁あふれチェック | ✅ |
| 中 | `sol_abi`: tuple エンコード / ABI デコード | ✅ |
| 低 | `sol_driver`: import 解決 (複数ファイル) | ✅ |
| 低 | `sol_cli`: `--remappings` / `--base-path` / `--include-path` / テスト | ✅ |
| 低 | `sol_driver`/`sol_cli`: `settings.optimizer` フラグ → `YulOptimizer` 駆動 | ✅ |
| 低 | `sol_types`: `RationalNumberType` / `FixedType` / `UFixedType` | ✅ |
| 低 | `sol_evm`: バイトコードリンカ (library placeholder) | ✅ |
| 低 | `sol_sema`: pure/view・可視性・override チェック / 未使用変数 / 循環 import | ✅ |
| 低 | `sol_yul`: Yul パーサ (`YulParser`) | ✅ |
| 低 | `sol_yul`: 複数返り値関数 (M>1) のホイスト | ✅ |
| 低 | `sol_yul`: オプティマイザ (定数畳み込み / 代数簡約 / DCE) | ✅ |
| 低 | `sol_abi`: NatSpec (devdoc/userdoc) / メタデータ JSON | ✅ |
| 低 | `sol_codegen`: string・bytes (動的型) / struct / 固定長配列の複数スロット | ✅ |
| 低 | `sol_yul`: オプティマイザのインライン展開 | ✅ |

---

## コントラクト検証 (Contract Verification) について

**現状: 未対応。** Etherscan/Sourcify 等での「ソース検証」は、提出したソースを
**公式 solc が再コンパイルしたバイトコードと一致**することを確認する仕組みであり、
本コンパイラはそれを満たせない。理由:

1. **バイトコードが solc 互換でない** — 本実装は独自の Yul 下げ・ディスパッチャ・
   スタック割当を持つため、同じソースでも solc と異なるバイト列になる
   (`YulOptimizer` は追加したが solc の最適化パイプラインとは別物)。
2. **メタデータ JSON は生成するが CBOR ハッシュは未付与** — `MetadataGenerator` が
   solc 互換の metadata JSON (compiler/language/output[abi/devdoc/userdoc]/settings/
   sources+keccak256) を生成するようになった。ただし solc のように CBOR エンコードして
   バイトコード末尾へ埋め込む処理は未実装 (`metadata.bytecodeHash: none`)。
3. **standard-json 出力は abi/ir/bytecode/devdoc/userdoc/metadata まで対応** —
   残るは sourceMap (デバッグ情報) と、デプロイ済みバイトコードの厳密一致。

→ 「自前で出した bytecode と deployedBytecode が再現可能か」という意味での
   self-consistency は満たす（決定的に同じ出力を生成する）が、**第三者の検証
   サービスと突き合わせる検証は不可**。対応には (a) メタデータ CBOR のバイトコード埋め込み、
   (b) sourceMap 生成、(c) solc 互換の最適化・コード配置、が最低限必要。

---

## CLI でコンパイル → チェーンへアップロードは可能か (2026-06-22 検証)

`mise` で Dart 3.12.2 を導入し `melos bootstrap` した上で `sol_cli` を実際に
実行して検証した結果。

### 結論

| やりたいこと | 状態 |
|---|---|
| `solc` CLI で Solidity ソースをコンパイル (bytecode/ABI/IR) | ✅ 可能 |
| コンパイル結果をチェーンにデプロイ（アップロード） | ❌ CLI 非対応。`sol_web3` のライブラリ API を呼ぶ Dart コードが別途必要 |
| OpenZeppelin の `ERC20` を継承するようなコントラクトのコンパイル | ❌ 不可（継承メンバーの名前解決・コード生成が未実装） |

### 1. コンパイル単体は CLI で完結する

```sh
dart run sol_cli:solc --bin Adder.sol      # EVM バイトコード
dart run sol_cli:solc --abi Adder.sol      # ABI JSON
dart run sol_cli:solc --ir  Adder.sol      # Yul IR
echo '{...}' | dart run sol_cli:solc --standard-json
```

`sol_cli`(`packages/sol_cli/bin/solc.dart` → `solc` コマンド) は `sol_driver` の
`CompilerStack` を呼ぶだけの薄いラッパーで、継承を使わない自己完結コントラクトなら
ここまでは正真正銘ワンライナーで完結する。

### 2. チェーンへのデプロイは CLI 化されていない

`sol_web3` の `pubspec.yaml` には `bin/` も `executables:` もなく、提供しているのは
`ContractDeployer` / `EthereumClient` / `EthPrivateKey` などの **Dart ライブラリ
API** のみ。`solc --deploy` のような1コマンドでの送信は存在しない。実際に送るには
[`packages/sol_web3/example/full_pipeline_example.dart`](packages/sol_web3/example/full_pipeline_example.dart)
のような Dart スクリプトを書いて `dart run` する必要がある:

```dart
final stack = CompilerStack()..addSource('Adder.sol', source);
final bytecode = stack.compile().contracts['Adder']!.bytecode;

final client = EthereumClient(Uri.parse('http://127.0.0.1:8545'));
final result = await ContractDeployer(client).deploy(
  credentials: EthPrivateKey.fromHex(privateKeyHex),
  bytecode: bytecode,
);
```

実テストネット/メインネットへの送信はこのリポジトリ内では未検証
（ネットワークアクセスがない開発環境のため）。ローカル `HttpServer` を使った
E2E テスト (`sol_web3/test/deploy_loopback_test.dart`) のみで検証済み。

### 3. 実際に検証: OpenZeppelin 風 ERC20 継承は現状コンパイルできない

以下のような、OpenZeppelin の `ERC20` を import して継承するコントラクトを
最小再現で試した:

```solidity
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract EconomyCoin is ERC20 {
    constructor() ERC20("EconomyCoin", "ECO") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
```

これは独立した2つの理由でコンパイルできない。

**(a) `@openzeppelin/contracts/...` の import はそもそも解決されない。**
`sol_driver` の `CompilerStack._resolveImports`(`compiler_stack.dart:77-95`) は、
import 文字列と `addSource()` に渡したキーが**完全一致**した場合のみソースを
リンクする。ディスクから相対パスでファイルを読みにいく処理も、npm 風パスを
解決する処理もない。`sol_cli` は `--remappings` / `--base-path` /
`--include-path` フラグを **引数として受け付けるだけ** で、
`compiler_command.dart` 内のロジックはパース結果を一切参照していない
(`sol_cli/test/cli_test.dart` のテストも「入力ファイルが無いので exit code 1」
としか検証しておらず、解決ロジック自体はテストされていない)。加えて
OpenZeppelin のソース自体もこのリポジトリには存在しない（vendoring なし）。

**(b) 継承メンバーの名前解決・コード生成が未実装。**
`sol_sema/resolver.dart` の `visitContractDefinition` は `node.members`
（コントラクト自身が宣言したメンバー）だけをスコープに登録し、
`node.baseContracts`（基底コントラクトのリスト）には一切アクセスしない。
`baseContracts` を参照しているのは `sol_ast`（パース/AST 構造と visitor）と
`sol_sema/contract_checker.dart`（override 整合性チェック）のみで、
名前解決 (`Resolver`) とコード生成 (`sol_codegen/ir_generator.dart`) には
継承の概念が存在しない。import 問題を避けて単一ファイルで最小再現しても
同様に失敗する:

```solidity
contract Base {
    uint256 public x;
    function setX(uint256 v) public { x = v; }
}
contract Derived is Base {
    function callSetX() public { setX(42); }   // public でも継承先から見えない
}
```

```
$ dart run sol_cli:solc --bin Derived.sol
ERROR at 0:214:4: Undeclared identifier "setX"
```

`callSetX` を削除して `contract Derived is Base {}` だけにしても実害は同じで、
生成される `Derived` の ABI は空 (`[]`) になる — `sol_codegen`/`sol_abi` も
基底コントラクトの関数・public state variable getter を派生コントラクトの
ディスパッチャ/ABI へマージしないため、継承された関数は呼び出せない状態で
デプロイされることになる。`super.setX(42)` のように明示的に親を指定しても
結果は変わらない。呼び出し対象が `Identifier` でない式（`MemberAccess` 経由の
呼び出し全般）は `ir_generator.dart:1127` で **警告**を出すだけでコンパイル
自体は継続し、呼び出し式がリテラル `0` に置き換わって副作用ごと消える
(B-36 として上記「残存バグ」に記録)。

> `sol_sema` の C3 多重継承線形化 (`c3_lineariser.dart`) は
> `contract_checker.dart` の override 整合性チェックにのみ使われている。
> `contract X is Y` は構文として受理され override 検査も機能するが、
> **継承メンバーの実際の参照・継承の「実体化」（フラット化）は未実装**。

### まとめ

- 継承を使わない自己完結コントラクトなら、CLI コンパイルまでは現状でも問題なく
  動く（`Adder`/`Counter`/最小 ERC20 風コントラクトを1ファイルにベタ書きする等)。
- `is` 継承を使うコントラクト — まさに OpenZeppelin の `ERC20` を継承する
  今回のサンプルコードのパターン — は **import 解決・名前解決・コード生成の
  3段階すべてにギャップがあり、コンパイル不可**。
- チェーンへのデプロイは常に CLI 非対応で、`sol_web3` を呼ぶ Dart コードが必要。
  実ネットワークへの送信はこのリポジトリ内では未検証。
- 継承を実際に使えるようにするには、最低限 (1) `sol_sema/resolver.dart` が
  C3 線形化順序で基底コントラクトのメンバーを派生コントラクトのスコープに
  マージする、(2) `sol_codegen` が継承された関数を派生コントラクトの
  ディスパッチャ/ABI に含める（オーバーライドされていれば派生側を優先する）、
  (3) `super.foo()` のような `MemberAccess` 呼び出しに対応する、
  (4) ファイルシステム上のパス解決・remapping を実装する、の4点が必要。
