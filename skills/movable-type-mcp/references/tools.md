# ツール一覧と引数の要点

MCP の `inputSchema`（`Protocol.pm`）が実装の正本。人間向けの同じ表はリポジトリの `docs/tools.md`。ここは操作時の要点だけ。

`blog_id` が必要な呼び出しの前に `blog_list`。一覧の `keyword` は DB の LIKE 部分一致。`offset` でページネーション。

## ブログ・記事・ページ

| ツール | 要点 |
|---|---|
| `blog_list` | 引数なし。サイト ID の正本 |
| `entry_list` | `blog_id` 必須。`status`: publish / draft / all。`keyword` / `offset` |
| `entry_get` | `entry_id`。本文付き。Page ID は不可 |
| `entry_create` | `blog_id`, `title`。省略時 `status=draft`。`category_ids` は記事カテゴリのみ（カテゴリセット内 ID は渡さない） |
| `entry_update` | `entry_id`。指定フィールドのみ |
| `entry_delete` | 取り消し不可。確認後。`confirm: true` 必須 |
| `entry_preview` | ファイルは書かない。`blog_id` + `entry_id` または title/body |
| `entry_export` | `entry_id` 必須。Page 不可。バックアップ代替ではない |
| `entry_import` | 破壊的。`confirm: true` 必須。著者は呼び出しユーザー。省略時下書き。再構築しない |
| `page_list` / `page_get` / `page_create` / `page_update` / `page_delete` / `page_preview` | 記事ツールとは別。フォルダは `folder_id`。作成の既定は下書き。公開後は `rebuild_page`。`page_delete` は `confirm: true` 必須 |

## カテゴリ・タグ・フォルダ

| ツール | 要点 |
|---|---|
| `category_list` / `get` / `create` / `update` / `delete` / `permutate` | `category_set_id` 省略時は記事カテゴリ。セット内は指定必須。`permutate` は当該スコープの全 ID 完全一致 |
| `category_set_*` | セット削除は配下カテゴリも消える。CT の `categories` フィールドが参照していてもコアは止めない。削除前に `content_type_get` |
| `tag_list` / `tag_rename` / `tag_delete` | rename/delete は取り消し不可。`tag_delete` は `confirm: true` 必須 |
| `folder_*` | 固定ページ用。記事カテゴリとは別 |

## アセット

| ツール | 要点 |
|---|---|
| `asset_list` / `asset_get` | `keyword` / `offset` |
| `asset_upload` | Base64 `data` + `file_name`。デコード後 20MB。許可拡張子のみ（`.svg` と実行系は不可）。既定ディレクトリ `mcp-uploads/` |
| `asset_delete` | 取り消し不可。`confirm: true` 必須 |
| `asset_thumbnail` | 画像アセットのサムネイル URL |

## テンプレート・マップ・ウィジェット

詳細手順は [templates.md](templates.md)。

| ツール | 要点 |
|---|---|
| `template_list` / `get` | 本文・outfile・識別子 |
| `template_tag_list` | その MT の実タグ。件数が多いので `keyword` 必須に近い |
| `template_validate` | 保存しない。行番号付きエラー |
| `template_preview` | ファイルは書かない。記事コンテキストが要る型は `entry_id` |
| `template_create` / `update` | 保存前に自動検証。index は `outfile` 必須。アーカイブ系は `archive_type` か `maps`。widgetset の body は不可 |
| `template_delete` | 取り消し不可。`confirm: true` 必須 |
| `templatemap_*` | アーカイブの URL/出力。無いと `rebuild_template` が失敗。マップ保存時は自動再構築しない |
| `widgetset_*` / `widget_list` | セット割当は `widget_ids` 全置換。`template_update` の body では組めない |

## 再構築

| やりたいこと | ツール |
|---|---|
| テンプレ1枚 | `rebuild_template`（`template_id`） |
| 記事 | `rebuild_entry`（`entry_id`。既定で依存アーカイブも） |
| 固定ページ | `rebuild_page` |
| コンテンツデータ | `rebuild_content_data` |
| 特定アーカイブだけ | `rebuild_site` + `archive_type` |
| 全体 | `rebuild_site`（タイムアウトしうる。最後） |

再構築には MT の「サイトの再構築」権限（`rebuild`）。ウィジェット/モジュール単体は `rebuild_template` できない。

## コンテンツタイプ・データ（MT7 以降）

| ツール | 要点 |
|---|---|
| `content_type_list` / `get` / `create` | get でフィールド ID・型。`type: categories` には `category_set_id` 必須 |
| `content_data_list` / `get` / `create` / `update` / `delete` | `fields` のキーはフィールド ID。作成の既定は下書き。公開後は `rebuild_content_data` |

## ログ・ユーザー

| ツール | 要点 |
|---|---|
| `log_list` / `log_get` | 読み取りのみ。「ログの閲覧」。`blog_id` 省略または 0 は権限範囲のシステム全体 |
| `user_list` / `get` / `create` / `update` / `delete` / `unlock` / `recover_password` | システム権限「ユーザーとグループの管理」。パスワード直接変更はしない。ロール付与は管理画面 |

## 権限の目安

| 操作 | 権限 |
|---|---|
| テンプレ書き込み / preview / マップ書き込み / ウィジェットセット書き込み | `edit_templates` |
| 再構築 | `rebuild` |
| ページ / フォルダ | `manage_pages`（フォルダは save/delete_folder） |
| `entry_preview` | `create_post` |
| `entry_export` / `entry_import` | `export_blog` / `import_blog` |
| ユーザー | `can_manage_users_groups` |

権限エラーは同じツールを繰り返さず、ユーザーに権限かトークンのユーザーを変えてもらう。
