
#!/bin/bash
set -e

REPO="https://github.com/redamoon/mt-mcp.git"
BRANCH="feature/mcp-plugin-initial"

# 1. clone
git clone "$REPO" mt-mcp
cd mt-mcp

# 2. ブランチ作成
git checkout -b "$BRANCH"

# 3. ディレクトリ構成作成
mkdir -p plugins/MTMCP/lib/MTMCP/Tools

# 4. config.yaml
cat > plugins/MTMCP/config.yaml << 'YAML'
name: MT MCP Server
id: MTMCP
key: MTMCP
version: 0.1.0
schema_version: 0.1
description: Movable Type 9 用 MCP (Model Context Protocol) サーバープラグイン

author_name: ''
author_link: ''

settings:
  api_token:
    default: ''
    scope: system

applications:
  cms:
    routes:
      mcp_endpoint:
        path: /mcp
        handler: $MTMCP::MTMCP::App::handle
        requires_login: 0
YAML

# 5. App.pm
cat > plugins/MTMCP/lib/MTMCP/App.pm << 'PERL'
package MTMCP::App;
use strict;
use warnings;
use JSON::XS;

my $json = JSON::XS->new->utf8->canonical;

sub handle {
    my ($app) = @_;

    unless ($app->request_method eq 'POST') {
        return _respond($app, 405, { error => 'Method Not Allowed' });
    }

    my $ct = $app->request->content_type // '';
    unless ($ct =~ m{application/json}i) {
        return _respond($app, 415, { error => 'Content-Type must be application/json' });
    }

    my $auth = $app->request->header('Authorization') // '';
    unless ($auth =~ /^Bearer\s+(.+)$/i) {
        $app->response->header('WWW-Authenticate' => 'Bearer realm="MT MCP"');
        return _respond($app, 401, { error => 'Unauthorized' });
    }
    my $provided_token = $1;

    my $plugin      = MT->component('MTMCP');
    my $valid_token = $plugin->get_config_value('api_token', 'system') // '';

    unless ($valid_token && $provided_token eq $valid_token) {
        return _respond($app, 401, { error => 'Invalid token' });
    }

    my $body = $app->request->content // '';
    my $req  = eval { $json->decode($body) };
    if ($@) {
        return _respond($app, 400, {
            jsonrpc => '2.0',
            id      => undef,
            error   => { code => -32700, message => 'Parse error' },
        });
    }

    require MTMCP::Protocol;
    my $response = MTMCP::Protocol::dispatch($app, $req);

    unless (defined $response) {
        $app->response->status(204);
        return '';
    }

    return _respond($app, 200, $response);
}

sub _respond {
    my ($app, $status, $data) = @_;
    $app->response->status($status);
    $app->response->header('Content-Type' => 'application/json; charset=UTF-8');
    return $json->encode($data);
}

1;
PERL

# 6. Protocol.pm
cat > plugins/MTMCP/lib/MTMCP/Protocol.pm << 'PERL'
package MTMCP::Protocol;
use strict;
use warnings;
use JSON::XS;

our $PROTOCOL_VERSION = '2024-11-05';

my %TOOL_HANDLERS = (
    'entry_list'      => sub { require MTMCP::Tools::Entry;    MTMCP::Tools::Entry::list(@_)        },
    'entry_get'       => sub { require MTMCP::Tools::Entry;    MTMCP::Tools::Entry::get(@_)         },
    'entry_create'    => sub { require MTMCP::Tools::Entry;    MTMCP::Tools::Entry::create(@_)      },
    'entry_update'    => sub { require MTMCP::Tools::Entry;    MTMCP::Tools::Entry::update(@_)      },
    'category_list'   => sub { require MTMCP::Tools::Category; MTMCP::Tools::Category::list(@_)     },
    'tag_list'        => sub { require MTMCP::Tools::Category; MTMCP::Tools::Category::list_tags(@_)},
    'asset_list'      => sub { require MTMCP::Tools::Asset;    MTMCP::Tools::Asset::list(@_)        },
    'asset_get'       => sub { require MTMCP::Tools::Asset;    MTMCP::Tools::Asset::get(@_)         },
    'template_list'   => sub { require MTMCP::Tools::Template; MTMCP::Tools::Template::list(@_)     },
    'template_get'    => sub { require MTMCP::Tools::Template; MTMCP::Tools::Template::get(@_)      },
    'template_update' => sub { require MTMCP::Tools::Template; MTMCP::Tools::Template::update(@_)   },
);

