# mt-mcp

Movable Type 9 用の MCP (Model Context Protocol) サーバープラグイン。  
Cursor・Claude Desktop などの MCP クライアントから MT を自然言語で直接操作できます。

## 対応ツール

### ブログ・記事

| ツール名 | 説明 |
|---|---|
| `blog_list` | ブログ（サイト）一覧取得 |
| `entry_list` | 記事一覧取得（`keyword` 部分一致検索・`offset` ページネーション対応） |
| `entry_get` | 記事1件取得（本文含む） |
| `entry_create` | 記事作成（デフォルト: 下書き） |
| `entry_update` | 記事更新 |
| `entry_delete` | 記事削除 |
| `category_list` | カテゴリ一覧取得 |
| `tag_list` | タグ一覧取得 |

### アセット・テンプレート

| ツール名 | 説明 |
|---|---|
| `asset_list` | アセット一覧取得（`keyword` 部分一致検索・`offset` ページネーション対応） |
| `asset_get` | アセット1件取得 |
| `asset_upload` | ファイルアップロード（Base64）による新規アセット作成 |
| `asset_delete` | アセット削除 |
| `asset_thumbnail` | 画像アセットのサムネイルURL取得（MTの動的リサイズ機能を利用） |
| `template_list` | テンプレート一覧取得（`keyword` 部分一致検索・`offset` ページネーション対応） |
| `template_get` | テンプレート1件取得（本文含む） |
| `template_create` | テンプレート新規作成 |
| `template_update` | テンプレート本文更新 |
| `template_delete` | テンプレート削除 |

### コンテンツタイプ・コンテンツデータ（MT7以降）

| ツール名 | 説明 |
|---|---|
| `content_type_list` | コンテンツタイプ一覧取得 |
| `content_type_get` | コンテンツタイプ詳細取得（フィールド定義含む） |
| `content_type_create` | コンテンツタイプ新規作成 |
| `content_data_list` | コンテンツデータ一覧取得（`keyword` 部分一致検索・`offset` ページネーション対応） |
| `content_data_get` | コンテンツデータ1件取得（フィールド値・ラベル含む） |
| `content_data_create` | コンテンツデータ作成 |
| `content_data_update` | コンテンツデータ更新（部分更新対応） |
| `content_data_delete` | コンテンツデータ削除 |

> 削除系ツール（`entry_delete` / `asset_delete` / `template_delete` / `content_data_delete`）は取り消せない操作です。AI が実行する前に対象を一覧・取得系ツールで確認するよう促してください。

### AI の操作フロー

`blog_id` が必要なツールを呼ぶ前に、AI は自動で `blog_list` を使ってブログIDを確認します。  
コンテンツデータ操作では `content_type_get` でフィールドIDを確認してから作成・更新を行います。

```
ユーザー: 「テスト記事を追加して」
AI:       blog_list → blog_id を確認
          → entry_create(blog_id, title="テスト記事", status="draft")

ユーザー: 「コンテンツタイプ〇〇にデータを追加して」
AI:       content_type_list → content_type_id を確認
          → content_type_get → フィールドID・型を確認
          → content_data_create(content_type_id, blog_id, fields={...})
```

## 動作環境

- Movable Type 9（コンテンツタイプ機能は MT7 以降）
- Apache 2.4+ (CGI または mod_perl)
- Perl 5.x (`JSON` モジュール)

## セットアップ

### 1. プラグインをインストール

```bash
cp -r plugins/MTMCP /path/to/mt/plugins/
```

MT を再起動（または `touch mt.cgi`）してプラグインを有効化します。

### 2. Apache の設定

`Authorization` ヘッダーを CGI に渡すために以下いずれかが必要です。

**方法 A: VirtualHost / Directory ブロックに追記**
```apache
<Directory "/var/www/html/mt">
    CGIPassAuth On
</Directory>
```

