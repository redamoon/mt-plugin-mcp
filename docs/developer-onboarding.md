# 開発者オンボーディング

プラグインを読んで直す人向けです。エージェント（AI）が守る制約は [AGENTS.md](../AGENTS.md) にあり、この文書の代替ではありません。

ユーザー向けの導入は [getting-started.md](getting-started.md)、ツール仕様は [tools.md](tools.md)、認証は [architecture-auth.md](architecture-auth.md) です。

## プラグインの配置

本体は `plugins/MTMCP/` です。開発中は MT の `plugins/MTMCP` へコピーするかシンボリックリンクします。

```
plugins/MTMCP/
├── config.yaml              # Data API ルートと CMS メソッド
└── lib/MTMCP/
    ├── App.pm               # /v4/mcp の SSE・JSON-RPC・トークン検証
    ├── Auth.pm              # POST /v4/mcp/authenticate
    ├── OAuth.pm             # /v4/mcp/token と /register
    ├── Perm.pm              # ブログ権限・システム権限
    ├── Protocol.pm          # ツール名の正本（ディスパッチと JSON Schema）
    ├── Search.pm            # keyword の DB LIKE
    ├── CMS/Token.pm         # 管理画面のトークン発行
    ├── CMS/Authorize.pm     # OAuth consent
    └── Tools/*.pm           # 各ツールの実装
```

エンドポイントの表は [architecture-auth.md](architecture-auth.md#エンドポイント定義) と `config.yaml` が正本です。ツールを足すときは通常 `config.yaml` は触りません（既存の `POST /v4/mcp` が `Protocol.pm` に委譲します）。

## テスト（MT 本体は不要）

`t/lib` のスタブでユニットテストします。本番の MT コアをコピーしないでください。

```bash
prove -I plugins/MTMCP/lib -I t/lib t/*.t
```

個別:

```bash
prove -I plugins/MTMCP/lib -I t/lib t/folder.t t/page.t
```

新しいツールでは、対応する `t/*.t` を足すか更新します。スタブが足りなければ `t/lib/MT/` に最小限のモックを置きます。既存テストとモジュールの対応は [AGENTS.md](../AGENTS.md) の表です。

## ツールを 1 本登録する

実装ファイル（例: `plugins/MTMCP/lib/MTMCP/Tools/Blog.pm`）を置いたうえで、**`Protocol.pm` の 2 箇所**を更新します。片方だけだと `tools/list` に出ないか、呼ぶと `Unknown tool` になります。

1. `%TOOL_HANDLERS` — ツール名 → `Tools::*` の関数

```perl
'blog_list' => sub { require MTMCP::Tools::Blog; MTMCP::Tools::Blog::list(@_) },
```

2. `_tool_definitions()` — MCP の `name` / `description` / `inputSchema`

```perl
{
    name        => 'blog_list',
    description => '...',
    inputSchema => { type => 'object', properties => {} },
},
```

権限チェックは各 `Tools::*` から `MTMCP::Perm` を呼びます。ツール名・権限の説明を変えたら [docs/tools.md](tools.md) も合わせてください。

やってはいけないこと（P3 を勝手に進めない、スカラー `load($id)` を class 混在に使わない、など）は [AGENTS.md](../AGENTS.md) です。

## トークンを取って `/v4/mcp` を叩く

ローカルや検証用 MT にプラグインを入れたあと:

1. Apache で `CGIPassAuth On`（[getting-started.md](getting-started.md) ステップ 2）。Nginx なら [README の Nginx の場合](../README.md#nginx-の場合)
2. 管理画面 **システム > プラグイン > MT MCP Server > 設定** でトークン発行。または `POST /v4/mcp/authenticate`（[README](../README.md#方法b-ログインapiで直接発行非対話自動化向け)）
3. ベース URL は `https://<host>/mt/mt-data-api.cgi/v4/mcp`（`mt.cgi` ではない）

接続確認:

```bash
curl -X POST https://example.com/mt/mt-data-api.cgi/v4/mcp \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <your-token>' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"curl","version":"0.0.1"}}}'
```

成功すると `serverInfo.name` が `MT MCP Server` です。続けて `tools/list` と `blog_list` は [README の疎通確認](../README.md#疎通確認) です。

401 のときはトークン期限（7 日）、`CGIPassAuth`（Nginx なら `HTTP_AUTHORIZATION` / `proxy_set_header Authorization` の欠落）、旧形式トークン（ユーザー未紐づけ）を疑います。シーケンスは [architecture-auth.md](architecture-auth.md) です。
