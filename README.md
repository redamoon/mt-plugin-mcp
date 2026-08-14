# mt-mcp

Movable Type 9 用の MCP (Model Context Protocol) サーバープラグイン。  
Cursor・Claude Desktop などの MCP クライアントから MT を自然言語で直接操作できます。

対応ツールの一覧・権限・操作の注意は [docs/tools.md](docs/tools.md) を参照してください。認証の流れは [docs/architecture-auth.md](docs/architecture-auth.md) です。

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

`Authorization` ヘッダーを CGI に渡すために以下いずれかが必要です。**トークンの取得方法（OAuth / ログインAPI / 管理画面）に関わらず、ツール呼び出し本体（`/v4/mcp`）に `Authorization: Bearer <token>` を渡すために必須**です。OAuthを使う場合でも省略できません。

**設定パターン1: VirtualHost / Directory ブロックに追記**
```apache
<Directory "/var/www/html/mt">
    CGIPassAuth On
</Directory>
```

**設定パターン2: `.htaccess` に追記**（サーバ設定を変更できない場合）
```apache
RewriteEngine On
RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
```

> どちらも設定できない場合は、`Authorization` の代わりに `X-MT-Authorization: MTAuth accessToken=<token>` ヘッダーを使う方法もあります（後述「認証ヘッダー」参照）。カスタムヘッダーは Apache の追加設定なしでそのまま CGI に渡ります。

### 3. アクセストークンを発行

トークンの発行方法は3通りあります。いずれで発行しても、そのトークンは**発行したユーザー本人**に紐づき、以後の操作（記事作成の著者、ブログへのアクセス権限など）はそのユーザーとして扱われます。

#### 方法A: ブラウザログイン（OAuth 2.1 / PKCE、推奨）

MCP クライアント自体にパスワードを一切渡さない方式です。ブラウザで MT の本物のログイン画面（多要素認証や外部認証を設定していればそれも含めて）にログインし、その場で許可した MCP クライアントだけがアクセストークンを受け取れます。

1. ブラウザで下記 URL を開く（`code_verifier` はクライアント側でランダムに生成し、`code_challenge = BASE64URL(SHA256(code_verifier))`）:
   ```text
   https://example.com/mt/mt.cgi?__mode=mcp_authorize
     &response_type=code
     &client_id=my-mcp-client
     &redirect_uri=http://127.0.0.1:PORT/callback
     &state=<ランダム文字列>
     &code_challenge=<code_verifier のSHA256をBase64URLエンコード>
     &code_challenge_method=S256
   ```
2. MT に未ログインなら通常のログイン画面が表示される。ログイン後、認可確認画面で **許可する** を選択
3. `redirect_uri` に `code`（認可コード）と `state` が付与されてリダイレクトされる
4. **クライアント側は、受け取った `state` が手順1で生成したものと完全に一致することを必ず確認してから次に進んでください。** 一致しない場合はリクエストを中断すること（認可レスポンスの差し替え対策）。
5. 受け取った `code` と、最初に生成した `code_verifier` を使ってトークンと交換する:
   ```bash
   curl -X POST https://example.com/mt/mt-data-api.cgi/v4/mcp/token \
     -H 'Content-Type: application/x-www-form-urlencoded' \
     -d 'grant_type=authorization_code&code=<受け取ったcode>&redirect_uri=http://127.0.0.1:PORT/callback&code_verifier=<code_verifier>'
   ```

成功レスポンス:
```json
{"access_token":"...","refresh_token":"...","token_type":"Bearer","expires_in":604800,"user_id":3,"username":"your-username"}
```

`access_token` の有効期限は7日間です。期限が切れる前（または切れた後）に、ブラウザでの再ログインなしで `refresh_token` を使って新しいアクセストークンを取得できます（対応しているMCPクライアントであれば自動的に行われます）。

```bash
curl -X POST https://example.com/mt/mt-data-api.cgi/v4/mcp/token \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'grant_type=refresh_token&refresh_token=<refresh_token>'
```

> `refresh_token` の有効期限は30日間です。使用するたびに新しい `access_token` と `refresh_token` が発行され、古い `refresh_token` は即座に無効化されます（ローテーション。盗まれたトークンの使い回しを検知・遮断しやすくするためです）。そのため、応答に含まれる新しい `refresh_token` を必ず保存し直してください。30日間まったく使われなかった `refresh_token` は失効し、その場合は認可フロー（手順1〜5）を最初からやり直す必要があります。