**方法 B: `.htaccess` に追記**（サーバ設定を変更できない場合）
```apache
RewriteEngine On
RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
```

### 3. アクセストークンを発行

トークンの発行方法は2通りあります。どちらで発行しても、そのトークンは**発行したユーザー本人**に紐づき、以後の操作（記事作成の著者、ブログへのアクセス権限など）はそのユーザーとして扱われます。

#### 方法A: ログインAPIで発行（推奨）

MT のユーザー名・パスワードで直接トークンを取得できます。管理画面を開けない CLI や自動化からも利用できます。

```bash
curl -X POST https://example.com/mt/mt-data-api.cgi/v4/mcp/authenticate \
  -H 'Content-Type: application/json' \
  -d '{"username":"your-username","password":"your-password"}'
```

成功レスポンス:
```json
{"access_token":"...","token_type":"Bearer","expires_in":604800,"user_id":3,"username":"your-username"}
```

> 通信は必ず HTTPS 経由で行ってください（平文の HTTP ではパスワードが漏えいします）。パスワード自体は保存されず、照合にのみ使用されます。5回連続で認証に失敗すると、そのユーザー名は15分間ロックされます。

#### 方法B: 管理画面から発行

MT 管理画面で **システム > プラグイン > MT MCP Server** を開き、**設定** タブを選択します。

![MT MCP Server の設定画面 — MCP トークンを発行する](./docs/images/mcp-token-settings.png)

1. **トークンを発行する** ボタンをクリック
2. 表示されたトークンを **コピー** ボタンでコピー
3. 次のステップで MCP クライアントの設定に貼り付け

> どちらの方法も、トークンの有効期限は発行から 7 日間です。再発行しても以前のトークンは即時無効になりません。期限切れの場合は同じ手順で再発行してください。

#### 権限について

各ツールは、トークンに紐づくユーザーがブログへのアクセス権限（MT の Permission）を持っているかを確認します。権限のないブログの記事・アセット・テンプレート・コンテンツデータは操作できません（システム管理者は全ブログを操作可能）。

> 互換性のため、本機能導入前に発行された古い形式のトークンにはユーザーが紐づいていません。その場合は権限チェックをスキップし、従来どおり動作します（`author_id` を省略した場合の記事作成者などはユーザーID 1 にフォールバックします）。新しいトークンを再発行することを推奨します。

### 4. MCP クライアントを設定

#### Cursor (`~/.cursor/mcp.json`)

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

#### Claude Desktop (`claude_desktop_config.json`)

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

## エンドポイント

| メソッド | パス | 役割 |
|---|---|---|
| `POST` | `/mt-data-api.cgi/v4/mcp/authenticate` | ユーザー名・パスワードでログインし、アクセストークンを発行 |
| `GET` | `/mt-data-api.cgi/v4/mcp` | SSE 接続（クライアントが POST 先 URL を受け取る） |
| `POST` | `/mt-data-api.cgi/v4/mcp` | JSON-RPC リクエストの送受信 |

認証ヘッダー（いずれか）：

| ヘッダー | 値 | Apache 設定 | 備考 |
|---|---|---|---|
| `Authorization` | `Bearer <token>` | `CGIPassAuth On` または RewriteRule が必要 | Cursor / Claude Desktop で動作確認済 |
| `X-MT-Authorization` | `MTAuth accessToken=<token>` | 不要 | Apache 設定変更できない環境向け |

## 疎通確認

### initialize（接続確認）

```bash
curl -X POST https://example.com/mt/mt-data-api.cgi/v4/mcp \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <your-token>' \
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
  -H 'Authorization: Bearer <your-token>' \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
```

### blog_list（ブログ一覧取得）

```bash
curl -X POST https://example.com/mt/mt-data-api.cgi/v4/mcp \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <your-token>' \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"blog_list","arguments":{}}}'
```

### entry_create（記事作成）