sub dispatch {
    my ($app, $req) = @_;
    my $method = $req->{method} // '';
    my $id     = $req->{id};
    my $params = $req->{params} // {};

    if ($method eq 'initialize') {
        return _result($id, {
            protocolVersion => $PROTOCOL_VERSION,
            capabilities    => { tools => { listChanged => JSON::XS::false } },
            serverInfo      => { name => 'MT MCP Server', version => '0.1.0' },
        });
    }

    if ($method eq 'notifications/initialized') {
        return undef;
    }

    if ($method eq 'tools/list') {
        return _result($id, { tools => _tool_definitions() });
    }

    if ($method eq 'tools/call') {
        my $tool_name = $params->{name}      // '';
        my $arguments = $params->{arguments} // {};
        my $handler   = $TOOL_HANDLERS{$tool_name};
        unless ($handler) {
            return _error($id, -32601, "Unknown tool: $tool_name");
        }
        my $result = eval { $handler->($app, $arguments) };
        if ($@) {
            (my $err = $@) =~ s/ at .+ line \d+\.?\s*$//;
            return _result($id, {
                content => [{ type => 'text', text => "Error: $err" }],
                isError => JSON::XS::true,
            });
        }
        return _result($id, {
            content => [{ type => 'text', text => encode_json($result) }],
        });
    }

    if ($method eq 'ping') {
        return _result($id, {});
    }

    return _error($id, -32601, "Method not found: $method");
}

sub _result { my ($id, $r) = @_; return { jsonrpc => '2.0', id => $id, result => $r } }
sub _error  { my ($id, $c, $m) = @_; return { jsonrpc => '2.0', id => $id, error => { code => $c, message => $m } } }

sub _tool_definitions {
    return [
        { name => 'entry_list',   description => '指定ブログの記事一覧を取得する',
          inputSchema => { type => 'object', required => ['blog_id'],
            properties => { blog_id => { type => 'integer' }, limit => { type => 'integer' },
                            status => { type => 'string', enum => ['publish','draft','all'] } } } },
        { name => 'entry_get',    description => '記事IDを指定して1件取得する',
          inputSchema => { type => 'object', required => ['entry_id'],
            properties => { entry_id => { type => 'integer' } } } },
        { name => 'entry_create', description => '新規記事を作成する（デフォルトは下書き）',
          inputSchema => { type => 'object', required => ['blog_id','title'],
            properties => { blog_id => { type => 'integer' }, title => { type => 'string' },
                            body => { type => 'string' }, status => { type => 'string', enum => ['publish','draft'] },
                            category_ids => { type => 'array', items => { type => 'integer' } } } } },
        { name => 'entry_update', description => '既存記事を更新する',
          inputSchema => { type => 'object', required => ['entry_id'],
            properties => { entry_id => { type => 'integer' }, title => { type => 'string' },
                            body => { type => 'string' }, status => { type => 'string', enum => ['publish','draft'] } } } },
        { name => 'category_list', description => '指定ブログのカテゴリ一覧を取得する',
          inputSchema => { type => 'object', required => ['blog_id'],
            properties => { blog_id => { type => 'integer' } } } },
        { name => 'tag_list',      description => '指定ブログのタグ一覧を取得する',
          inputSchema => { type => 'object', required => ['blog_id'],
            properties => { blog_id => { type => 'integer' } } } },
        { name => 'asset_list',    description => '指定ブログのアセット一覧を取得する',
          inputSchema => { type => 'object', required => ['blog_id'],
            properties => { blog_id => { type => 'integer' }, limit => { type => 'integer' },
                            class => { type => 'string' } } } },
        { name => 'asset_get',     description => 'アセットIDを指定して1件取得する',
          inputSchema => { type => 'object', required => ['asset_id'],
            properties => { asset_id => { type => 'integer' } } } },
        { name => 'template_list', description => '指定ブログのテンプレート一覧を取得する',
          inputSchema => { type => 'object', required => ['blog_id'],
            properties => { blog_id => { type => 'integer' }, type => { type => 'string' } } } },
        { name => 'template_get',  description => 'テンプレートIDを指定して1件取得する（本文含む）',
          inputSchema => { type => 'object', required => ['template_id'],
            properties => { template_id => { type => 'integer' } } } },
        { name => 'template_update', description => 'テンプレートの本文を更新する',
          inputSchema => { type => 'object', required => ['template_id','body'],
            properties => { template_id => { type => 'integer' }, body => { type => 'string' } } } },
    ];
}

1;
PERL

# 7. Tools/Entry.pm
cat > plugins/MTMCP/lib/MTMCP/Tools/Entry.pm << 'PERL'
package MTMCP::Tools::Entry;
use strict;
use warnings;
use MT::Entry;
use MT::Placement;