> `redirect_uri` は RFC 8252（ネイティブアプリ向け OAuth）の慣例に従い、次のいずれかのみ許可しています。①ループバック: `http://127.0.0.1:*` / `http://localhost:*` / `http://[::1]:*`（任意のポート）。②プライベートスキーム: `cursor://...` や `claude://...` など http/https 以外のカスタムURLスキーム（Cursor・Claude Desktop などデスクトップアプリが使用）。③既知クライアントの固定HTTPSコールバック（完全一致のみ・現状 Cursor の Background Agent 用 `https://www.cursor.com/agents/mcp/oauth/callback` のみ登録）。任意の外部Webホストへのリダイレクトはオープンリダイレクト対策のため拒否されます。認可コードの有効期限は10分・一度使うと失効します。PKCE は `S256` のみ対応（`plain` は不可）。`POST /v4/mcp/register`（Dynamic Client Registration）で登録済みの `client_id` を使う場合は、認可時の `redirect_uri` がその登録内容と完全一致することも追加で要求されます。
>
> Cursor / Claude Desktop など、MCP のリモートサーバー向け OAuth 自動検出（`WWW-Authenticate: Bearer resource_metadata=...` からの `.well-known` 参照）に対応したクライアントであれば、下記の静的ファイルを配置することでフローの一部を自動化できます。未対応のクライアントでは、上記の手順を独自のログインヘルパー（ブラウザを開いて `redirect_uri` でコードを受け取る小さなスクリプトなど）で実行してください。
>
> `https://example.com/.well-known/oauth-protected-resource`
> ```json
> {
>   "resource": "https://example.com/mt/mt-data-api.cgi/v4/mcp",
>   "authorization_servers": ["https://example.com"]
> }
> ```
> `https://example.com/.well-known/oauth-authorization-server`
> ```json
> {
>   "issuer": "https://example.com",
>   "authorization_endpoint": "https://example.com/mt/mt.cgi?__mode=mcp_authorize",
>   "token_endpoint": "https://example.com/mt/mt-data-api.cgi/v4/mcp/token",
>   "registration_endpoint": "https://example.com/mt/mt-data-api.cgi/v4/mcp/register",
>   "response_types_supported": ["code"],
>   "grant_types_supported": ["authorization_code", "refresh_token"],
>   "code_challenge_methods_supported": ["S256"],
>   "token_endpoint_auth_methods_supported": ["none"]
> }
> ```
> これらは静的ファイルとして Web サーバーのドキュメントルート直下（`/.well-known/`）に配置してください（MT のバージョン管理下の `/mt-data-api.cgi/v4/...` の外側にある必要があります）。`registration_endpoint`（`POST /v4/mcp/register`）は RFC 7591 の Dynamic Client Registration に対応しており、Cursor など事前登録なしで OAuth を試みるクライアントが自動的にクライアントIDを取得できます（client_secret は発行しません＝PKCEを使うパブリッククライアント向け）。

#### IPアドレス制限があるMT環境での注意

Cursor の「Background Agent」のようにクラウド側で動作するMCPクライアントを使う場合、OAuthの一部リクエスト（`.well-known` の取得、`POST /v4/mcp/register`、`POST /v4/mcp/token`）は**ユーザー本人のブラウザではなく、クライアント（Cursorなど）のサーバー自身から**送信されます。MT サーバーに IP アドレス制限（ファイアウォール・WAF・`Require ip` 等）をかけている場合は、これらのエンドポイントに対してそのクライアントのサーバー送信元IPを許可する必要があります。

- 認可画面（`GET /mt.cgi?__mode=mcp_authorize` とその後の `POST`）は、ユーザー本人のブラウザからのアクセスなので、通常どおり管理者の端末からのみ許可されていれば問題ありません。
- `.well-known/*`、`POST /v4/mcp/register`、`POST /v4/mcp/token` は、クライアントのサーバーからのアクセスを許可する必要があります。許可すべき具体的なIPレンジは各クライアント（Cursor等）の公式ドキュメントを参照してください（変更されることがあるため、本READMEには固定のIPを記載しません）。
- IPレンジの継続的な追従が難しい場合は、`.well-known` を公開せず（前述「方法B」または「方法C」に絞る）、OAuthの自動検出を使わない運用も選択肢です。

#### 方法B: ログインAPIで直接発行（非対話・自動化向け）

ブラウザを開けない CLI・CI などから、ユーザー名・パスワードで直接トークンを取得できます。

```bash
read -s -p 'Password: ' MT_PASSWORD; echo
curl -X POST https://example.com/mt/mt-data-api.cgi/v4/mcp/authenticate \
  -H 'Content-Type: application/json' \
  --data-binary @- <<EOF
{"username":"your-username","password":"$MT_PASSWORD"}
EOF
unset MT_PASSWORD
```

