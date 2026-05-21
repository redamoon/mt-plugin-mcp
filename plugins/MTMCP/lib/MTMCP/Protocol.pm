package MTMCP::Protocol;
use strict;
use warnings;
use utf8;
use JSON;

our $PROTOCOL_VERSION = '2024-11-05';

my $json = JSON->new->ascii->canonical;

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
    'template_list'        => sub { require MTMCP::Tools::Template;     MTMCP::Tools::Template::list(@_)         },
    'template_get'         => sub { require MTMCP::Tools::Template;     MTMCP::Tools::Template::get(@_)          },
    'template_update'      => sub { require MTMCP::Tools::Template;     MTMCP::Tools::Template::update(@_)       },
    'content_type_list'    => sub { require MTMCP::Tools::ContentType;  MTMCP::Tools::ContentType::list(@_)      },
    'content_type_get'     => sub { require MTMCP::Tools::ContentType;  MTMCP::Tools::ContentType::get(@_)       },
    'content_type_create'  => sub { require MTMCP::Tools::ContentType;  MTMCP::Tools::ContentType::create(@_)    },
    'content_data_list'    => sub { require MTMCP::Tools::ContentData;  MTMCP::Tools::ContentData::list(@_)      },
    'content_data_get'     => sub { require MTMCP::Tools::ContentData;  MTMCP::Tools::ContentData::get(@_)       },
    'content_data_create'  => sub { require MTMCP::Tools::ContentData;  MTMCP::Tools::ContentData::create(@_)    },
    'content_data_update'  => sub { require MTMCP::Tools::ContentData;  MTMCP::Tools::ContentData::update(@_)    },
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
        {
            name        => 'content_type_list',
            description => '指定ブログのコンテンツタイプ一覧を取得する。content_data_* 操作の前に呼んで content_type_id を確認すること。',
            inputSchema => {
                type     => 'object',
                required => ['blog_id'],
                properties => {
                    blog_id => { type => 'integer', description => 'ブログID（blog_list で確認）' },
                },
            },
        },
        {
            name        => 'content_type_get',
            description => 'コンテンツタイプの詳細（フィールド定義一覧）を取得する。content_data_create/update でフィールドIDを確認するために使う。',
            inputSchema => {
                type     => 'object',
                required => ['content_type_id'],
                properties => {
                    content_type_id => { type => 'integer', description => 'コンテンツタイプID（content_type_list で確認）' },
                },
            },
        },
        {
            name        => 'content_type_create',
            description => 'コンテンツタイプを新規作成する。fields を省略すると「タイトル」「本文」の2フィールドが作られる。',
            inputSchema => {
                type     => 'object',
                required => ['blog_id', 'name'],
                properties => {
                    blog_id     => { type => 'integer', description => 'ブログID（blog_list で確認）' },
                    name        => { type => 'string',  description => 'コンテンツタイプ名' },
                    description => { type => 'string',  description => '説明文' },
                    fields      => {
                        type  => 'array',
                        items => {
                            type       => 'object',
                            properties => {
                                type        => { type => 'string',  description => 'single_line_text / multi_line_text など' },
                                label       => { type => 'string',  description => 'フィールドラベル' },
                                order       => { type => 'integer', description => '表示順' },
                                label_field => { type => 'boolean', description => 'データラベルに使うフィールド' },
                                required    => { type => 'boolean', description => '必須かどうか' },
                            },
                        },
                    },
                },
            },
        },
        {
            name        => 'content_data_list',
            description => '指定コンテンツタイプのコンテンツデータ一覧を取得する。',
            inputSchema => {
                type     => 'object',
                required => ['content_type_id'],
                properties => {
                    content_type_id => { type => 'integer', description => 'コンテンツタイプID' },
                    blog_id         => { type => 'integer', description => 'ブログID（省略可）' },
                    limit           => { type => 'integer', description => '取得件数（デフォルト20）' },
                    status          => { type => 'string',  enum => ['publish','draft','all'], description => 'ステータス' },
                },
            },
        },
        {
            name        => 'content_data_get',
            description => 'コンテンツデータIDを指定して1件取得する。フィールド値と各フィールドのラベルも返す。',
            inputSchema => {
                type     => 'object',
                required => ['content_data_id'],
                properties => {
                    content_data_id => { type => 'integer', description => 'コンテンツデータID' },
                },
            },
        },
        {
            name        => 'content_data_create',
            description => 'コンテンツデータを新規作成する。事前に content_type_get でフィールドIDを確認すること。fields のキーはフィールドID（整数を文字列化）。',
            inputSchema => {
                type     => 'object',
                required => ['content_type_id', 'blog_id'],
                properties => {
                    content_type_id => { type => 'integer', description => 'コンテンツタイプID' },
                    blog_id         => { type => 'integer', description => 'ブログID' },
                    status          => { type => 'string',  enum => ['publish','draft'], description => '省略時は draft' },
                    fields          => { type => 'object',  description => 'フィールドID => 値 のオブジェクト（例: {"1": "テキスト", "2": "値"}）' },
                    author_id       => { type => 'integer', description => '著者ユーザーID（省略時は管理者）' },
                },
            },
        },
        {
            name        => 'content_data_update',
            description => '既存のコンテンツデータを更新する。fields は指定したフィールドのみ上書き（未指定フィールドは保持）。',
            inputSchema => {
                type     => 'object',
                required => ['content_data_id'],
                properties => {
                    content_data_id => { type => 'integer', description => '更新するコンテンツデータID' },
                    status          => { type => 'string',  enum => ['publish','draft'], description => '新しいステータス' },
                    fields          => { type => 'object',  description => 'フィールドID => 値 のオブジェクト（部分更新可）' },
                },
            },
        },
    ];
}

1;
