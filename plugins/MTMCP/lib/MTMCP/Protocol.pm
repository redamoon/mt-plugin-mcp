package MTMCP::Protocol;
use strict;
use warnings;
use JSON;

our $PROTOCOL_VERSION = '2024-11-05';

my $json = JSON->new->utf8->canonical;

my %TOOL_HANDLERS = (
    'blog_list'       => sub { require MTMCP::Tools::Blog;     MTMCP::Tools::Blog::list(@_)         },
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
            capabilities    => { tools => { listChanged => JSON::false } },
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
                isError => JSON::true,
            });
        }
        return _result($id, {
            content => [{ type => 'text', text => $json->encode($result) }],
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
        {
            name        => 'blog_list',
            description => 'Movable Type のブログ（サイト）一覧を取得する。blog_id が不明なときは必ずこのツールで確認してから操作すること。',
            inputSchema => { type => 'object', properties => {} },
        },
        {
            name        => 'entry_list',
            description => '指定ブログの記事一覧を取得する。blog_id が不明なら先に blog_list を呼ぶこと。',
            inputSchema => {
                type     => 'object',
                required => ['blog_id'],
                properties => {
                    blog_id => { type => 'integer', description => 'ブログID（blog_list で確認）' },
                    limit   => { type => 'integer', description => '取得件数（デフォルト20）' },
                    status  => { type => 'string', enum => ['publish','draft','all'], description => '記事ステータス' },
                },
            },
        },
        {
            name        => 'entry_get',
            description => '記事IDを指定して1件の記事を本文ごと取得する。',
            inputSchema => {
                type     => 'object',
                required => ['entry_id'],
                properties => {
                    entry_id => { type => 'integer', description => '記事ID' },
                },
            },
        },
        {
            name        => 'entry_create',
            description => '新規記事を作成する。blog_id が不明なら先に blog_list を呼ぶこと。カテゴリを指定したい場合は先に category_list で ID を確認すること。status を省略すると下書きになる。',
            inputSchema => {
                type     => 'object',
                required => ['blog_id', 'title'],
                properties => {
                    blog_id      => { type => 'integer', description => 'ブログID（blog_list で確認）' },
                    title        => { type => 'string',  description => '記事タイトル' },
                    body         => { type => 'string',  description => '記事本文（HTML可）' },
                    status       => { type => 'string',  enum => ['publish','draft'], description => '省略時は draft（下書き）' },
                    category_ids => { type => 'array', items => { type => 'integer' }, description => 'カテゴリIDの配列（category_list で確認）' },
                    author_id    => { type => 'integer', description => '著者ユーザーID（省略時は管理者ユーザー）' },
                },
            },
        },
        {
            name        => 'entry_update',
            description => '既存の記事を更新する。指定したフィールドのみ上書きされる。',
            inputSchema => {
                type     => 'object',
                required => ['entry_id'],
                properties => {
                    entry_id => { type => 'integer', description => '更新する記事のID' },
                    title    => { type => 'string',  description => '新しいタイトル' },
                    body     => { type => 'string',  description => '新しい本文' },
                    status   => { type => 'string',  enum => ['publish','draft'], description => '新しいステータス' },
                },
            },
        },
        {
            name        => 'category_list',
            description => '指定ブログのカテゴリ一覧を取得する。entry_create でカテゴリを指定する前に呼ぶこと。',
            inputSchema => {
                type     => 'object',
                required => ['blog_id'],
                properties => {
                    blog_id => { type => 'integer', description => 'ブログID' },
                },
            },
        },
        {
            name        => 'tag_list',
            description => '指定ブログで使われているタグ一覧を取得する。',
            inputSchema => {
                type     => 'object',
                required => ['blog_id'],
                properties => {
                    blog_id => { type => 'integer', description => 'ブログID' },
                },
            },
        },
        {
            name        => 'asset_list',
            description => '指定ブログのアセット（画像・ファイルなど）一覧を取得する。',
            inputSchema => {
                type     => 'object',
                required => ['blog_id'],
                properties => {
                    blog_id => { type => 'integer', description => 'ブログID' },
                    limit   => { type => 'integer' },
                    class   => { type => 'string',  description => 'image / file など' },
                },
            },
        },
        {
            name        => 'asset_get',
            description => 'アセットIDを指定して1件取得する。',
            inputSchema => {
                type     => 'object',
                required => ['asset_id'],
                properties => {
                    asset_id => { type => 'integer', description => 'アセットID' },
                },
            },
        },
        {
            name        => 'template_list',
            description => '指定ブログのテンプレート一覧を取得する。',
            inputSchema => {
                type     => 'object',
                required => ['blog_id'],
                properties => {
                    blog_id => { type => 'integer', description => 'ブログID' },
                    type    => { type => 'string',  description => 'テンプレートタイプ（index, individual など）' },
                },
            },
        },
        {
            name        => 'template_get',
            description => 'テンプレートIDを指定して本文ごと取得する。',
            inputSchema => {
                type     => 'object',
                required => ['template_id'],
                properties => {
                    template_id => { type => 'integer', description => 'テンプレートID' },
                },
            },
        },
        {
            name        => 'template_update',
            description => 'テンプレートの本文を更新する。',
            inputSchema => {
                type     => 'object',
                required => ['template_id', 'body'],
                properties => {
                    template_id => { type => 'integer', description => 'テンプレートID' },
                    body        => { type => 'string',  description => '新しいテンプレート本文' },
                },
            },
        },
    ];
}

1;
