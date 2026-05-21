# mt-mcp

Movable Type 9 用の MCP (Model Context Protocol) サーバープラグイン。  
Cursor・Claude Desktop などの MCP クライアントから MT を直接操作できます。

## 対応ツール

| ツール名 | 説明 |
|---|---|
| `entry_list` | 記事一覧取得 |
| `entry_get` | 記事1件取得 |
| `entry_create` | 記事作成（デフォルト: 下書き） |
| `entry_update` | 記事更新 |
| `category_list` | カテゴリ一覧取得 |
| `tag_list` | タグ一覧取得 |
| `asset_list` | アセット一覧取得 |
| `asset_get` | アセット1件取得 |
| `template_list` | テンプレート一覧取得 |
| `template_get` | テンプレート1件取得（本文含む） |
| `template_update` | テンプレート本文更新 |

## 動作環境

- Movable Type 9
- Apache + mod_perl

## インストール

```bash
cp -r plugins/MTMCP /path/to/mt/plugins/
```

## 設定

1. MT 管理画面 > システム > プラグイン > MT MCP Server > 設定
2. **API Token** に任意のトークン文字列を設定して保存

## エンドポイント

```
POST https://example.com/mt/mt.cgi/mcp
```

## MCP クライアント設定

### Cursor (`~/.cursor/mcp.json`)

```json
{
  "mcpServers": {
    "movable-type": {
      "type": "http",
      "url": "https://example.com/mt/mt.cgi/mcp",
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
      "url": "https://example.com/mt/mt.cgi/mcp",
      "headers": {
        "Authorization": "Bearer <your-api-token>"
      }
    }
  }
}
```

## 疎通確認

```bash
curl -X POST https://example.com/mt/mt.cgi/mcp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <your-api-token>" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
      "protocolVersion": "2024-11-05",
      "capabilities": {},
      "clientInfo": { "name": "curl", "version": "0.0.1" }
    }
  }'
```

## ディレクトリ構成

```
plugins/MTMCP/
├── config.yaml
└── lib/
    └── MTMCP/
        ├── App.pm
        ├── Protocol.pm
        └── Tools/
            ├── Entry.pm
            ├── Category.pm
            ├── Asset.pm
            └── Template.pm
```
