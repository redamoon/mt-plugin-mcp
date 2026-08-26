# エラーメッセージ → 対処

接続・Web サーバー（401、CGIPassAuth、Nginx の Authorization）は `docs/getting-started.md` と README のトラブルシューティング。ここでは **ツール実行中** の対処。

| メッセージ・症状 | 対処 |
|---|---|
| `この操作を行う権限がありません` | リトライしない。対象ブログの権限を持つユーザーでトークンを出し直すか、MT で権限を付ける |
| `「テンプレートの編集」の権限がありません` | `edit_templates` が無い。権限付与またはトークンのユーザーを変える |
| `「サイトの再構築」の権限がありません` | `rebuild` が無い。同上 |
| `テンプレート構文にエラーがあります` / `<mt:...> with no </mt:...> on line N` | 行番号を見て本文を直す。`template_tag_list` でタグ名を確認。`skip_validation` は使わない |
| `インデックステンプレートには outfile が必要です` | `outfile` を付ける。公開しないなら `build_type: 0` |
| `テンプレート'○○'には出力ファイルの設定がありません` | 既存の空 outfile インデックス。`template_list` で探し、`template_update` で `outfile` か `build_type: 0` |
| `このテンプレート（type: ...）は単体で再構築できません` | ウィジェット/モジュール。それを Include しているインデックス/アーカイブを `rebuild_template` |
| `rebuild_site` が応答しない・504 | 範囲を絞る（`rebuild_template` / `rebuild_entry` / `archive_type`）。または管理画面から再構築 |
| `ブログの公開パス（site_path）が設定されていないため再構築できません` | 管理画面「サイトの設定 > 公開」でサイトパス |
| `Archive type '...' is not a chosen archive type` | そのブログで無効な `archive_type`。外すか有効な型にする |
| `File extension not allowed` | 許可リスト外（実行可能、`.svg` など）。変換してから `asset_upload` |
| `Entry not found`（preview など） | Page ID を記事ツールに渡している。`page_*` を使う |
| 削除・import を急いでいる | 一覧/取得で対象を示して確認。`entry_import` は `confirm: true` なしでは動かない |
| フィールドに値が入らない / 別欄に入る | `content_type_get` を取り直し、`fields` のキーを ID にする |

原因がログに残っているときは `log_list`（`level` / `keyword`）。書き込みはできない。
