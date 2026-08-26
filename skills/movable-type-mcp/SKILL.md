---
name: movable-type-mcp
description: >
  Operate Movable Type via the MT MCP server (blog, entry, page, template,
  content type/data, asset, rebuild). Use whenever the user asks to work with
  Movable Type or MT CMS, when calling mcp__movable-type__* tools, or when
  creating, editing, publishing, or deleting entries, pages, templates, or
  content data. Enforces draft-then-rebuild, the template validate/preview loop,
  scoped rebuilds, and confirm-before-delete.
---

# Movable Type MCP

MT を MCP ツールで操作するときの手順。引数の正本はツールスキーマと、この Skill の [references/tools.md](references/tools.md)。人間向けの同じ内容はリポジトリの `docs/tools.md` / `docs/guides/`。

接続（プラグイン配置・トークン・クライアント）はこの Skill の範囲外。未接続ならユーザーに `docs/getting-started.md` を案内する。サイト CRUD・Stats・バックアップ・データ移行一括は未提供なので作ろうとしない。

## 必ず守る手順

1. **`blog_id` が要るツールの前に `blog_list`。** ID を推測しない。
2. **コンテンツデータは `content_type_get` でフィールド ID と型を確認してから** `content_data_create` / `update`。キーはラベルではなくフィールド ID。
3. **記事・ページ・コンテンツデータの既定は下書き。** 公開まで求められたときだけ `status=publish` にし、続けて対象を絞った再構築を実行する（記事なら `rebuild_entry`、ページなら `rebuild_page`、コンテンツデータなら `rebuild_content_data`）。保存しただけでは公開ファイルは変わらない。
4. **テンプレートは検証ループ。** 詳細は [references/templates.md](references/templates.md)。
5. **インデックステンプレートには `outfile` が必須。** 空だとそのサイトの `rebuild_site` / `rebuild_entry` が壊れる。公開しないなら `build_type: 0`。
6. **`rebuild_site` は最終手段。** まず `rebuild_template` / `rebuild_entry` / `rebuild_page` / `rebuild_content_data`。カテゴリアーカイブだけなど範囲が明確なときだけ `rebuild_site` に `archive_type` を付ける。
7. **削除系は取り消せない。** 実行前に一覧・取得系で対象を提示し、ユーザーの確認を取る。`entry_import` は `confirm: true` が無いと動かない。確認なしで消さない。
8. **権限エラーはリトライしない。** `edit_templates` / `rebuild` / ブログ権限などのメッセージが出たら、ユーザーに MT 側の権限付与または権限のあるユーザーでのトークン再発行を促す。

preview 系（`entry_preview` / `page_preview` / `template_preview`）はビルド結果を返すだけで公開ファイルを書かない。見た目確認に使う。

## 典型フロー

**記事を作って公開して**

`blog_list` →（任意）`entry_preview` → `entry_create(..., status="draft")` → ユーザーが公開を求めたら `entry_update(..., status="publish")` → `rebuild_entry`

**記事一覧テンプレートを作って**

[references/templates.md](references/templates.md) のループ。インデックスなら `outfile` を付ける。サイト全体は再構築しない。

**不要な記事を消して**

`blog_list` → `entry_list` / `entry_get` で候補を提示 → 確認後にだけ `entry_delete`

## 参照（必要なときだけ読む）

- ツール一覧と引数の要点: [references/tools.md](references/tools.md)
- テンプレート作成のワークフロー: [references/templates.md](references/templates.md)
- エラーメッセージ → 対処: [references/troubleshooting.md](references/troubleshooting.md)
