# MT MCP Server — 認証・接続アーキテクチャ

## 概要

MCP クライアント（Claude Desktop など）が Movable Type に接続する際の認証・通信フローを示す。

認証方式は **Bearer トークン（静的）** のみ。トークンはプラグイン設定画面（システム管理 > プラグイン > MT MCP Server）で発行し、`Authorization: Bearer <token>` ヘッダとして毎リクエストに付与する。

---

## コンポーネント図

```plantuml
@startuml
skinparam componentStyle rectangle
skinparam rectangle {
  BorderColor #555
  BackgroundColor #f9f9f9
}

package "MCP Client" {
  [Claude Desktop / AI Agent] as client
}

package "Movable Type (Web Server)" {
  package "MT Data API" {
    [mt-data-api.cgi] as cgi
    [Endpoint Router\n(config.yaml)] as router
  }

  package "MTMCP Plugin" {
    [App.pm\nhandle / handle_sse] as app
    [_check_auth()\nBearer 検証] as auth
    [Protocol.pm\ndispatch()] as protocol

    package "Tools" {
      [Entry / Blog\nCategory / Tag] as tools_entry
      [Asset] as tools_asset
      [Template] as tools_tmpl
      [ContentType\nContentData] as tools_ct
    }
  }

  database "Plugin Config\n(api_token)" as config
  database "MT Database" as db
}

client --> cgi : HTTP (GET/POST)\nAuthorization: Bearer <token>
cgi --> router : ルーティング
router --> app : GET  → handle_sse\nPOST → handle
app --> auth : _check_auth()
auth --> config : get_config_value('api_token')
auth --> app : OK / 401
app --> protocol : dispatch(req)
protocol --> tools_entry
protocol --> tools_asset
protocol --> tools_tmpl
protocol --> tools_ct
tools_entry --> db
tools_asset --> db
tools_tmpl --> db
tools_ct --> db

@enduml
```

---

## SSE 接続フロー（初回接続）

MCP クライアントは最初に GET で SSE エンドポイントへ接続し、POST 先 URL を受け取る。

```mermaid
sequenceDiagram
    participant C  as MCP Client
    participant MT as mt-data-api.cgi
    participant A  as App.pm
    participant CF as Plugin Config<br/>(api_token)

    C->>MT: GET /mt-data-api.cgi/v4/mcp<br/>Authorization: Bearer <token>
    MT->>A: handle_sse()
    A->>A: _check_auth()
    A->>CF: get_config_value('api_token')
    CF-->>A: stored_token

    alt トークン一致
        A-->>C: 200 text/event-stream<br/>event: endpoint<br/>data: https://.../v4/mcp
        Note over C: POST 先 URL を取得
    else トークン不一致 / 未設定
        A-->>C: 401 Unauthorized<br/>WWW-Authenticate: Bearer realm="MT MCP"
    end
```

---

## JSON-RPC リクエストフロー（MCP プロトコル）

SSE で取得した URL に対して MCP の JSON-RPC 2.0 メッセージを POST する。

```mermaid
sequenceDiagram
    participant C  as MCP Client
    participant MT as mt-data-api.cgi
    participant A  as App.pm
    participant CF as Plugin Config<br/>(api_token)
    participant P  as Protocol.pm
    participant T  as Tool Handler<br/>(Entry / Blog / ...)
    participant DB as MT Database

    C->>MT: POST /mt-data-api.cgi/v4/mcp<br/>Content-Type: application/json<br/>Authorization: Bearer <token><br/>Body: {"jsonrpc":"2.0","method":"..."}

    MT->>A: handle()

    Note over A: Content-Type チェック<br/>（application/json でなければ 415）

    A->>A: _check_auth()
    A->>CF: get_config_value('api_token')
    CF-->>A: stored_token

    alt 認証失敗
        A-->>C: 401 {"error":"Unauthorized"}<br/>or {"error":"Invalid token"}
    else 認証成功
        A->>A: JSON デコード
        A->>P: dispatch(app, req)

        alt method: initialize
            P-->>C: 200 {protocolVersion, capabilities, serverInfo}
        else method: tools/list
            P-->>C: 200 {tools: [...]}
        else method: tools/call
            P->>T: handler(app, arguments)
            T->>DB: MT オブジェクト操作
            DB-->>T: 結果
            T-->>P: result
            P-->>C: 200 {content:[{type:"text", text:"..."}]}
        else method: ping
            P-->>C: 200 {}
        else 未知のメソッド
            P-->>C: 200 {error:{code:-32601, message:"Method not found"}}
        end
    end
```

---

## 認証チェック詳細（`_check_auth`）

```mermaid
flowchart TD
    A[リクエスト受信] --> B{Authorization ヘッダあり?}
    B -- No --> E1[401 Unauthorized\nWWW-Authenticate: Bearer realm='MT MCP']
    B -- Yes --> C{Bearer スキームか?}
    C -- No --> E1
    C -- Yes --> D[provided_token を抽出]
    D --> F[Plugin Config から api_token を取得]
    F --> G{api_token が設定済み\nかつ provided_token と一致?}
    G -- No --> E2[401 Invalid token]
    G -- Yes --> OK[認証成功 → 処理継続]
```

> **注意**: トークンは固定文字列の完全一致比較のみ。有効期限・スコープ・複数トークンの概念はない。

---

## エンドポイント定義

`config.yaml` で登録される 2 つのエンドポイント：

| verb | route | handler | 用途 |
|------|-------|---------|------|
| GET  | `/v4/mcp` | `App::handle_sse` | SSE 接続・POST URL 通知 |
| POST | `/v4/mcp` | `App::handle` | JSON-RPC 2.0 メッセージ処理 |

いずれも `requires_login: 0`（MT セッション認証は不要）。Bearer トークン認証のみで制御する。
