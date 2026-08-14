# 画像を記事に貼る

画像をアセットとして上げ、記事本文から参照する流れです。拡張子・サイズの制限は [asset_upload の注意](../tools.md#asset_upload-の注意点) です。

## AI にこう頼む

```
このブログに hero.png をアップロードして。
返ってきた URL を、下書き記事「オンボーディング確認」の本文先頭に img で入れて。
まだ公開しないで。
```

一覧から探す場合:

```
最近上げた画像アセットを一覧して、ファイル名に hero を含むものを教えて。
```

## 実際に呼ばれるツール

```
blog_list
asset_upload   → Base64 の data とファイル名
asset_thumbnail（任意） → 縮小 URL
entry_create または entry_update
  → 本文にアセットの URL を書く
```

公開する場合は [記事を作る](create-entry.md) と同じく `status=publish` のあと **`rebuild_entry`** です。

## チェックポイント

- 管理画面のアイテムにファイルがある。
- 下書き記事の本文に URL が入っている。公開は再構築後。

## 注意

- `asset_delete` は取り消せません。消す前に `asset_get` または `asset_list` で確認してください。
- 許可されない拡張子（実行可能ファイルや `.svg` など）はエラーになります。
- アップロード先はブログの `site_path` 配下（既定は `mcp-uploads/`）です。書き込み権限が必要です。
