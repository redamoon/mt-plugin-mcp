# 対応ツール

Movable Type 9 用 MCP サーバーが公開するツールの一覧と、権限・注意点です。インストールとクライアント設定は [README](../README.md) を参照してください。

ツール定義の正本は `plugins/MTMCP/lib/MTMCP/Protocol.pm` です。


## ブログ・記事

| ツール名 | 説明 |
|---|---|
| `blog_list` | ブログ（サイト）一覧取得 |
| `entry_list` | 記事一覧取得（`keyword` は DB 側 LIKE の部分一致・`offset` ページネーション対応） |
| `entry_get` | 記事1件取得（本文含む） |
| `entry_create` | 記事作成（デフォルト: 下書き） |
| `entry_update` | 記事更新 |
| `entry_delete` | 記事削除（`DeleteFilesAtRebuild` が無効なら公開 HTML が残ることがある） |
| `entry_preview` | 記事を Individual アーカイブとしてビルド（ファイルは書き出さない。`entry_create` 前の見た目確認） |
| `entry_export` | 記事1件を MT Import/Export テキストで返す（`entry_id` 必須。Page 不可。文字数打ち切り。バックアップ代替ではない） |
| `page_list` | 固定ページ一覧（`folder_id` で絞り込み可） |
| `page_get` | 固定ページ1件取得（本文含む） |
| `page_create` | 固定ページ作成（デフォルト: 下書き。フォルダは `folder_id` 単数） |
| `page_update` | 固定ページ更新（`folder_id: 0` でフォルダ解除） |
| `page_delete` | 固定ページ削除（`DeleteFilesAtRebuild` が無効なら公開 HTML が残ることがある） |
| `page_preview` | 固定ページを Page アーカイブとしてビルド（ファイルは書き出さない） |
| `category_list` | カテゴリ一覧（`category_set_id` 省略時は記事カテゴリ。指定時はセット内） |
| `category_get` | カテゴリ1件取得（セット内も含む。フォルダは見つからない） |
| `category_create` | カテゴリ作成（任意の `category_set_id`） |
| `category_update` | カテゴリ更新 |
| `category_delete` | カテゴリ削除（取り消せない） |
| `category_permutate` | カテゴリの表示順変更（当該スコープの全 ID 完全一致） |
| `category_set_list` | カテゴリセット一覧 |
| `category_set_get` | カテゴリセット1件取得（配下カテゴリ含む） |
| `category_set_create` | カテゴリセット作成（サイト内で名前一意） |
| `category_set_update` | カテゴリセット名の更新（カテゴリ配列は不可） |
| `category_set_delete` | カテゴリセット削除（配下カテゴリも消える。取り消せない） |
| `tag_list` | タグ一覧取得（記事・ページ・アセット・コンテンツデータ） |
| `tag_rename` | サイト内のタグ名変更（取り消せない。他サイト利用時は clone＋付け替え） |
| `tag_delete` | サイトからタグを外す（取り消せない。関連オブジェクトから外れる） |
| `folder_list` | フォルダ一覧取得（固定ページ用。記事カテゴリとは別） |
| `folder_get` | フォルダ1件取得 |
| `folder_create` | フォルダ作成 |
| `folder_update` | フォルダ更新 |
| `folder_delete` | フォルダ削除（配下ページは親またはルートへ移る） |

## アセット・テンプレート

