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
