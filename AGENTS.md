# エージェント / コントリビューター向けメモ

このリポジトリは Movable Type 9 用の MCP サーバープラグインです。ユーザー向けの導入は [docs/getting-started.md](docs/getting-started.md) と [README.md](README.md)、ツール説明は [docs/tools.md](docs/tools.md) です。人間の開発者がプラグインを直す手順は [docs/developer-onboarding.md](docs/developer-onboarding.md) です。本ファイルはエージェント向けの **どこを触るか・テストの回し方・やってはいけないこと** であり、人間向けオンボーディングの代替ではありません。

ロードマップの実装範囲は [#26](https://github.com/redamoon/mt-plugin-mcp/issues/26) の P1/P2 までです。検討中の P3 と後続は [#44](https://github.com/redamoon/mt-plugin-mcp/issues/44) です。

## ディレクトリ

```
plugins/MTMCP/                 # プラグイン本体（MT の plugins/ へコピー）
  config.yaml                  # エンドポイント・CMS メソッドの登録
  lib/MTMCP/
    App.pm                     # Data API ハンドラ・トークン検証・SSE
    Auth.pm                    # ログイン API（/v4/mcp/authenticate）
    OAuth.pm                   # OAuth 2.1 PKCE・refresh・DCR（/v4/mcp/token, /register）
    Perm.pm                    # ブログ単位・システム権限
    Protocol.pm                # MCP JSON-RPC。ツール名 → Tools::* の正本
    Search.pm                  # keyword の DB LIKE
    Args.pm                    # bool 引数の判定・confirm 必須チェック
    Author.pm                  # author_id → MT::Author のキャッシュ付きロード
    CMS/Token.pm               # 管理画面からのトークン発行
    CMS/Authorize.pm           # OAuth 認可（consent）
    Tools/*.pm                 # ツール実装
  tmpl/                        # CMS テンプレート
t/*.t                          # ユニットテスト
t/lib/                         # MT 本体のスタブ（実 MT は不要）
docs/                          # ユーザー向け（getting-started / guides / developer-onboarding / tools / architecture-auth）
tools/claude-desktop-bridge/   # Claude Desktop 用 stdio↔HTTP ブリッジ
skills/movable-type-mcp/       # 配布用 Claude Skill（運用手順。Perl は触らない）
```

新しい MCP ツールを足すときは、実装を `plugins/MTMCP/lib/MTMCP/Tools/` に置き、`Protocol.pm` のディスパッチ表と `_tool_definitions()` の両方に登録します。ツール名・権限の説明を変えたら [docs/tools.md](docs/tools.md) も合わせます。

認証まわりの図とエンドポイントは [docs/architecture-auth.md](docs/architecture-auth.md) です。実装の正本は `Auth.pm` / `OAuth.pm` / `App.pm` / `config.yaml` です。

## Tools とテスト

| モジュール | 主なツール | テスト |
| --- | --- | --- |
| `Tools/Blog.pm` | `blog_list` | （一覧のみ。専用テストなし） |
| `Tools/Entry.pm` | `entry_*` / `entry_preview` / `entry_export` / `entry_import` | `t/entry_class_filter.t` `t/entry_preview.t` `t/entry_export.t` `t/entry_import.t` `t/keyword_search.t` |
| `Tools/Page.pm` | `page_*` / `page_preview` | `t/page.t` |
| `Tools/Folder.pm` | `folder_*` | `t/folder.t` |
| `Tools/Category.pm` | `category_*` | `t/category_write.t` |
| `Tools/CategorySet.pm` | `category_set_*` | `t/category_set.t` `t/content_type_categories_field.t` |
| `Tools/Tag.pm` | `tag_list` / `tag_rename` / `tag_delete` | `t/tag_rename_delete.t` |
| `Tools/Asset.pm` | `asset_*` | （専用テストなし） |
| `Tools/Template.pm` | `template_*` | `t/template_widgetset_body.t` |
| `Tools/TemplateMap.pm` | `templatemap_*` | `t/templatemap.t` |
| `Tools/Widget.pm` | `widgetset_*` / `widget_list` | `t/widgetset.t` |
| `Tools/Log.pm` | `log_list` / `log_get` | `t/log_tools.t` |
| `Tools/User.pm` | `user_list` / `get` / `create` / `update` / `delete` / `unlock` / `recover_password` | `t/user_tools.t` |
| `Tools/Rebuild.pm` | `rebuild_*` | （専用テストなし。Page は `t/page.t` で触れる） |
| `Tools/ContentType.pm` | `content_type_*` | `t/content_type_categories_field.t` |
| `Tools/ContentData.pm` | `content_data_*` | （専用テストなし） |
| `Search.pm` | `keyword` の LIKE | `t/keyword_search.t` `t/search_helper.t` |
| `Args.pm` | bool 引数の判定 / confirm 必須チェック | `t/args.t` |
| `Author.pm` | `author_id` → `MT::Author` のロード（メモ化つき） | `t/author_helper.t` |
| `Perm.pm` | 権限チェック | `t/perm_log_view.t` |

ツールを追加・変更したら、対応する `t/*.t` を足すか更新します。スタブが足りないときは `t/lib/MT/` に最小限のモックを置きます（本番の MT コアをコピーしない）。

## テストの回し方

MT 本体は不要です。

```bash
prove -I plugins/MTMCP/lib -I t/lib t/*.t
```

個別:

```bash
prove -I plugins/MTMCP/lib -I t/lib t/folder.t t/page.t
```

## やってはいけないこと

- **P3 の実装を勝手に進めない。** 対象は [#44](https://github.com/redamoon/mt-plugin-mcp/issues/44): Stats（#18）、`blog_backup`（#20）、データ移行本体（#21）。本体（Data API など）の動きを見てから判断する。
- **NOT_PLANNED を再オープンしない。** サイト CRUD（#9）、ロール・権限・グループ（#11）、テーマ（#16）、プラグイン管理（#17）は、必要になったら新規起票する。
- **secrets をコミットしない。** `.env`、トークン、パスワード、実サイトの認証情報。
- **force-push しない。** `main` への force-push は特にしない。
- **スカラー `MT::*->load($id)` は class/type が絡むと使わない。** Entry と Page、Category と Folder など。ハッシュ条件で `class` を明示する（#24 の方針）。
- **公開ファイルを黙って書かない。** preview 系はビルド結果を返すだけで書き出さない。破壊的操作は確認・権限を厳しくする。
- **hooks をスキップしない。** `--no-verify` や `--no-gpg-sign` は使わない。

## 関連

- 実装ロードマップ（P1/P2・ラップアップ）: [#26](https://github.com/redamoon/mt-plugin-mcp/issues/26)
- 検討中（P3）: [#44](https://github.com/redamoon/mt-plugin-mcp/issues/44)
- ユーザー向け README / docs: [#41](https://github.com/redamoon/mt-plugin-mcp/issues/41)（本ファイルは [#42](https://github.com/redamoon/mt-plugin-mcp/issues/42)）
- オンボーディング新設は #22。Claude Skill は #23（`skills/movable-type-mcp/`。運用手順は docs と揃える）。
