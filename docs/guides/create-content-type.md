# コンテンツタイプを作る / コンテンツデータを投入する

MT7 以降のコンテンツタイプを定義し、その型にデータを入れる流れです。フィールド ID を推測せず、**必ず `content_type_get` で確認してから** `content_data_create` します。

一覧と権限は [tools.md のコンテンツタイプ節](../tools.md#コンテンツタイプコンテンツデータmt7以降) です。

## AI にこう頼む

まだ型が無い場合:

```
このブログに「お知らせ」というコンテンツタイプを作って。
フィールドはタイトル（1行テキスト）と本文（複数行テキスト）でよい。
```

既存の型にデータを入れる場合:

```
「お知らせ」コンテンツタイプのフィールド定義を確認してから、
タイトル「メンテ告知」、本文「明日 2 時から」のデータを下書きで追加して。
まだサイト全体は再構築しないで。
```

公開する場合:

```
いま作ったコンテンツデータを公開して、そのデータだけ再構築して。
```

## 実際に呼ばれるツール

型を新規作成:

```
blog_list
  → blog_id
content_type_list
  → 同名が無いか確認
content_type_create(blog_id, name, fields)
```

`fields` を省略すると、タイトル（`single_line_text`）と本文（`multi_line_text`）が付きます。`type: categories` のフィールドには `category_set_id` が必須です。セットは先に `category_set_create` します。記事の `category_ids` とは別物です。

データを投入:

```
content_type_list  → content_type_id
content_type_get   → 各フィールドの id と型
content_data_create(
  content_type_id,
  blog_id,
  status="draft",
  fields={ "<フィールドID>": "値", ... }
)
```

`fields` のキーはラベルではなく **フィールド ID** です。`content_type_get` の結果をそのまま使ってください。

公開するとき:

```
content_data_update(..., status="publish")
rebuild_content_data
```

`rebuild_site` は使いません。

## チェックポイント

- 管理画面のコンテンツタイプ一覧に名前が出る。
- データは下書きなら公開アーカイブに出ない。公開＋`rebuild_content_data` のあと、対応アーカイブが更新される。

## 注意

- `content_data_delete` と `category_set_delete` は取り消せません。セット削除は配下カテゴリも消えます。コンテンツタイプがセットを参照していても MT コアは止めません。消す前に `content_type_get` で `category_set_id` を確認してください。
- フィールド ID を間違えると、別フィールドに値が入るかエラーになります。作成・更新のたびに `content_type_get` を挟むのが安全です。