| ツール名 | 説明 |
|---|---|
| `asset_list` | アセット一覧取得（`keyword` は DB 側 LIKE の部分一致・`offset` ページネーション対応） |
| `asset_get` | アセット1件取得 |
| `asset_upload` | ファイルアップロード（Base64）による新規アセット作成 |
| `asset_delete` | アセット削除 |
| `asset_thumbnail` | 画像アセットのサムネイルURL取得（MTの動的リサイズ機能を利用） |
| `template_list` | テンプレート一覧取得（`keyword` は DB 側 LIKE の部分一致・`offset` ページネーション対応） |
| `template_get` | テンプレート1件取得（本文・出力ファイル名・識別子・公開方法含む） |
| `template_create` | テンプレート新規作成（保存前に構文を自動検証） |
| `template_update` | テンプレート更新（本文・名前・タイプ・出力設定を部分更新、保存前に構文を自動検証） |
| `template_delete` | テンプレート削除 |
| `template_validate` | テンプレート構文の検証のみ（保存しない・行番号付きエラー） |
| `template_preview` | テンプレートをビルドして出力HTMLを取得（ファイルは書き出さない） |
| `template_tag_list` | その環境で使える MT タグ一覧（プラグイン追加分も含む） |
| `templatemap_list` | テンプレートマップ一覧（アーカイブテンプレートの URL/出力パス） |
| `templatemap_get` | テンプレートマップ1件取得 |
| `templatemap_create` | テンプレートマップ作成（`rebuild_template` の前提） |
| `templatemap_update` | テンプレートマップ更新 |
| `templatemap_delete` | テンプレートマップ削除（静的ファイルは残ることがある） |
| `widgetset_list` | ウィジェットセット一覧（割当順の widgets 付き） |
| `widgetset_get` | ウィジェットセット1件取得 |
| `widgetset_create` | ウィジェットセット作成（`widget_ids` で割当） |
| `widgetset_update` | ウィジェットセット更新（`widget_ids` は全置換） |
| `widgetset_delete` | ウィジェットセット削除（ウィジェット本体は残る） |
| `widget_list` | ウィジェット一覧（`widgetset_id` でセット内・割当順） |

## 再構築（公開）

| ツール名 | 説明 |
|---|---|
| `rebuild_template` | テンプレート1枚を再構築 |
| `rebuild_entry` | 記事1件を再構築（依存アーカイブ・インデックスも既定で再構築） |
| `rebuild_page` | 固定ページ1件を再構築 |
| `rebuild_content_data` | コンテンツデータ1件を再構築 |
| `rebuild_site` | ブログ全体を再構築（`archive_type` で範囲を絞り込み可） |

## ログ（読み取り）

| ツール名 | 説明 |
|---|---|
| `log_list` | アクティビティログ一覧（`level` / 期間 / `keyword` で絞り込み。`blog_id` 省略または `0` は権限範囲のシステム全体） |
| `log_get` | ログ1件取得（`metadata` 含む。list では省略） |

> `log_list` / `log_get` は MT の **「ログの閲覧」** 権限が必要です。システム全体は `view_log`、サイト単位は `view_blog_log`（`view_log` があればサイト指定も可）。作成・更新・削除・リセット・エクスポートはありません。

## ユーザー（システム権限）

| ツール名 | 説明 |
|---|---|
| `user_list` | ユーザー一覧（コメント投稿者は含まない。`keyword` / `status` / `lockout`） |
| `user_get` | ユーザー1件取得（パスワードは返さない） |
| `user_create` | ユーザー作成（作成直後はサイト権限なし。ロールは管理画面） |
| `user_update` | プロフィール更新（表示名・メール・URL・状態。パスワード変更と権限付与はしない） |
| `user_delete` | ユーザー削除（取り消し不可。自分自身は削除不可） |
| `user_unlock` | ログイン失敗ロックの解除 |
| `user_recover_password` | パスワード回復メール送信（新しいパスワードは受け取らない） |

