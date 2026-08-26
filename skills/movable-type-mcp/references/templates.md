# テンプレート作成のワークフロー

人間向けの同じ手順は `docs/guides/edit-template.md` と `docs/tools.md` の「AI にテンプレートを作らせる」。

MT タグは学習データだけに頼らず、その環境の `template_tag_list` で確認する。

## ループ

```
blog_list
template_list / template_get     → 既存の書き方を見る
template_tag_list(keyword=...)   → 実在するタグ名
（本文を書く）
template_validate                → エラーなら行番号で直して再実行
template_preview                 → ファイルは書かない。必要なら entry_id
template_create または template_update
templatemap_create               → アーカイブでマップが無いとき
rebuild_template                 → 公開ファイルへ反映
```

`skip_validation: true` は通常使わない。検証エラーは自分で直す。

## 種別ごとの必須

- **index**: `outfile`（例: `index.html`）。空のインデックスが1つあるだけで、そのサイトの `rebuild_site` と `rebuild_entry` が失敗する。公開しないなら `build_type: 0`。
- **アーカイブ系**（individual / page / archive / category / author / ct / ct_archive）: `archive_type` か `maps`。無ければ `templatemap_create`。`ct` / `ct_archive` は `content_type_id` 必須。
- **widgetset**: `widgetset_*` で割当。`template_create` の `body` は指定しない。
- **widget / custom**: 単体 `rebuild_template` はできないことが多い。読み込んでいるインデックス/アーカイブを再構築する。

## 公開

保存だけでは公開ファイルは変わらない。反映は `rebuild_template`。サイト全体のデザイン入れ替え以外で `rebuild_site` は使わない。

## 権限

書き込みと `template_preview` は「テンプレートの編集」（`edit_templates`）。構文チェックだけの `template_validate` はブログへのアクセスがあれば足りる。