```bash
curl -X POST https://example.com/mt/mt-data-api.cgi/v4/mcp \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <your-token>' \
  -d '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"entry_create","arguments":{"blog_id":1,"title":"テスト記事","body":"本文です。","status":"draft"}}}'
```

### content_data_create（コンテンツデータ作成）

```bash
# 1. コンテンツタイプ一覧でIDを確認
curl -X POST https://example.com/mt/mt-data-api.cgi/v4/mcp \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <your-token>' \
  -d '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"content_type_list","arguments":{"blog_id":1}}}'

# 2. フィールドID確認
curl -X POST https://example.com/mt/mt-data-api.cgi/v4/mcp \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <your-token>' \
  -d '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"content_type_get","arguments":{"content_type_id":1}}}'

# 3. データ作成
curl -X POST https://example.com/mt/mt-data-api.cgi/v4/mcp \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <your-token>' \
  -d '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"content_data_create","arguments":{"content_type_id":1,"blog_id":1,"status":"draft","fields":{"1":"タイトル","2":"本文"}}}}'
```

## ディレクトリ構成

```
plugins/MTMCP/
├── config.yaml
└── lib/
    └── MTMCP/
        ├── App.pm          # Data API ハンドラ・トークン検証・SSE
        ├── Auth.pm         # ログインAPI（ユーザー名/パスワード → トークン発行）・失敗ロックアウト
        ├── Perm.pm         # ブログ単位の権限チェック
        ├── Protocol.pm     # MCP JSON-RPC ディスパッチャ
        ├── CMS/
        │   └── Token.pm    # 管理画面からのトークン発行
        └── Tools/
            ├── Blog.pm         # blog_list
            ├── Entry.pm        # entry_list / get / create / update / delete
            ├── Category.pm     # category_list / tag_list
            ├── Asset.pm        # asset_list / get / upload / delete / thumbnail
            ├── Template.pm     # template_list / get / create / update / delete
            ├── ContentType.pm  # content_type_list / get / create
            └── ContentData.pm  # content_data_list / get / create / update / delete
```

### asset_upload の注意点

- アップロード先は `blog_id` のブログの `site_path` 配下（デフォルトは `mcp-uploads/` サブディレクトリ）。書き込み権限が必要です。
- `data` には Base64 エンコードしたファイル内容を渡します。
- 画像拡張子（jpg / jpeg / png / gif / bmp / webp / svg）は自動的に画像アセットとして登録され、幅・高さの取得を試みます（MT 側で画像処理バックエンド〈Image::Magick / GD / Imager〉が有効な場合）。
- `asset_thumbnail` は MT の動的サムネイル生成機能を利用するため、同様に画像処理バックエンドの設定が必要です。

## トラブルシューティング

| 症状 | 原因 | 対処 |
|---|---|---|
| `401 Unauthorized` | トークンが無効または期限切れ | MT 管理画面でトークンを再発行 |
| `SSE error: Non-200 status code (404)` | GET エンドポイントが未登録（旧バージョン） | プラグインを最新版に更新し MT を再起動 |
| ツール説明が文字化けする | JSON エンコーダの設定不備（旧バージョン） | プラグインを最新版に更新し MT を再起動 |
| `Unknown endpoint` | プラグインのキャッシュが古い | MT 管理画面でプラグインを無効→有効に切り替え |
| `500 Can't locate JSON/XS.pm` | JSON::XS が未インストール | 不要（本プラグインは `JSON` モジュールを使用） |
| ログイン画面が返る | エンドポイントが `mt.cgi` になっている | `mt-data-api.cgi/v4/mcp` を使用すること |
| `429 Too Many Requests`（ログイン時） | 同一ユーザー名で5回連続認証失敗 | 15分待ってから再試行 |
| ツール呼び出しで `この操作を行う権限がありません` | トークンに紐づくユーザーが対象ブログの権限を持っていない | 対象ブログの権限を持つユーザーでトークンを再発行するか、MT側でブログ権限を付与 |