> `user_*` は MT の **「ユーザーとグループの管理」**（`can_manage_users_groups`）が必要です。ブログ編集者トークンではすべて権限エラーになります。サイトへのロール付与・剥奪（grant/revoke）はありません。パスワードの直接変更は `user_recover_password` を使います。作成ユーザーに `system_permissions` は付きません。
>
> 再構築系ツールは MT の **「サイトの再構築」権限**（`rebuild`）を必要とします。`template_create` / `template_update` / `template_delete` / `template_preview` / `templatemap_*` の書き込み / `widgetset_*` の書き込みは **「テンプレートの編集」権限**（`edit_templates`）を必要とします。`page_*` は **「ページの管理」権限**（`manage_pages`）を必要とします。`folder_create` / `folder_update` は `save_folder`、`folder_delete` は `delete_folder`（いずれも `manage_pages` に含まれます）。`entry_preview` は **「記事の作成」権限**（`create_post`）を必要とします。`entry_export` は **「ブログのエクスポート」権限**（`export_blog`）を必要とします（サイトバックアップや移行一括投入の代替ではありません）。記事カテゴリの `category_create` / `category_update` は `save_category`、`category_delete` は `delete_category`、`category_permutate` は `edit_categories`。セット内カテゴリの作成・更新は `save_catefory_set_category`（MT コアの綴り）、削除と `category_set_*` / セットの `category_permutate` は `manage_category_set`。記事カテゴリの変更は公開ファイルを自動再構築しないため、カテゴリアーカイブを出す場合は `rebuild_site` に `archive_type: Category` を指定する。フォルダ操作は `folder_*`（別ツール）。

>
> **記事の `category_ids` にはカテゴリセット内のカテゴリを渡さないこと。** 記事カテゴリは `category_set_id` が 0 のものだけです。セットはコンテンツタイプの `categories` フィールドから参照します。
>
> **`category_set_delete` は配下カテゴリをまとめて消し、コンテンツタイプのフィールドがセットを参照していてもコアは削除を止めません。** 削除前に `content_type_get` で `category_set_id` の参照を確認してください。`content_type_create` で `type: categories` のフィールドには `category_set_id` が必須です。
>
> `template_preview` は任意の本文を MT テンプレートとして評価するため、保存と同等の権限を要求しています。`AllowFileInclude` を有効にしている環境では `<mt:Include file="...">` でサーバー上のファイルを読み出せてしまうためです。構文チェックのみで評価を伴わない `template_validate` はブログへのアクセス権限で実行できます。

## コンテンツタイプ・コンテンツデータ（MT7以降）

| ツール名 | 説明 |
|---|---|
| `content_type_list` | コンテンツタイプ一覧取得 |
| `content_type_get` | コンテンツタイプ詳細取得（フィールド定義含む） |
| `content_type_create` | コンテンツタイプ新規作成 |
| `content_data_list` | コンテンツデータ一覧取得（`keyword` は DB 側 LIKE の部分一致・`offset` ページネーション対応） |
| `content_data_get` | コンテンツデータ1件取得（フィールド値・ラベル含む） |
| `content_data_create` | コンテンツデータ作成 |
| `content_data_update` | コンテンツデータ更新（部分更新対応） |
| `content_data_delete` | コンテンツデータ削除 |

> 削除系ツール（`entry_delete` / `page_delete` / `folder_delete` / `category_delete` / `category_set_delete` / `asset_delete` / `template_delete` / `templatemap_delete` / `widgetset_delete` / `content_data_delete` / `user_delete`）は取り消せない操作です。AI が実行する前に対象を一覧・取得系ツールで確認するよう促してください。

## 権限と注意

各ツールは、トークンに紐づくユーザーがブログへのアクセス権限（MT の Permission）を持っているかを確認します。権限のないブログの記事・アセット・テンプレート・コンテンツデータは操作できません（システム管理者は全ブログを操作可能）。`log_list` / `log_get` はブログアクセスではなく `view_log` / `view_blog_log` を確認します（`blog_id=0` のシステムログも対象）。`user_*` はシステム権限 `can_manage_users_groups` を確認します（ブログ権限の付与・剥奪はできません）。

## AI の操作フロー

`blog_id` が必要なツールを呼ぶ前に、AI は自動で `blog_list` を使ってブログIDを確認します。  
コンテンツデータ操作では `content_type_get` でフィールドIDを確認してから作成・更新を行います。

