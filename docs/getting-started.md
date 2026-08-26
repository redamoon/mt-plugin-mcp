# はじめての MT MCP

最短で「AI から Movable Type に接続できた」まで進む手順です。分岐は並べず、**推奨ルートを1本**にしています。他の認証方法やクライアントは [README](../README.md) を参照してください。

ツール名の一覧はここには書きません。[docs/tools.md](tools.md) を見てください。接続できたあとの作業例は [利用ガイド](guides.md) です。

## 所要時間と前提

| | |
|---|---|
| 所要時間 | 約 15〜30 分（Apache の再読み込みができる場合） |
| 前提 | Movable Type 9、Apache 2.4+、Perl の `JSON` モジュール |
| Nginx の場合 | この手順のステップは分岐しません。[README の Nginx の場合](../README.md#nginx-の場合) を参照してください |
| 推奨クライアント | Cursor（手動トークン） |
| 推奨トークン | 管理画面から発行（方法 C） |

コンテンツタイプ機能は MT7 以降です。OAuth 自動ログインや Claude Desktop は、この手順で接続できたあとで [README のクライアント設定](../README.md#4-mcp-クライアントを設定) に進んでください。

## ステップ 1. プラグインを入れる

リポジトリの `plugins/MTMCP` を、MT の `plugins/` にコピーします。

```bash
cp -r plugins/MTMCP /path/to/mt/plugins/
```

MT を再起動するか `touch mt.cgi` してプラグインを読み直します。管理画面の **システム > プラグイン** に **MT MCP Server** が出れば成功です。

**ここまでで確認できること:** プラグイン一覧に MT MCP Server がある。

見つからないときは、コピー先が MT 本体の `plugins/` か、パーミッションを確認してください。

## ステップ 2. Apache で Authorization を通す

ツール呼び出し（`/v4/mcp`）には `Authorization: Bearer <token>` が必要です。Apache は既定でこのヘッダーを CGI に渡しません。

VirtualHost または Directory に次を足して、Apache を再読み込みします。

```apache
<Directory "/var/www/html/mt">
    CGIPassAuth On
</Directory>
```

パスは実際の MT インストール先に合わせてください。

サーバ設定を変えられない場合は、`.htaccess` の RewriteRule か、`X-MT-Authorization` ヘッダーがあります。詳細は [README の Apache 設定](../README.md#2-apache-の設定) と [認証アーキテクチャ](architecture-auth.md#ヘッダーと-web-サーバーの関係) です。

Nginx で動かしている場合は、ステップを分岐せず [README の Nginx の場合](../README.md#nginx-の場合) を参照してください。

**ここまでで確認できること:** Apache の設定を保存し、`apachectl configtest`（または同等）が通る。実際のトークン通過は次のステップ以降で確認します。

詰まりやすい点: `CGIPassAuth` を忘れると、トークンを発行できても MCP 呼び出しが 401 になります。

## ステップ 3. アクセストークンを発行する

管理画面で **システム > プラグイン > MT MCP Server > 設定** を開き、**トークンを発行する** を押してコピーします。

![MT MCP Server の設定画面 — MCP トークンを発行する](images/mcp-token-settings.png)

トークンは発行したユーザー本人に紐づきます。以後の記事作成の著者や、触れるブログは、そのユーザーの MT 権限どおりです。有効期限は 7 日です。

**ここまでで確認できること:** トークン文字列を手元にコピーできている。

OAuth（ブラウザログイン）やログイン API は [README のトークン発行](../README.md#3-アクセストークンを発行) です。認証の図は [architecture-auth.md](architecture-auth.md) です。

## ステップ 4. Cursor に接続する

`~/.cursor/mcp.json` に次を書きます。URL のホストとパスは自分の MT に合わせてください。

```json
{
  "mcpServers": {
    "movable-type": {
      "type": "sse",
      "url": "https://example.com/mt/mt-data-api.cgi/v4/mcp",
      "headers": {
        "Authorization": "Bearer <発行したトークン>"
      }
    }
  }
}
```

ポイント:

- パスは **`mt-data-api.cgi/v4/mcp`** です。`mt.cgi` ではありません。`mt.cgi` だとログイン画面が返ります。
- Cursor を再読み込み（または MCP サーバーを再接続）します。

**ここまでで確認できること:** Cursor の MCP 一覧で `movable-type` が接続済みになり、チャットから「ブログ一覧を出して」と頼むと `blog_list` が返る。

curl で同じことを確認する場合は [README の疎通確認](../README.md#疎通確認) です。`initialize` → `tools/list` → `blog_list` の順が分かりやすいです。

## 次にすること

接続できたあと、AI に運用手順（下書き→再構築、テンプレ検証ループ、削除前確認）を守らせるなら [Claude Skill](../README.md#5-claude-skill-を入れる推奨) を入れてください。

- [記事を作る](guides/create-entry.md)
- [コンテンツタイプを作る / データを投入する](guides/create-content-type.md)
- [テンプレートを直す](guides/edit-template.md)
- [画像を記事に貼る](guides/attach-image.md)
- ツール仕様: [tools.md](tools.md)
- プラグインを直す人: [developer-onboarding.md](developer-onboarding.md)

## つまずいたとき

よくあるのは次の2つです。表全体は [README のトラブルシューティング](../README.md#トラブルシューティング) です。

| 症状 | まず疑うこと |
|---|---|
| 401 | トークン期限切れ、またはステップ 2 の `CGIPassAuth` 漏れ（Nginx なら [README](../README.md#nginx-の場合)） |
| ログイン画面が返る | URL が `mt.cgi` になっている。`mt-data-api.cgi/v4/mcp` にする |
| 権限エラー | トークンのユーザーがそのブログを操作できない |

削除系ツール（`entry_delete` など）は取り消せません。公開は下書き保存だけでは足りず、対象を絞った再構築（記事なら `rebuild_entry`）が必要です。サイト全体の `rebuild_site` はタイムアウトしうるので、普段は使いません。