成功レスポンスには `access_token` と合わせて `refresh_token` も含まれます。7日ごとに毎回パスワードを入力し直さずに済むよう、`refresh_token`（30日間有効）を保存しておき、`grant_type=refresh_token` で更新できます（方法A の「OAuth」節にある `POST /v4/mcp/token` の例と同じ形式です）。

> `-d` の引数に直接パスワードを書くと、シェルの履歴ファイルや `ps` コマンドの実行中プロセス一覧に残ってしまうため避けてください。上記のように標準入力（`--data-binary @-`）経由で渡すことを推奨します。通信は必ず HTTPS 経由で行ってください（平文の HTTP ではパスワードが漏えいします）。パスワード自体は保存されず、照合にのみ使用されます。5回連続で認証に失敗すると、そのユーザー名は15分間ロックされます。対話的に使える環境では方法Aの方が安全です（パスワードが MCP クライアントを経由しないため）。

#### 方法C: 管理画面から発行

MT 管理画面で **システム > プラグイン > MT MCP Server** を開き、**設定** タブを選択します。

![MT MCP Server の設定画面 — MCP トークンを発行する](./docs/images/mcp-token-settings.png)

1. **トークンを発行する** ボタンをクリック
2. 表示されたトークンを **コピー** ボタンでコピー
3. 次のステップで MCP クライアントの設定に貼り付け

> いずれの方法も、トークンの有効期限は発行から 7 日間です。再発行しても以前のトークンは即時無効になりません。期限切れの場合は同じ手順で再発行してください。

#### 権限について