```
ユーザー: 「テスト記事を追加して」
AI:       blog_list → blog_id を確認
          → entry_preview(blog_id, title="テスト記事", body=...) で見た目確認（公開ファイルは書かない）
          → entry_create(blog_id, title="テスト記事", status="draft")

ユーザー: 「会社概要ページを作って About フォルダに入れて公開して」
AI:       blog_list → folder_list → folder_id を確認
          → page_create(blog_id, title="会社概要", folder_id, status="publish")
          → page_preview で内容確認
          → rebuild_page

ユーザー: 「コンテンツタイプ〇〇にデータを追加して」
AI:       content_type_list → content_type_id を確認
          → content_type_get → フィールドID・型を確認
          → content_data_create(content_type_id, blog_id, fields={...})
```

## AI にテンプレートを作らせる

MT テンプレートは独自のタグ言語で書くため、AI が知識だけで書くと存在しないタグや閉じ忘れが混入しがちです。
本プラグインは「タグを調べる → 検証する → 保存する → 再構築して確認する」というループを AI が自力で回せるように、
以下のツールを組み合わせて使えるようにしています。

```
ユーザー: 「記事一覧を出すインデックステンプレートを作って」
AI:       blog_list          → blog_id を確認
          template_list      → 既存テンプレートの構成を把握
          template_get       → 近いテンプレートの書き方を参考にする
          template_tag_list(keyword="Entry")
                             → 実際に使えるタグ名を確認
          template_validate  → 書いた本文の構文をチェック（エラーなら自分で修正して再実行）
          template_preview   → ビルド結果のHTMLを見て内容を確認
          template_create    → 保存（このとき再度自動検証される。アーカイブ系は archive_type か maps を付ける）
          templatemap_create → マップが無ければ追加（無いと rebuild_template が失敗する）
          rebuild_template   → 公開ファイルに反映
```

ポイント:

- **`template_create` / `template_update` は保存前に必ず構文を検証します。** エラーがあれば保存せず、`<mt:Entries> with no </mt:Entries> on line 12.` のように行番号付きで返します。AI はこのメッセージを読んで自分で修正できます。どうしても検証を通さず保存したい場合のみ `skip_validation: true` を指定してください。
- **`template_tag_list` はその MT 環境で実際に登録されているタグを返します。** プラグインが追加したタグも含まれるため、AI の学習データに無いタグでも正しく扱えます。素の MT 9 で600件以上あるので `keyword` での絞り込みが前提です。
- **`template_preview` はファイルを書き出しません。** 公開中のサイトに影響を与えずに出力を確認できます。`individual` など記事コンテキストが必要なテンプレートは `entry_id` を渡してください。
- **インデックステンプレートには `outfile` が必須です。** MT は出力ファイル名が空のインデックステンプレートを見つけると再構築処理をそこで中断するため、`outfile` の無いテンプレートを1つ作るだけで、そのサイトの `rebuild_site` と `rebuild_entry` がすべて失敗するようになります。これを防ぐため `template_create` / `template_update` が作成時点で弾きます（公開しないテンプレートとして作る場合は `build_type: 0` を指定してください）。
- **保存しただけでは公開ファイルは更新されません。** 反映するには `rebuild_template` を実行します。
- **アーカイブテンプレートにはテンプレートマップが必要です。** `template_create` で `archive_type`（または `maps`）を付けるか、続けて `templatemap_create` してください。マップ保存時の自動再構築はしません。
- **ウィジェットセットの割当は `widgetset_*` です。** `template_update` の `body` ではセットを組めません。

## 再構築の範囲を絞る

MCP は HTTP リクエスト上で動くため、**`rebuild_site`（ブログ全体）は記事数の多いサイトで Web サーバーのタイムアウトに達することがあります。**
まずは対象を絞ったツールを使ってください。

| やりたいこと | 使うツール |
|---|---|
| テンプレートを直したので反映したい | `rebuild_template` |
| 記事を作成・更新したので公開したい | `rebuild_entry` |
| 固定ページを作成・更新したので公開したい | `rebuild_page` |
| コンテンツデータを作成・更新したので公開したい | `rebuild_content_data` |
| 特定のアーカイブだけ作り直したい | `rebuild_site`（`archive_type` を指定） |
| デザイン全体を入れ替えたので全部作り直したい | `rebuild_site` |

