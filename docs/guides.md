# 利用ガイド

接続済みの人が、AI に何を頼むかの実例です。ツールの引数・権限の正本は [tools.md](tools.md) です。AI に同じ手順を自動で守らせるパッケージは [Claude Skill](../README.md#5-claude-skill-を入れる推奨)（`skills/movable-type-mcp/`）です。まだ接続していない場合は [getting-started.md](getting-started.md) から始めてください。

## ガイド一覧

| やりたいこと | ガイド |
|---|---|
| 記事を下書きし、必要なら公開する | [記事を作る](guides/create-entry.md) |
| コンテンツタイプを定義し、データを入れる | [コンテンツタイプ / コンテンツデータ](guides/create-content-type.md) |
| テンプレートを調べて直して反映する | [テンプレートを直す](guides/edit-template.md) |
| 画像をアップロードして記事に入れる | [画像を記事に貼る](guides/attach-image.md) |

## AI に任せるときの共通注意

- **削除は取り消せない。** `entry_delete` / `asset_delete` / `template_delete` / `content_data_delete` などを使う前に、一覧・取得系で対象を確認させる。
- **作成の既定は下書き。** `entry_create` は公開しない。公開ファイルを出すにはステータスを公開にしてから、対象を絞った再構築を行う。
- **サイト全体の再構築は最後の手段。** 記事なら `rebuild_entry`、テンプレートなら `rebuild_template`、コンテンツデータなら `rebuild_content_data`。`rebuild_site` は記事数が多いとタイムアウトしうる（[tools.md の再構築](tools.md#再構築の範囲を絞る)）。