各ツールは、トークンに紐づくユーザーの MT 権限で実行されます。ツールごとの権限と注意は [docs/tools.md](docs/tools.md#権限と注意) を参照してください。

> 本機能導入前に発行された、ユーザーが紐づかない古い形式のトークンは **401 エラーで拒否されます**（ブログ権限チェックを回避できてしまうため）。古いトークンをお使いの場合は、上記いずれかの方法で新しいトークンを再発行してください。

### 4. MCP クライアントを設定

#### Cursor (`~/.cursor/mcp.json`)

**OAuth自動ログイン（推奨・動作確認済み）**

`.well-known` を設置済みなら、`headers` を書かずにこれだけで接続できます。接続時にブラウザが自動的に開き、MTへのログイン → 許可画面 → 接続、という流れになります（本READMEのトラブルシューティングは主にこの方式の実機検証で得た知見です）。

```json
{
  "mcpServers": {
    "movable-type": {
      "url": "https://example.com/mt/mt-data-api.cgi/v4/mcp"
    }
  }
}
```

**手動トークン方式（`.well-known` 未設置の場合・フォールバック）**

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

**実機確認の結果、`claude_desktop_config.json` はこのような `type`/`url`/`headers` 形式のリモートMCPサーバー定義をサポートしていません。** 該当エントリは「有効なMCPサーバー設定ではない」として無視されます。Claude Desktopでリモート（HTTP/SSE）のMCPサーバーを使う場合は、この設定ファイルを直接編集するのではなく、アプリ内の「設定 → コネクタ」のようなUIから追加する必要があるとみられます（具体的な手順はバージョンにより異なる可能性があり、本READMEでは検証できていません）。

MTサーバーがHTTPS未対応（例: ローカルDockerで `http://localhost:PORT` のみ）の場合は、コネクタUI経由でも接続できない可能性が高いです。その場合は、以下の「ローカル環境（HTTPS未対応）の場合」を参照してください。

##### ローカル環境（HTTPS未対応）の場合

MTがローカルDocker等で動いていて `http://localhost:PORT` にしかアクセスできない場合、`command`/`args` によるローカル起動のMCPサーバー（Claude Desktopが標準サポートする形式）として、付属のブリッジスクリプトを使う方法があります。HTTPS化は不要です。

`tools/claude-desktop-bridge/mt-mcp-bridge.js`（Node.js標準ライブラリのみ、追加インストール不要）が、標準入出力（stdio）とMTのHTTPエンドポイントの間を中継します。

```json
{
  "mcpServers": {
    "movable-type": {
      "command": "node",
      "args": ["/absolute/path/to/mt-plugin-mcp/tools/claude-desktop-bridge/mt-mcp-bridge.js"],
      "env": {
        "MT_MCP_URL": "http://localhost:10000/mt-data-api.cgi/v4/mcp",
        "MT_MCP_TOKEN": "<発行したトークン>"
      }
    }
  }
}
```

- `MT_MCP_URL` はDocker等で公開しているMTの実際のURL（`v4/mcp` まで含む）に置き換えてください。
- `MT_MCP_TOKEN` は方法A〜Cいずれかで発行したトークンです（有効期限7日。切れたら再発行してこの値を更新してください。`refresh_token` によるこのスクリプト自体の自動更新には対応していません）。
- `args` のパスは絶対パスで指定してください。

#### Claude Code（CLI）

`.mcp.json` またはプロジェクト設定でリモートMCPサーバーを直接指定できます。MTがHTTPS対応の公開URLを持つ場合は、Cursorと同様の方法A/Bの設定で動作する可能性があります（未検証）。ローカルDocker等でHTTPS未対応の場合は、上記のブリッジスクリプトを `command`/`args` で指定する方法が使えます。

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
| `GET` | `/mt.cgi?__mode=mcp_authorize` | OAuth 認可エンドポイント（ブラウザでMTにログイン→consent画面） |
| `POST` | `/mt.cgi?__mode=mcp_authorize_approve` | consent画面からの許可/拒否を受け取り、`redirect_uri` へリダイレクト |
| `POST` | `/mt-data-api.cgi/v4/mcp/token` | OAuth トークンエンドポイント（`grant_type=authorization_code`：認可コード+PKCE→トークン／`grant_type=refresh_token`：リフレッシュトークン→新トークン） |
| `POST` | `/mt-data-api.cgi/v4/mcp/authenticate` | ユーザー名・パスワードでログインし、アクセストークンを発行 |
| `POST` | `/mt-data-api.cgi/v4/mcp/register` | Dynamic Client Registration（`client_id` 発行。client_secret は出さない） |
| `GET` | `/mt-data-api.cgi/v4/mcp` | SSE 接続（クライアントが POST 先 URL を受け取る） |
| `POST` | `/mt-data-api.cgi/v4/mcp` | JSON-RPC リクエストの送受信 |
| `OPTIONS` | `/mt-data-api.cgi/v4/mcp` | CORS プリフライト |

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
{"id":1,"jsonrpc":"2.0","result":{"capabilities":{"tools":{"listChanged":false}},"protocolVersion":"2024-11-05","serverInfo":{"name":"MT MCP Server","version":"0.7.0"}}}
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

## ディレクトリ構成

```
plugins/MTMCP/
├── config.yaml
└── lib/
    └── MTMCP/
        ├── App.pm          # Data API ハンドラ・トークン検証・SSE
        ├── Auth.pm         # ログインAPI（ユーザー名/パスワード → トークン発行）・失敗ロックアウト
        ├── OAuth.pm        # OAuth 2.1（認可コード + PKCE）トークンエンドポイント・検証ロジック
        ├── Perm.pm         # ブログ単位・システム権限（ログ閲覧・ユーザー管理）のチェック
        ├── Protocol.pm     # MCP JSON-RPC ディスパッチャ
        ├── CMS/
        │   ├── Token.pm      # 管理画面からのトークン発行
        │   └── Authorize.pm  # OAuth 認可エンドポイント（consent画面）
        └── Tools/
            ├── Blog.pm         # blog_list
            ├── Entry.pm        # entry_list / get / create / update / delete / preview
            ├── Page.pm         # page_list / get / create / update / delete / preview
            ├── Folder.pm       # folder_list / get / create / update / delete
            ├── Category.pm     # category_list / get / create / update / delete / permutate
            ├── CategorySet.pm  # category_set_list / get / create / update / delete
            ├── Tag.pm          # tag_list / rename / delete
            ├── Asset.pm        # asset_list / get / upload / delete / thumbnail
            ├── Template.pm     # template_list / get / create / update / delete / validate / preview / tag_list
            ├── TemplateMap.pm  # templatemap_list / get / create / update / delete
            ├── Widget.pm       # widgetset_* / widget_list
            ├── Log.pm          # log_list / log_get
            ├── User.pm         # user_list / get / create / delete / unlock / recover_password
            ├── Rebuild.pm      # rebuild_template / entry / page / content_data / site
            ├── ContentType.pm  # content_type_list / get / create
            └── ContentData.pm  # content_data_list / get / create / update / delete

tools/
└── claude-desktop-bridge/
    └── mt-mcp-bridge.js  # Claude Desktop用stdio<->HTTPブリッジ（HTTPS未対応のローカル環境向け）
```

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
| `redirect_uri is not allowed`（OAuth認可時） | `redirect_uri` がループバック（127.0.0.1 / localhost / [::1]）でも http/https 以外のカスタムスキームでもない | クライアント側の redirect_uri を確認（http(s) の外部ホストは非対応） |
| `invalid_grant`（トークン交換時） | 認可コードの期限切れ（10分）・使用済み・`code_verifier`不一致・`redirect_uri`不一致 | 認可フローを最初からやり直す |
| `Incompatible auth server: does not support dynamic client registration`（Cursor） | `oauth-authorization-server` に `registration_endpoint` が含まれていない | `.well-known/oauth-authorization-server` に `registration_endpoint` を追加（本READMEのサンプル参照） |
| `This token was issued by an older version...`（401） | ユーザーに紐づかない古い形式のトークンを使用している | 新しいトークンを再発行する |
| `invalid_grant`: `client_id mismatch`（トークン交換時） | 認可時と異なる `client_id` でトークン交換を試みた | `/authorize` と `/token` で同じ `client_id` を使用する |
| `invalid_grant`: `Refresh token is invalid or expired` | `refresh_token` が期限切れ（30日）・使用済み（ローテーション済み）・不正な値 | 認可フロー（またはログインAPI）を最初からやり直して新しいトークンを取得する |
| アップロードで `File extension not allowed` | 許可されていない拡張子（実行可能ファイルや`.svg`など）を指定した | 許可拡張子（[docs/tools.md](docs/tools.md#asset_upload-の注意点) 参照）に変換してからアップロード |
| Claude Desktopで「有効なMCPサーバー設定ではないため、スキップされました」 | `claude_desktop_config.json` は `type`/`url`/`headers` によるリモートサーバー定義をサポートしていない | アプリのコネクタ設定UIから追加するか、HTTPS未対応のローカル環境なら `tools/claude-desktop-bridge/` のブリッジスクリプトを使う |
| `テンプレート構文にエラーがあります`（テンプレート保存時） | 本文に閉じ忘れや存在しないタグがある | エラーの行番号を見て修正する。`template_tag_list` で正しいタグ名を確認できる。意図的に保存する場合のみ `skip_validation: true` |
| `インデックステンプレートには outfile が必要です` | `type: "index"` で `outfile` を指定していない | `outfile: "index.html"` のように出力ファイル名を指定する。公開しないテンプレートなら `build_type: 0` |
| 再構築が `テンプレート'○○'には出力ファイルの設定がありません` で失敗する | 出力ファイル名が空のインデックステンプレートが既に存在する（本プラグインの旧版やMT側で作成されたもの） | `template_list` で該当テンプレートを探し、`template_update` で `outfile` を設定するか `build_type: 0` にする |
| `「テンプレートの編集」の権限がありません` | トークンのユーザーに `edit_templates` 権限が無い（`template_create` / `update` / `delete` / `preview` で必要） | MT 側でテンプレート編集権限を持つロールを付与するか、権限のあるユーザーでトークンを再発行 |
| `「サイトの再構築」の権限がありません` | トークンのユーザーに `rebuild` 権限が無い | MT 側で「サイトの再構築」権限を付与するか、権限のあるユーザーでトークンを再発行 |
| `rebuild_site` が応答しない・504 になる | 記事数が多くWebサーバーのタイムアウトを超えた | `rebuild_template` / `rebuild_entry` で範囲を絞る、`archive_type` を指定して分割実行する、またはMT管理画面から再構築する |
| `このテンプレート（type: ...）は単体で再構築できません` | ウィジェットやモジュールなど、単体では出力先を持たないテンプレートを指定した | それを読み込んでいるインデックス/アーカイブテンプレートを `rebuild_template` するか、`rebuild_site` を使う |
| `ブログの公開パス（site_path）が設定されていないため再構築できません` | ブログの公開パスが未設定 | MT 管理画面の「サイトの設定 > 公開」でサイトパスを設定する |
| `Archive type '...' is not a chosen archive type` | `rebuild_site` の `archive_type` がそのブログで使われていない | 指定を外して全体を再構築するか、ブログで有効なアーカイブタイプを指定する |

## 開発

プラグイン本体は `plugins/MTMCP/` です。MT の `plugins/` にコピー（またはシンボリックリンク）して有効化します。

ユニットテストは MT 本体を必要とせず、`t/lib` のスタブを使います。

```bash
prove -I plugins/MTMCP/lib -I t/lib t/*.t
```

個別に実行する例:

```bash
prove -I plugins/MTMCP/lib -I t/lib t/folder.t t/page.t
```

## 関連

- 実装ロードマップ: [#26](https://github.com/redamoon/mt-plugin-mcp/issues/26)
- ドキュメント追従: [#41](https://github.com/redamoon/mt-plugin-mcp/issues/41)
- 課題一覧: [Issues](https://github.com/redamoon/mt-plugin-mcp/issues)

