# mt-mcp

Movable Type 9 用の MCP (Model Context Protocol) サーバープラグイン。  
Cursor・Claude Desktop などの MCP クライアントから MT を自然言語で直接操作できます。

## 対応ツール

| ツール名 | 説明 |
|---|---|
| `blog_list` | ブログ（サイト）一覧取得 |
| `entry_list` | 記事一覧取得 |
| `entry_get` | 記事1件取得（本文含む） |
| `entry_create` | 記事作成（デフォルト: 下書き） |
| `entry_update` | 記事更新 |
| `category_list` | カテゴリ一覧取得 |
| `tag_list` | タグ一覧取得 |
| `asset_list` | アセット一覧取得 |
| `asset_get` | アセット1件取得 |
| `template_list` | テンプレート一覧取得 |
| `template_get` | テンプレート1件取得（本文含む） |
| `template_update` | テンプレート本文更新 |

### AI の操作フロー

`blog_id` が必要なツールを呼ぶ前に、AI は自動で `blog_list` を使ってブログIDを確認します。  
そのため、ユーザーは「〇〇ブログに記事を追加して」のように自然文で指示するだけで動作します。

```
ユーザー: 「テスト記事を追加して」
AI:       blog_list → blog_id を確認
          → entry_create(blog_id, title="テスト記事", status="draft")
```

## 動作環境

- Movable Type 9
- Apache 2.4+ (CGI または mod_perl)
- Perl 5.x (`JSON` モジュール)

## インストール

```bash
cp -r plugins/MTMCP /path/to/mt/plugins/
```

## 設定

### 1. API トークンの設定

MT 管理画面 > システム > プラグイン > **MT MCP Server** > 設定  
**API Token** に任意のトークン文字列を入力して保存します。

### 2. Apache 設定

`Authorization` ヘッダーを CGI に渡すために `CGIPassAuth On` が必要です。  
VirtualHost の `<Directory>` ブロックに追加してください。

```apache
<Directory "/var/www/html/mt">
    CGIPassAuth On
    # ...既存の設定...
</Directory>
```

## エンドポイント

MT の Data API 経由でリクエストを受け付けます。

```
POST https://example.com/mt/mt-data-api.cgi/v4/mcp
```

| ヘッダー | 値 |
|---|---|
| `Content-Type` | `application/json` |
| `Authorization` | `Bearer <api-token>` |

## MCP クライアント設定

### Cursor (`~/.cursor/mcp.json`)

```json
{
  "mcpServers": {
    "movable-type": {
      "type": "http",
      "url": "https://example.com/mt/mt-data-api.cgi/v4/mcp",
      "headers": {
        "Authorization": "Bearer <your-api-token>"
      }
    }
  }
}
```

### Claude Desktop (`claude_desktop_config.json`)

```json
{
  "mcpServers": {
    "movable-type": {
      "type": "http",
      "url": "https://example.com/mt/mt-data-api.cgi/v4/mcp",
      "headers": {
        "Authorization": "Bearer <your-api-token>"
      }
    }
  }
}
```

## 疎通確認

### initialize（接続確認）

```bash
curl -X POST https://example.com/mt/mt-data-api.cgi/v4/mcp \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <your-api-token>' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"curl","version":"0.0.1"}}}'
```

成功レスポンス:
```json
{"id":1,"jsonrpc":"2.0","result":{"capabilities":{"tools":{"listChanged":false}},"protocolVersion":"2024-11-05","serverInfo":{"name":"MT MCP Server","version":"0.1.0"}}}
```

### tools/list（ツール一覧確認）

```bash
curl -X POST https://example.com/mt/mt-data-api.cgi/v4/mcp \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <your-api-token>' \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
```

### blog_list（ブログ一覧取得）

```bash
curl -X POST https://example.com/mt/mt-data-api.cgi/v4/mcp \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <your-api-token>' \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"blog_list","arguments":{}}}'
```

### entry_create（記事作成）

```bash
curl -X POST https://example.com/mt/mt-data-api.cgi/v4/mcp \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <your-api-token>' \
  -d '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"entry_create","arguments":{"blog_id":1,"title":"テスト記事","body":"本文です。","status":"draft"}}}'
```

## ディレクトリ構成

```
plugins/MTMCP/
├── config.yaml
└── lib/
    └── MTMCP/
        ├── App.pm          # Data API ハンドラ・認証
        ├── Protocol.pm     # MCP JSON-RPC ディスパッチャ
        └── Tools/
            ├── Blog.pm     # blog_list
            ├── Entry.pm    # entry_list / get / create / update
            ├── Category.pm # category_list / tag_list
            ├── Asset.pm    # asset_list / get
            └── Template.pm # template_list / get / update
```

## トラブルシューティング

| 症状 | 原因 | 対処 |
|---|---|---|
| `401 Unauthorized` | Apache が Authorization ヘッダーを CGI に渡していない | `CGIPassAuth On` を追加 |
| `Unknown endpoint` | プラグインのキャッシュが古い | MT 管理画面でプラグインを無効→有効に切り替え |
| `500 Can't locate JSON/XS.pm` | JSON::XS が未インストール | 不要（本プラグインは `JSON` モジュールを使用） |
| ログイン画面が返る | エンドポイントが `mt.cgi` になっている | `mt-data-api.cgi/v4/mcp` を使用すること |