sub list {
    my ($app, $args) = @_;
    my $blog_id = $args->{blog_id} or die "blog_id is required\n";
    my $limit   = $args->{limit}   // 20;
    my $status  = $args->{status}  // 'publish';
    my %terms = (blog_id => $blog_id);
    $terms{status} = MT::Entry::RELEASE() if $status eq 'publish';
    $terms{status} = MT::Entry::HOLD()    if $status eq 'draft';
    my @entries = MT::Entry->load(\%terms,
        { limit => $limit, sort => 'authored_on', direction => 'descend' });
    return [ map { _to_hash($_) } @entries ];
}

sub get {
    my ($app, $args) = @_;
    my $entry_id = $args->{entry_id} or die "entry_id is required\n";
    my $entry = MT::Entry->load($entry_id) or die "Entry not found: $entry_id\n";
    return _to_hash($entry, 1);
}

sub create {
    my ($app, $args) = @_;
    my $blog_id = $args->{blog_id} or die "blog_id is required\n";
    my $title   = $args->{title}   or die "title is required\n";
    my $entry = MT::Entry->new;
    $entry->blog_id($blog_id);
    $entry->title($title);
    $entry->text($args->{body} // '');
    $entry->status(($args->{status}//'draft') eq 'publish' ? MT::Entry::RELEASE() : MT::Entry::HOLD());
    $entry->author_id($app ? $app->user->id : 1);
    $entry->save or die $entry->errstr . "\n";
    _set_categories($entry, $args->{category_ids}) if $args->{category_ids};
    return { entry_id => $entry->id, status => 'created', title => $entry->title };
}

sub update {
    my ($app, $args) = @_;
    my $entry_id = $args->{entry_id} or die "entry_id is required\n";
    my $entry = MT::Entry->load($entry_id) or die "Entry not found: $entry_id\n";
    $entry->title($args->{title}) if defined $args->{title};
    $entry->text($args->{body})   if defined $args->{body};
    if (defined $args->{status}) {
        $entry->status($args->{status} eq 'publish' ? MT::Entry::RELEASE() : MT::Entry::HOLD());
    }
    $entry->save or die $entry->errstr . "\n";
    return { entry_id => $entry->id, status => 'updated', title => $entry->title };
}

sub _to_hash {
    my ($entry, $full) = @_;
    my $hash = {
        id          => $entry->id,
        title       => $entry->title,
        status      => $entry->status == MT::Entry::RELEASE() ? 'publish' : 'draft',
        authored_on => $entry->authored_on,
        permalink   => eval { $entry->permalink } // '',
    };
    if ($full) {
        $hash->{body}    = $entry->text      // '';
        $hash->{excerpt} = $entry->excerpt   // '';
        $hash->{more}    = $entry->text_more // '';
    }
    my @placements = MT::Placement->load({ entry_id => $entry->id });
    if (@placements) {
        require MT::Category;
        $hash->{categories} = [
            map { my $c = MT::Category->load($_->category_id); $c ? { id => $c->id, label => $c->label } : () }
            @placements
        ];
    }
    return $hash;
}

sub _set_categories {
    my ($entry, $cat_ids) = @_;
    MT::Placement->remove({ entry_id => $entry->id });
    my $is_primary = 1;
    for my $cat_id (@$cat_ids) {
        my $p = MT::Placement->new;
        $p->entry_id($entry->id);
        $p->blog_id($entry->blog_id);
        $p->category_id($cat_id);
        $p->is_primary($is_primary);
        $p->save or die $p->errstr . "\n";
        $is_primary = 0;
    }
}

1;
PERL

# 8. Tools/Category.pm
cat > plugins/MTMCP/lib/MTMCP/Tools/Category.pm << 'PERL'
package MTMCP::Tools::Category;
use strict;
use warnings;
use MT::Category;
use MT::Tag;
use MT::ObjectTag;

sub list {
    my ($app, $args) = @_;
    my $blog_id = $args->{blog_id} or die "blog_id is required\n";
    my @cats = MT::Category->load({ blog_id => $blog_id },
        { sort => 'label', direction => 'ascend' });
    return [ map { { id => $_->id, label => $_->label, parent_id => $_->parent || undef } } @cats ];
}

sub list_tags {
    my ($app, $args) = @_;
    my $blog_id = $args->{blog_id} or die "blog_id is required\n";
    my @obj_tags = MT::ObjectTag->load({ blog_id => $blog_id, object_datasource => 'entry' });
    my %tag_ids = map { $_->tag_id => 1 } @obj_tags;
    my @tags;
    if (%tag_ids) {
        @tags = MT::Tag->load({ id => [keys %tag_ids] }, { sort => 'name', direction => 'ascend' });
    }
    return [ map { { id => $_->id, name => $_->name } } @tags ];
}

1;
PERL

# 9. Tools/Asset.pm
cat > plugins/MTMCP/lib/MTMCP/Tools/Asset.pm << 'PERL'
package MTMCP::Tools::Asset;
use strict;
use warnings;
use MT::Asset;

sub list {
    my ($app, $args) = @_;
    my $blog_id = $args->{blog_id} or die "blog_id is required\n";
    my $limit   = $args->{limit}   // 20;
    my %terms = (blog_id => $blog_id);
    $terms{class} = $args->{class} if $args->{class};
    my @assets = MT::Asset->load(\%terms,
        { limit => $limit, sort => 'created_on', direction => 'descend' });
    return [ map { _to_hash($_) } @assets ];
}

sub get {
    my ($app, $args) = @_;
    my $asset_id = $args->{asset_id} or die "asset_id is required\n";
    my $asset = MT::Asset->load($asset_id) or die "Asset not found: $asset_id\n";
    return _to_hash($asset, 1);
}

sub _to_hash {
    my ($asset, $full) = @_;
    my $hash = {
        id         => $asset->id,
        label      => $asset->label // '',
        file_name  => $asset->file_name,
        class      => $asset->class,
        url        => eval { $asset->url } // '',
        created_on => $asset->created_on,
    };
    if ($full) {
        $hash->{file_path}    = $asset->file_path    // '';
        $hash->{mime_type}    = $asset->mime_type    // '';
        $hash->{file_size}    = $asset->file_size    // 0;
        $hash->{image_width}  = $asset->image_width  // 0 if $asset->class eq 'image';
        $hash->{image_height} = $asset->image_height // 0 if $asset->class eq 'image';
    }
    return $hash;
}

1;
PERL

# 10. Tools/Template.pm
cat > plugins/MTMCP/lib/MTMCP/Tools/Template.pm << 'PERL'
package MTMCP::Tools::Template;
use strict;
use warnings;
use MT::Template;

sub list {
    my ($app, $args) = @_;
    my $blog_id = $args->{blog_id} or die "blog_id is required\n";
    my %terms = (blog_id => $blog_id);
    $terms{type} = $args->{type} if $args->{type};
    my @tmpls = MT::Template->load(\%terms, { sort => 'name', direction => 'ascend' });
    return [ map { _to_hash($_) } @tmpls ];
}

sub get {
    my ($app, $args) = @_;
    my $tmpl_id = $args->{template_id} or die "template_id is required\n";
    my $tmpl = MT::Template->load($tmpl_id) or die "Template not found: $tmpl_id\n";
    return _to_hash($tmpl, 1);
}

sub update {
    my ($app, $args) = @_;
    my $tmpl_id = $args->{template_id} or die "template_id is required\n";
    die "body is required\n" unless defined $args->{body};
    my $tmpl = MT::Template->load($tmpl_id) or die "Template not found: $tmpl_id\n";
    $tmpl->text($args->{body});
    $tmpl->save or die $tmpl->errstr . "\n";
    return { template_id => $tmpl->id, status => 'updated', name => $tmpl->name };
}

sub _to_hash {
    my ($tmpl, $full) = @_;
    my $hash = { id => $tmpl->id, name => $tmpl->name, type => $tmpl->type };
    $hash->{body} = $tmpl->text // '' if $full;
    return $hash;
}

1;
PERL

# 11. README.md
cat > README.md << 'MD'
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
MD

# 12. コミット & プッシュ
git add -A
git commit -m "feat: add MT MCP Server plugin (initial implementation)

- MT9 対応 MCP (Model Context Protocol) サーバープラグイン
- Streamable HTTP トランスポート (JSON-RPC 2.0)
- Bearer token 認証（MT管理画面で設定）
- 対応ツール: entry, category, tag, asset, template の CRUD"

git push origin "$BRANCH"

echo ""
echo "✅ Push 完了！"
echo ""
echo "PR作成URL:"
echo "https://github.com/redamoon/mt-mcp/compare/main...$BRANCH?quick_pull=1&title=feat%3A+add+MT+MCP+Server+plugin&body=MT9+%E5%AF%BE%E5%BF%9C+MCP+%E3%82%B5%E3%83%BC%E3%83%90%E3%83%BC%E3%83%97%E3%83%A9%E3%82%B0%E3%82%A4%E3%83%B3%E3%81%AE%E5%88%9D%E6%9C%9F%E5%AE%9F%E8%A3%85"
