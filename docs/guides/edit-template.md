# テンプレートを直す

「タグを調べる → 検証する → 保存する → 1枚だけ再構築する」です。AI の記憶だけにタグ名を任せず、その MT で実際に使えるタグを `template_tag_list` で確認します。

詳細と注意は [tools.md のテンプレート節](../tools.md#ai-にテンプレートを作らせる) です。

## AI にこう頼む

```
このブログのインデックステンプレートを一覧して。
トップの HTML を少し直したいので、該当を取得してから
構文チェックして、問題なければ保存して 1 枚だけ再構築して。
サイト全体の再構築はしないで。
```

新規のインデックスを足す場合:

```
記事タイトルを直近 5 件出すインデックステンプレートを作って。
outfile は latest.html。保存前に validate と preview して。
```

## 実際に呼ばれるツール

```
blog_list
template_list / template_get
template_tag_list(keyword="...")
template_validate
template_preview   → ファイルは書かない
template_create または template_update
rebuild_template
```

アーカイブテンプレートはマップが無いと `rebuild_template` が失敗します。必要なら `templatemap_create` を挟みます。

## チェックポイント

- `template_validate` が通ってから保存している。
- インデックステンプレートに `outfile` がある（空のままだと、そのサイトの `rebuild_entry` や `rebuild_site` まで失敗しうる）。
- 反映は `rebuild_template` のあと。保存しただけでは公開ファイルは変わらない。

## 注意

- 書き込みと preview には「テンプレートの編集」権限が必要です。
- `template_delete` は取り消せません。
- ウィジェットセットの中身は `template_update` の `body` では組めません。`widgetset_*` を使います。