`rebuild_site` がタイムアウトする場合は、`archive_type`（`Individual` / `Monthly` / `Category` / `Page` など）で分割して実行するか、MT 管理画面から再構築してください。
なお `rebuild_template` はアーカイブテンプレートに対しても使えます（テンプレートマップで結び付いているアーカイブタイプだけを再構築します）。

## asset_upload の注意点


- アップロード先は `blog_id` のブログの `site_path` 配下（デフォルトは `mcp-uploads/` サブディレクトリ）。書き込み権限が必要です。
- `data` には Base64 エンコードしたファイル内容を渡します。最大サイズは20MB（Base64デコード後）です。
- 許可される拡張子は許可リスト方式です: `jpg` / `jpeg` / `png` / `gif` / `bmp` / `webp` / `ico` / `tif` / `tiff` / `pdf` / `txt` / `csv` / `md` / `doc` / `docx` / `xls` / `xlsx` / `ppt` / `pptx` / `zip` / `mp3` / `mp4` / `mov` / `avi` / `wav` / `ogg` / `webm`。サーバー上で実行され得る拡張子（`.php` / `.cgi` / `.pl` など）や、スクリプトを埋め込める `.svg`（保存型XSSのリスク）は安全のため許可されません。
- 画像拡張子は自動的に画像アセットとして登録され、幅・高さの取得を試みます（MT 側で画像処理バックエンド〈Image::Magick / GD / Imager〉が有効な場合）。
- `asset_thumbnail` は MT の動的サムネイル生成機能を利用するため、同様に画像処理バックエンドの設定が必要です。

## ツール呼び出しの例

接続確認（`initialize` / `tools/list` / `blog_list`）は [README の疎通確認](../README.md#疎通確認) を参照してください。

### entry_create（記事作成）

```bash
curl -X POST https://example.com/mt/mt-data-api.cgi/v4/mcp \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <your-token>' \
  -d '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"entry_create","arguments":{"blog_id":1,"title":"テスト記事","body":"本文です。","status":"draft"}}}'
```

### content_data_create（コンテンツデータ作成）

```bash
# 1. コンテンツタイプ一覧でIDを確認
curl -X POST https://example.com/mt/mt-data-api.cgi/v4/mcp \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <your-token>' \
  -d '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"content_type_list","arguments":{"blog_id":1}}}'

# 2. フィールドID確認
curl -X POST https://example.com/mt/mt-data-api.cgi/v4/mcp \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <your-token>' \
  -d '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"content_type_get","arguments":{"content_type_id":1}}}'

# 3. データ作成
curl -X POST https://example.com/mt/mt-data-api.cgi/v4/mcp \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <your-token>' \
  -d '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"content_data_create","arguments":{"content_type_id":1,"blog_id":1,"status":"draft","fields":{"1":"タイトル","2":"本文"}}}}'
```

### template_validate（テンプレート構文の検証）

```bash
curl -X POST https://example.com/mt/mt-data-api.cgi/v4/mcp \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <your-token>' \
  -d '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"template_validate","arguments":{"blog_id":1,"body":"<mt:Entries lastn=\"5\"><$mt:EntryTitle$>"}}}'
```

閉じタグが無いのでエラーが返る例:
```json
{"valid":false,"errors":[{"message":"<mt:Entries> with no </mt:Entries> on line 1.","line":1}]}
```

### template_tag_list（使えるタグを調べる）

```bash
curl -X POST https://example.com/mt/mt-data-api.cgi/v4/mcp \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <your-token>' \
  -d '{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"template_tag_list","arguments":{"keyword":"EntryTitle"}}}'
```

### rebuild_template（テンプレート1枚の再構築）

```bash
curl -X POST https://example.com/mt/mt-data-api.cgi/v4/mcp \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <your-token>' \
  -d '{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"rebuild_template","arguments":{"template_id":1}}}'
```
