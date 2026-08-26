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
    'entry_delete'    => sub { require MTMCP::Tools::Entry;    MTMCP::Tools::Entry::remove(@_)      },
    'entry_preview'   => sub { require MTMCP::Tools::Entry;    MTMCP::Tools::Entry::preview(@_)     },
    'entry_export'    => sub { require MTMCP::Tools::Entry;    MTMCP::Tools::Entry::export(@_)      },
    'entry_import'    => sub { require MTMCP::Tools::Entry;    MTMCP::Tools::Entry::import_entries(@_) },
    'page_list'       => sub { require MTMCP::Tools::Page;     MTMCP::Tools::Page::list(@_)         },
    'page_get'        => sub { require MTMCP::Tools::Page;     MTMCP::Tools::Page::get(@_)          },
    'page_create'     => sub { require MTMCP::Tools::Page;     MTMCP::Tools::Page::create(@_)       },
    'page_update'     => sub { require MTMCP::Tools::Page;     MTMCP::Tools::Page::update(@_)       },
    'page_delete'     => sub { require MTMCP::Tools::Page;     MTMCP::Tools::Page::remove(@_)       },
    'page_preview'    => sub { require MTMCP::Tools::Page;     MTMCP::Tools::Page::preview(@_)      },
    'category_list'      => sub { require MTMCP::Tools::Category; MTMCP::Tools::Category::list(@_)      },
    'category_get'       => sub { require MTMCP::Tools::Category; MTMCP::Tools::Category::get(@_)       },
    'category_create'    => sub { require MTMCP::Tools::Category; MTMCP::Tools::Category::create(@_)    },
    'category_update'    => sub { require MTMCP::Tools::Category; MTMCP::Tools::Category::update(@_)    },
    'category_delete'    => sub { require MTMCP::Tools::Category; MTMCP::Tools::Category::remove(@_)    },
    'category_permutate' => sub { require MTMCP::Tools::Category; MTMCP::Tools::Category::permutate(@_) },
    'category_set_list'   => sub { require MTMCP::Tools::CategorySet; MTMCP::Tools::CategorySet::list(@_)   },
    'category_set_get'    => sub { require MTMCP::Tools::CategorySet; MTMCP::Tools::CategorySet::get(@_)    },
    'category_set_create' => sub { require MTMCP::Tools::CategorySet; MTMCP::Tools::CategorySet::create(@_) },
    'category_set_update' => sub { require MTMCP::Tools::CategorySet; MTMCP::Tools::CategorySet::update(@_) },
    'category_set_delete' => sub { require MTMCP::Tools::CategorySet; MTMCP::Tools::CategorySet::remove(@_) },
    'tag_list'        => sub { require MTMCP::Tools::Tag;      MTMCP::Tools::Tag::list(@_)         },
    'tag_rename'      => sub { require MTMCP::Tools::Tag;      MTMCP::Tools::Tag::rename(@_)       },
    'tag_delete'      => sub { require MTMCP::Tools::Tag;      MTMCP::Tools::Tag::remove(@_)       },
    'folder_list'     => sub { require MTMCP::Tools::Folder;   MTMCP::Tools::Folder::list(@_)       },
    'folder_get'      => sub { require MTMCP::Tools::Folder;   MTMCP::Tools::Folder::get(@_)        },
    'folder_create'   => sub { require MTMCP::Tools::Folder;   MTMCP::Tools::Folder::create(@_)     },
    'folder_update'   => sub { require MTMCP::Tools::Folder;   MTMCP::Tools::Folder::update(@_)     },
    'folder_delete'   => sub { require MTMCP::Tools::Folder;   MTMCP::Tools::Folder::remove(@_)     },
    'asset_list'      => sub { require MTMCP::Tools::Asset;    MTMCP::Tools::Asset::list(@_)        },
    'asset_get'       => sub { require MTMCP::Tools::Asset;    MTMCP::Tools::Asset::get(@_)         },
    'asset_upload'    => sub { require MTMCP::Tools::Asset;    MTMCP::Tools::Asset::upload(@_)      },
    'asset_delete'    => sub { require MTMCP::Tools::Asset;    MTMCP::Tools::Asset::remove(@_)      },
    'asset_thumbnail' => sub { require MTMCP::Tools::Asset;    MTMCP::Tools::Asset::thumbnail(@_)   },
    'template_list'        => sub { require MTMCP::Tools::Template;     MTMCP::Tools::Template::list(@_)         },
    'template_get'         => sub { require MTMCP::Tools::Template;     MTMCP::Tools::Template::get(@_)          },
    'template_create'      => sub { require MTMCP::Tools::Template;     MTMCP::Tools::Template::create(@_)       },
    'template_update'      => sub { require MTMCP::Tools::Template;     MTMCP::Tools::Template::update(@_)       },
    'template_delete'      => sub { require MTMCP::Tools::Template;     MTMCP::Tools::Template::remove(@_)       },
    'template_validate'    => sub { require MTMCP::Tools::Template;     MTMCP::Tools::Template::validate(@_)     },
    'template_preview'     => sub { require MTMCP::Tools::Template;     MTMCP::Tools::Template::preview(@_)      },
    'template_tag_list'    => sub { require MTMCP::Tools::Template;     MTMCP::Tools::Template::tag_list(@_)     },
    'templatemap_list'     => sub { require MTMCP::Tools::TemplateMap;  MTMCP::Tools::TemplateMap::list(@_)      },
    'templatemap_get'      => sub { require MTMCP::Tools::TemplateMap;  MTMCP::Tools::TemplateMap::get(@_)       },
    'templatemap_create'   => sub { require MTMCP::Tools::TemplateMap;  MTMCP::Tools::TemplateMap::create(@_)    },
    'templatemap_update'   => sub { require MTMCP::Tools::TemplateMap;  MTMCP::Tools::TemplateMap::update(@_)    },
    'templatemap_delete'   => sub { require MTMCP::Tools::TemplateMap;  MTMCP::Tools::TemplateMap::remove(@_)    },
    'widgetset_list'       => sub { require MTMCP::Tools::Widget;       MTMCP::Tools::Widget::list(@_)           },
    'widgetset_get'        => sub { require MTMCP::Tools::Widget;       MTMCP::Tools::Widget::get(@_)            },
    'widgetset_create'     => sub { require MTMCP::Tools::Widget;       MTMCP::Tools::Widget::create(@_)         },
    'widgetset_update'     => sub { require MTMCP::Tools::Widget;       MTMCP::Tools::Widget::update(@_)         },
    'widgetset_delete'     => sub { require MTMCP::Tools::Widget;       MTMCP::Tools::Widget::remove(@_)         },
    'widget_list'          => sub { require MTMCP::Tools::Widget;       MTMCP::Tools::Widget::list_widgets(@_)   },
    'log_list'             => sub { require MTMCP::Tools::Log;          MTMCP::Tools::Log::list(@_)              },
    'log_get'              => sub { require MTMCP::Tools::Log;          MTMCP::Tools::Log::get(@_)               },
    'user_list'            => sub { require MTMCP::Tools::User;         MTMCP::Tools::User::list(@_)              },
    'user_get'             => sub { require MTMCP::Tools::User;         MTMCP::Tools::User::get(@_)               },
    'user_create'          => sub { require MTMCP::Tools::User;         MTMCP::Tools::User::create(@_)            },
    'user_delete'          => sub { require MTMCP::Tools::User;         MTMCP::Tools::User::remove(@_)            },
    'user_unlock'          => sub { require MTMCP::Tools::User;         MTMCP::Tools::User::unlock(@_)            },
    'user_update'          => sub { require MTMCP::Tools::User;         MTMCP::Tools::User::update(@_)            },
    'user_recover_password'=> sub { require MTMCP::Tools::User;         MTMCP::Tools::User::recover_password(@_)  },
    'rebuild_site'         => sub { require MTMCP::Tools::Rebuild;      MTMCP::Tools::Rebuild::site(@_)          },
    'rebuild_template'     => sub { require MTMCP::Tools::Rebuild;      MTMCP::Tools::Rebuild::template(@_)      },
    'rebuild_entry'        => sub { require MTMCP::Tools::Rebuild;      MTMCP::Tools::Rebuild::entry(@_)         },
    'rebuild_page'         => sub { require MTMCP::Tools::Rebuild;      MTMCP::Tools::Rebuild::page(@_)          },
    'rebuild_content_data' => sub { require MTMCP::Tools::Rebuild;      MTMCP::Tools::Rebuild::content_data(@_)  },
    'content_type_list'    => sub { require MTMCP::Tools::ContentType;  MTMCP::Tools::ContentType::list(@_)      },
    'content_type_get'     => sub { require MTMCP::Tools::ContentType;  MTMCP::Tools::ContentType::get(@_)       },
    'content_type_create'  => sub { require MTMCP::Tools::ContentType;  MTMCP::Tools::ContentType::create(@_)    },
    'content_data_list'    => sub { require MTMCP::Tools::ContentData;  MTMCP::Tools::ContentData::list(@_)      },
    'content_data_get'     => sub { require MTMCP::Tools::ContentData;  MTMCP::Tools::ContentData::get(@_)       },
    'content_data_create'  => sub { require MTMCP::Tools::ContentData;  MTMCP::Tools::ContentData::create(@_)    },
    'content_data_update'  => sub { require MTMCP::Tools::ContentData;  MTMCP::Tools::ContentData::update(@_)    },
    'content_data_delete'  => sub { require MTMCP::Tools::ContentData;  MTMCP::Tools::ContentData::remove(@_)    },
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
            serverInfo      => { name => 'MT MCP Server', version => '0.7.0' },
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
                    offset  => { type => 'integer', description => '取得開始位置（ページネーション用、デフォルト0）' },
                    status  => { type => 'string', enum => ['publish','draft','all'], description => '記事ステータス' },
                    keyword => { type => 'string', description => 'タイトル・本文に対する DB 側の部分一致検索キーワード（件数上限なし）' },
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
            name        => 'entry_delete',
            description => '記事を削除する。取り消せない。DeleteFilesAtRebuild が有効なら Individual アーカイブの公開ファイルも削除する。無効なら公開ディレクトリに HTML が残ることがある。confirm: true 必須。',
            inputSchema => {
                type     => 'object',
                required => ['entry_id', 'confirm'],
                properties => {
                    entry_id => { type => 'integer', description => '削除する記事のID' },
                    confirm => { type => 'boolean', description => 'true のときだけ実行する（取り消せない操作の確認）' },
                },
            },
        },
        {
            name        => 'entry_preview',
            description => '記事を Individual アーカイブテンプレートでビルドして HTML を返す（公開ファイルは書かない）。entry_create の前に見た目を確認するために使う。entry_id か title/body が必要。Page ID は指定できない（Entry not found）。preferred な Individual マップが必要。権限は記事の作成（create_post）。',
            inputSchema => {
                type     => 'object',
                required => ['blog_id'],
                properties => {
                    blog_id        => { type => 'integer', description => 'ブログID（blog_list で確認）' },
                    entry_id       => { type => 'integer', description => '既存記事のID（Page ID は不可。指定フィールドがあれば未保存上書き）' },
                    title          => { type => 'string',  description => '未保存プレビュー時のタイトル、または既存記事への上書き' },
                    body           => { type => 'string',  description => '未保存プレビュー時の本文、または既存記事への上書き' },
                    more           => { type => 'string',  description => '続き（text_more）' },
                    excerpt        => { type => 'string',  description => '概要' },
                    category_ids   => { type => 'array', items => { type => 'integer' }, description => 'カテゴリIDの配列（先頭が主カテゴリ。保存しない）' },
                    convert_breaks => { type => 'string',  description => '改行変換。省略時は既存記事の値、未保存ならブログ設定' },
                    status         => { type => 'string',  enum => ['publish','draft'], description => '見た目用のみ。公開ファイルは出さない' },
                },
            },
        },
        {
            name        => 'entry_export',
            description => '記事1件を Movable Type の Import/Export テキストで返す。全件はコンテキスト溢れしやすいので entry_id 必須。Page は拒否。'
                . '本文は文字数上限で打ち切る。サイトバックアップや移行用一括投入の代替ではない。権限はブログのエクスポート（export_blog）。',
            inputSchema => {
                type     => 'object',
                required => ['entry_id'],
                properties => {
                    entry_id => { type => 'integer', description => '記事ID（Page ID は不可。entry_list で確認）' },
                    blog_id  => { type => 'integer', description => 'ブログID。指定時は記事の blog_id と一致必須' },
                },
            },
        },
        {
            name        => 'entry_import',
            description => '記事を一括作成する破壊的操作。MT Import/Export テキスト（body）から記事を作る。confirm: true 必須。'
                . '著者は常に呼び出しユーザー（ユーザー新規作成なし）。ImportPath は使わない。default_status 省略時は draft。再構築しない。'
                . '本文は 1MB まで。サイトバックアップや移行用一括投入の代替ではない。権限はブログのインポート（import_blog）。',
            inputSchema => {
                type     => 'object',
                required => ['blog_id', 'body', 'confirm'],
                properties => {
                    blog_id         => { type => 'integer', description => 'ブログID（blog_list で確認）' },
                    body            => { type => 'string',  description => 'MT Import/Export テキスト。ファイルパスや ImportPath は不可' },
                    confirm         => { type => 'boolean', description => 'true のときだけ実行する' },
                    default_status  => { type => 'string', enum => ['draft', 'publish'], description => '省略時は draft（サイト既定の公開にはしない）' },
                },
            },
        },
        {
            name        => 'page_list',
            description => '指定ブログの固定ページ一覧を取得する。記事の entry_list とは別。フォルダで絞る場合は folder_list で ID を確認してから folder_id を渡すこと。',
            inputSchema => {
                type     => 'object',
                required => ['blog_id'],
                properties => {
                    blog_id   => { type => 'integer', description => 'ブログID（blog_list で確認）' },
                    limit     => { type => 'integer', description => '取得件数（デフォルト20）' },
                    offset    => { type => 'integer', description => '取得開始位置（ページネーション用、デフォルト0）' },
                    status    => { type => 'string', enum => ['publish','draft','all'], description => 'ページステータス（省略時は publish）' },
                    keyword   => { type => 'string', description => 'タイトル・本文に対する部分一致検索キーワード' },
                    folder_id => { type => 'integer', description => 'フォルダID（folder_list で確認。指定時はそのフォルダ配下のみ）' },
                },
            },
        },
        {
            name        => 'page_get',
            description => '固定ページIDを指定して1件を本文ごと取得する。記事IDを渡しても見つからない（entry_get を使うこと）。',
            inputSchema => {
                type     => 'object',
                required => ['page_id'],
                properties => {
                    page_id => { type => 'integer', description => '固定ページID' },
                },
            },
        },
        {
            name        => 'page_create',
            description => '固定ページを新規作成する。記事の entry_create とは別。フォルダは単数の folder_id（カテゴリIDは不可）。フォルダIDは folder_list で確認する。status 省略時は下書き。公開ファイルは作らないので、公開するには rebuild_page を使うこと。',
            inputSchema => {
                type     => 'object',
                required => ['blog_id', 'title'],
                properties => {
                    blog_id    => { type => 'integer', description => 'ブログID（blog_list で確認）' },
                    title      => { type => 'string',  description => 'ページタイトル' },
                    body       => { type => 'string',  description => '本文（HTML可）' },
                    status     => { type => 'string',  enum => ['publish','draft'], description => '省略時は draft（下書き）' },
                    folder_id  => { type => 'integer', description => 'フォルダID（1件。folder_list で確認。カテゴリIDは不可）' },
                    basename   => { type => 'string',  description => '出力ファイル名のベース（省略時は MT が自動生成）' },
                    author_id  => { type => 'integer', description => '著者ユーザーID（省略時は管理者ユーザー）' },
                },
            },
        },
        {
            name        => 'page_update',
            description => '既存の固定ページを更新する。指定したフィールドのみ上書きされる。folder_id を省略するとフォルダは変えない。外すときは folder_id: 0 を明示する。公開ファイルは更新されないので、必要なら rebuild_page を使うこと。',
            inputSchema => {
                type     => 'object',
                required => ['page_id'],
                properties => {
                    page_id    => { type => 'integer', description => '更新する固定ページのID' },
                    title      => { type => 'string',  description => '新しいタイトル' },
                    body       => { type => 'string',  description => '新しい本文' },
                    status     => { type => 'string',  enum => ['publish','draft'], description => '新しいステータス' },
                    folder_id  => { type => 'integer', description => 'フォルダID。0 でフォルダ解除。省略時は変更しない' },
                    basename   => { type => 'string',  description => '新しい basename' },
                },
            },
        },
        {
            name        => 'page_delete',
            description => '固定ページを削除する。取り消せない。DeleteFilesAtRebuild が有効なら Page アーカイブの公開ファイルも削除する。無効なら公開ディレクトリに HTML が残ることがある。confirm: true 必須。',
            inputSchema => {
                type     => 'object',
                required => ['page_id', 'confirm'],
                properties => {
                    page_id => { type => 'integer', description => '削除する固定ページのID' },
                    confirm => { type => 'boolean', description => 'true のときだけ実行する（取り消せない操作の確認）' },
                },
            },
        },
        {
            name        => 'page_preview',
            description => '固定ページを Page アーカイブテンプレートでビルドして HTML を返す（ファイルは書き出さない）。page_id なら保存済み本文、blog_id と title/body なら未保存プレビュー。Page アーカイブの preferred マップが必要。権限はページの管理（manage_pages）。',
            inputSchema => {
                type     => 'object',
                properties => {
                    page_id => { type => 'integer', description => '既存ページのID（本文は DB。body があれば未保存上書き）' },
                    blog_id => { type => 'integer', description => '未保存プレビュー時のブログID' },
                    title   => { type => 'string',  description => '未保存プレビュー時のタイトル' },
                    body    => { type => 'string',  description => '未保存プレビュー時の本文、または既存ページへの上書き' },
                },
            },
        },
        {
            name        => 'category_list',
            description => '指定ブログのカテゴリ一覧を取得する。category_set_id を省略（または 0）すると記事カテゴリのみ。セット内カテゴリを取るときは category_set_id を渡す。フォルダ（folder_list）は含まない。記事の category_ids にはセット内カテゴリを渡さないこと。category_permutate の前に全 ID を取るために使う。',
            inputSchema => {
                type     => 'object',
                required => ['blog_id'],
                properties => {
                    blog_id         => { type => 'integer', description => 'ブログID' },
                    parent_id       => { type => 'integer', description => '親カテゴリID。0 でトップレベルのみ。省略時は全件' },
                    category_set_id => { type => 'integer', description => 'カテゴリセットID。省略時は記事カテゴリ（0）' },
                },
            },
        },
        {
            name        => 'category_get',
            description => 'カテゴリを1件取得する。フォルダIDは見つからない。セット内カテゴリも取得できる（返却の category_set_id で判別）。記事の category_ids にはセット内カテゴリを渡さないこと。',
            inputSchema => {
                type     => 'object',
                required => ['category_id'],
                properties => {
                    category_id => { type => 'integer', description => 'カテゴリID' },
                },
            },
        },
        {
            name        => 'category_create',
            description => 'カテゴリを作成する。category_set_id を省略すると記事カテゴリ（権限 save_category）。セット内なら同じブログのセットを指定し、権限は save_catefory_set_category（MT コアの綴り）。親は同じブログ・同じセット・class=category。記事の category_ids にはセット内カテゴリを渡さない。公開ファイルは自動再構築しない（必要なら rebuild_site の archive_type Category）。',
            inputSchema => {
                type     => 'object',
                required => ['blog_id', 'label'],
                properties => {
                    blog_id         => { type => 'integer', description => 'ブログID' },
                    label           => { type => 'string',  description => 'カテゴリ名（100文字以内。同じ親・同じセット内で一意）' },
                    basename        => { type => 'string',  description => 'URL パス用 basename（省略時は自動生成）' },
                    parent_id       => { type => 'integer', description => '親カテゴリID（省略時はトップレベル）' },
                    description     => { type => 'string',  description => '説明' },
                    category_set_id => { type => 'integer', description => 'カテゴリセットID。省略時は記事カテゴリ（0）' },
                },
            },
        },
        {
            name        => 'category_update',
            description => 'カテゴリを更新する。指定したフィールドのみ上書き（最低1つ必要）。フォルダIDは更新できない。セット内カテゴリはオブジェクトの category_set_id で権限が切り替わる（save_category / save_catefory_set_category）。',
            inputSchema => {
                type     => 'object',
                required => ['category_id'],
                properties => {
                    category_id => { type => 'integer', description => 'カテゴリID' },
                    label       => { type => 'string',  description => '新しいカテゴリ名（100文字以内）' },
                    basename    => { type => 'string',  description => '新しい basename' },
                    parent_id   => { type => 'integer', description => '新しい親カテゴリID。0 でトップレベル。同じセット内に限る' },
                    description => { type => 'string',  description => '新しい説明' },
                },
            },
        },
        {
            name        => 'category_delete',
            description => 'カテゴリを削除する。取り消せない操作なので、実行前に対象を確認すること。子カテゴリは親へ繰り上がる。記事カテゴリは delete_category、セット内は manage_category_set。公開ファイルは自動再構築しない（必要なら rebuild_site の archive_type Category）。confirm: true 必須。',
            inputSchema => {
                type     => 'object',
                required => ['category_id', 'confirm'],
                properties => {
                    category_id => { type => 'integer', description => '削除するカテゴリのID' },
                    confirm => { type => 'boolean', description => 'true のときだけ実行する（取り消せない操作の確認）' },
                },
            },
        },
        {
            name        => 'category_permutate',
            description => 'カテゴリ表示順を並べ替える。category_ids は先に category_list で取った当該スコープ（記事または指定セット）の全 ID と完全一致させること。省略時は Blog.category_order（edit_categories）。category_set_id 指定時は CategorySet.order（manage_category_set）。',
            inputSchema => {
                type     => 'object',
                required => ['blog_id', 'category_ids'],
                properties => {
                    blog_id         => { type => 'integer', description => 'ブログID' },
                    category_ids    => { type => 'array', items => { type => 'integer' }, description => '並べ替え後のカテゴリID（全件・重複なし）' },
                    category_set_id => { type => 'integer', description => 'カテゴリセットID。省略時は記事カテゴリ' },
                },
            },
        },
        {
            name        => 'category_set_list',
            description => '指定ブログのカテゴリセット一覧を取得する。コンテンツタイプの categories フィールドが参照するセット。権限はカテゴリセットの管理（manage_category_set）。',
            inputSchema => {
                type     => 'object',
                required => ['blog_id'],
                properties => {
                    blog_id => { type => 'integer', description => 'ブログID' },
                },
            },
        },
        {
            name        => 'category_set_get',
            description => 'カテゴリセットを1件取得する。配下カテゴリ（id, label, parent_id, basename）を含む。権限は manage_category_set。',
            inputSchema => {
                type     => 'object',
                required => ['category_set_id'],
                properties => {
                    category_set_id => { type => 'integer', description => 'カテゴリセットID' },
                },
            },
        },
        {
            name        => 'category_set_create',
            description => 'カテゴリセットを作成する。サイト内で名前は一意。セット内カテゴリは category_create に category_set_id を渡して追加する。権限は manage_category_set。',
            inputSchema => {
                type     => 'object',
                required => ['blog_id', 'name'],
                properties => {
                    blog_id => { type => 'integer', description => 'ブログID' },
                    name    => { type => 'string',  description => 'セット名（サイト内で一意）' },
                },
            },
        },
        {
            name        => 'category_set_update',
            description => 'カテゴリセットの名前だけを更新する（Data API と同じ）。categories 配列は渡さない（渡すとエラー）。セット内カテゴリは category_update を使う。権限は manage_category_set。',
            inputSchema => {
                type     => 'object',
                required => ['category_set_id', 'name'],
                properties => {
                    category_set_id => { type => 'integer', description => 'カテゴリセットID' },
                    name            => { type => 'string',  description => '新しいセット名' },
                },
            },
        },
        {
            name        => 'category_set_delete',
            description => 'カテゴリセットを削除する。取り消せない。配下カテゴリも削除される。コンテンツタイプの categories フィールドがこのセットを参照していてもコアはブロックしないため、削除前に content_type_get で参照の有無を確認すること。権限は manage_category_set。confirm: true 必須。',
            inputSchema => {
                type     => 'object',
                required => ['category_set_id', 'confirm'],
                properties => {
                    category_set_id => { type => 'integer', description => '削除するカテゴリセットのID' },
                    confirm => { type => 'boolean', description => 'true のときだけ実行する（取り消せない操作の確認）' },
                },
            },
        },

        {
            name        => 'tag_list',
            description => '指定ブログで使われているタグ一覧を取得する。記事・ページ・アセット・コンテンツデータの ObjectTag を対象にする。正規化専用レコードは除く。',
            inputSchema => {
                type     => 'object',
                required => ['blog_id'],
                properties => {
                    blog_id => { type => 'integer', description => 'ブログID' },
                },
            },
        },
        {
            name        => 'tag_rename',
            description => '指定サイト内のタグ名を変更する。取り消せない操作なので、実行前に tag_list で対象を確認すること。記事・ページ・アセット・コンテンツデータのタグが対象。他サイトで同じタグが使われている場合はサイト内だけ付け替え、他サイトは旧名のまま。同名タグへマージすることがある。公開ファイルは自動再構築しない（必要なら rebuild_entry / rebuild_site）。権限はタグの名前変更（rename_tag）とタグの編集（edit_tags）。',
            inputSchema => {
                type     => 'object',
                required => ['blog_id', 'tag_id', 'name'],
                properties => {
                    blog_id => { type => 'integer', description => 'ブログID' },
                    tag_id  => { type => 'integer', description => '変更するタグのID（tag_list で確認）' },
                    name    => { type => 'string',  description => '新しいタグ名' },
                },
            },
        },
        {
            name        => 'tag_delete',
            description => '指定サイトからタグを外す。取り消せない操作なので、実行前に対象のタグを確認すること。関連する記事・ページ・アセット・コンテンツデータから外れる。他サイトで使われていればタグマスタは残る。公開ファイルは自動再構築しない。権限はタグの削除（remove_tag）。confirm: true 必須。',
            inputSchema => {
                type     => 'object',
                required => ['blog_id', 'tag_id', 'confirm'],
                properties => {
                    blog_id => { type => 'integer', description => 'ブログID' },
                    tag_id  => { type => 'integer', description => '外すタグのID（tag_list で確認）' },
                    confirm => { type => 'boolean', description => 'true のときだけ実行する（取り消せない操作の確認）' },
                },
            },
        },
        {
            name        => 'folder_list',
            description => '指定ブログのフォルダ一覧を取得する。固定ページ用の置き場所であり、記事カテゴリ（category_list）とは別。page_create の folder_id を調べるときに使う。',
            inputSchema => {
                type     => 'object',
                required => ['blog_id'],
                properties => {
                    blog_id   => { type => 'integer', description => 'ブログID' },
                    parent_id => { type => 'integer', description => '親フォルダID。0 でトップレベルのみ。省略時は全件' },
                    keyword   => { type => 'string',  description => 'ラベル・basename の部分一致' },
                    limit     => { type => 'integer', description => '取得件数' },
                    offset    => { type => 'integer', description => '取得開始位置' },
                },
            },
        },
        {
            name        => 'folder_get',
            description => 'フォルダIDを指定して1件取得する。カテゴリIDを渡すと Folder not found になる。',
            inputSchema => {
                type     => 'object',
                required => ['folder_id'],
                properties => {
                    folder_id => { type => 'integer', description => 'フォルダID' },
                },
            },
        },
        {
            name        => 'folder_create',
            description => '固定ページ用フォルダを作成する。記事カテゴリの作成ではない。親は同じブログのフォルダに限る。',
            inputSchema => {
                type     => 'object',
                required => ['blog_id', 'label'],
                properties => {
                    blog_id     => { type => 'integer', description => 'ブログID' },
                    label       => { type => 'string',  description => 'フォルダ名（100文字以内）' },
                    basename    => { type => 'string',  description => 'URL パス用 basename（省略時は自動生成）' },
                    parent_id   => { type => 'integer', description => '親フォルダID（省略時はトップレベル）' },
                    description => { type => 'string',  description => '説明' },
                },
            },
        },
        {
            name        => 'folder_update',
            description => 'フォルダを更新する。指定したフィールドのみ上書き（最低1つ必要）。親を自分の子孫にするとエラー。',
            inputSchema => {
                type     => 'object',
                required => ['folder_id'],
                properties => {
                    folder_id   => { type => 'integer', description => 'フォルダID' },
                    label       => { type => 'string',  description => '新しいフォルダ名（100文字以内）' },
                    basename    => { type => 'string',  description => '新しい basename' },
                    parent_id   => { type => 'integer', description => '新しい親フォルダID。0 でトップレベル' },
                    description => { type => 'string',  description => '新しい説明' },
                },
            },
        },
        {
            name        => 'folder_delete',
            description => 'フォルダを削除する。取り消せない。配下の固定ページは親フォルダ（なければルート）へ移る。子フォルダは親へ繰り上がる。confirm: true 必須。',
            inputSchema => {
                type     => 'object',
                required => ['folder_id', 'confirm'],
                properties => {
                    folder_id => { type => 'integer', description => '削除するフォルダのID' },
                    confirm => { type => 'boolean', description => 'true のときだけ実行する（取り消せない操作の確認）' },
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
                    offset  => { type => 'integer', description => '取得開始位置（ページネーション用、デフォルト0）' },
                    class   => { type => 'string',  description => 'image / file など' },
                    keyword => { type => 'string',  description => 'ラベル・ファイル名に対する DB 側の部分一致検索キーワード（件数上限なし）' },
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
            name        => 'asset_upload',
            description => 'ファイルをアップロードして新規アセットを作成する。data には Base64 エンコードしたファイル内容を渡す（最大20MB）。許可される拡張子: jpg/jpeg/png/gif/bmp/webp/ico/tif/tiff/pdf/txt/csv/md/doc/docx/xls/xlsx/ppt/pptx/zip/mp3/mp4/mov/avi/wav/ogg/webm（実行可能ファイルやSVGは安全のため許可されない）。画像拡張子は自動的に画像アセットとして登録される。',
            inputSchema => {
                type     => 'object',
                required => ['blog_id', 'file_name', 'data'],
                properties => {
                    blog_id   => { type => 'integer', description => 'ブログID（blog_list で確認）' },
                    file_name => { type => 'string',  description => 'アップロードするファイル名（拡張子を含む）' },
                    data      => { type => 'string',  description => 'ファイル内容を Base64 エンコードした文字列' },
                    directory => { type => 'string',  description => '保存先サブディレクトリ（省略時は mcp-uploads）' },
                    label     => { type => 'string',  description => 'アセットのラベル（省略時はファイル名）' },
                    overwrite => { type => 'boolean', description => '同名ファイルがある場合に上書きするか（省略時は連番を付けて別名保存）' },
                    author_id => { type => 'integer', description => '作成者ユーザーID（省略時は管理者ユーザー）' },
                },
            },
        },
        {
            name        => 'asset_delete',
            description => 'アセットを削除する。取り消せない操作なので、実行前に対象のアセットを確認すること。confirm: true 必須。',
            inputSchema => {
                type     => 'object',
                required => ['asset_id', 'confirm'],
                properties => {
                    asset_id => { type => 'integer', description => '削除するアセットのID' },
                    confirm => { type => 'boolean', description => 'true のときだけ実行する（取り消せない操作の確認）' },
                },
            },
        },
        {
            name        => 'asset_thumbnail',
            description => '画像アセットのサムネイルURLを取得する（MTの動的リサイズ機能を利用）。width/height を省略すると元のサイズ設定に従う。',
            inputSchema => {
                type     => 'object',
                required => ['asset_id'],
                properties => {
                    asset_id => { type => 'integer', description => 'アセットID' },
                    width    => { type => 'integer', description => 'サムネイルの幅（px）' },
                    height   => { type => 'integer', description => 'サムネイルの高さ（px）' },
                    square   => { type => 'boolean', description => '正方形にトリミングするか' },
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
                    keyword => { type => 'string',  description => 'テンプレート名に対する DB 側の部分一致検索キーワード（件数上限なし）' },
                    limit   => { type => 'integer', description => '取得件数（省略時は全件）' },
                    offset  => { type => 'integer', description => '取得開始位置（ページネーション用、デフォルト0）' },
                },
            },
        },
        {
            name        => 'template_get',
            description => 'テンプレートIDを指定して本文ごと取得する。アーカイブ系（individual / page / archive など）では maps 配列（テンプレートマップ）も返す。ウィジェットセットの割当確認は widgetset_get を使うこと。',
            inputSchema => {
                type     => 'object',
                required => ['template_id'],
                properties => {
                    template_id => { type => 'integer', description => 'テンプレートID' },
                },
            },
        },
        {
            name        => 'template_create',
            description => '新規テンプレートを作成する。type には index / individual / archive / category / page / widget / custom などを指定する。'
                . '保存前に MT テンプレート構文を自動検証し、エラーがあれば行番号付きで返して保存を中止する（その場合は本文を修正して再実行すること）。'
                . '本文を書く前に template_tag_list で使えるタグを確認し、既存テンプレートの書き方を template_get で参考にすると成功しやすい。'
                . 'type が index のときは outfile（出力ファイル名）も必ず指定すること。'
                . 'アーカイブ系（individual / page / archive / category / author / ct / ct_archive）は maps または archive_type を付けないと公開できない。無い場合は warning を返すので templatemap_create を続けること。'
                . 'type が ct / ct_archive のときは content_type_id が必須。'
                . 'ウィジェットセットの作成・割当は widgetset_* を使うこと。type が widgetset のときは body を指定できない（指定するとエラー。本文はウィジェット構成から自動生成され、渡した body は保存されない）。'
                . '作成しただけでは公開ファイルは生成されないため、必要に応じて rebuild_template を実行すること。',
            inputSchema => {
                type     => 'object',
                required => ['blog_id', 'name', 'type'],
                properties => {
                    blog_id    => { type => 'integer', description => 'ブログID（blog_list で確認）' },
                    name       => { type => 'string',  description => 'テンプレート名' },
                    type       => { type => 'string',  description => 'テンプレートタイプ（index, individual, archive, category, page, widget, custom など）' },
                    body       => { type => 'string',  description => 'テンプレート本文（MTタグを含む HTML）。type が widgetset のときは指定不可（指定するとエラー。本文はウィジェット構成から自動生成されるため保存されない）' },
                    outfile    => { type => 'string',  description => '出力ファイル名（例: index.html）。type が index の場合は必須（build_type: 0 のときを除く）' },
                    identifier => { type => 'string',  description => 'テンプレート識別子（<mt:Include identifier="..."> で参照するための名前）' },
                    build_type => { type => 'integer', enum => [0, 1, 2, 3, 4, 5], description => '公開方法。0=公開しない / 1=すぐに公開（オンデマンド） / 2=手動 / 3=ダイナミック / 4=バックグラウンド / 5=スケジュール。省略時は MT のデフォルト' },
                    rebuild_me => { type => 'boolean', description => 'インデックスの再構築時に一緒に再構築するか（index系テンプレート向け）' },
                    skip_validation => { type => 'boolean', description => '構文検証をスキップして強制的に保存する。通常は指定しないこと' },
                    archive_type => { type => 'string', description => 'アーカイブ系テンプレート作成時のショートカット。内部で maps: [{ archive_type }] になる（例: Individual / Page）' },
                    maps => {
                        type  => 'array',
                        items => {
                            type       => 'object',
                            properties => {
                                archive_type  => { type => 'string' },
                                file_template => { type => 'string' },
                                is_preferred  => { type => 'boolean' },
                                build_type    => { type => 'integer' },
                                cat_field_id  => { type => 'integer' },
                                dt_field_id   => { type => 'integer' },
                            },
                        },
                        description => '作成と同時に付けるテンプレートマップ',
                    },
                    content_type_id => { type => 'integer', description => 'type が ct / ct_archive のとき必須' },
                },
            },
        },
        {
            name        => 'template_update',
            description => 'テンプレートを更新する。body / name / type / outfile / identifier / build_type / rebuild_me のうち指定した項目のみ上書きされる（最低1つ必要）。'
                . 'body を指定した場合は保存前に構文を自動検証し、エラーがあれば行番号付きで返して保存を中止する。'
                . 'type が widgetset のときは body を指定できない（指定するとエラー。本文はウィジェット構成から自動生成され、渡した body は保存されない）。'
                . 'ウィジェットセットの割当変更は widgetset_update を使うこと。'
                . '更新後に公開ファイルへ反映するには rebuild_template（または rebuild_site）を実行すること。',
            inputSchema => {
                type     => 'object',
                required => ['template_id'],
                properties => {
                    template_id => { type => 'integer', description => 'テンプレートID' },
                    body        => { type => 'string',  description => '新しいテンプレート本文。type が widgetset のときは指定不可（指定するとエラー。本文はウィジェット構成から自動生成されるため保存されない）' },
                    name        => { type => 'string',  description => '新しいテンプレート名' },
                    type        => { type => 'string',  description => '新しいテンプレートタイプ' },
                    outfile     => { type => 'string',  description => '新しい出力ファイル名' },
                    identifier  => { type => 'string',  description => '新しいテンプレート識別子' },
                    build_type  => { type => 'integer', enum => [0, 1, 2, 3, 4, 5], description => '公開方法。0=公開しない / 1=すぐに公開 / 2=手動 / 3=ダイナミック / 4=バックグラウンド / 5=スケジュール' },
                    rebuild_me  => { type => 'boolean', description => 'インデックスの再構築時に一緒に再構築するか' },
                    skip_validation => { type => 'boolean', description => '構文検証をスキップして強制的に保存する。通常は指定しないこと' },
                },
            },
        },
        {
            name        => 'template_validate',
            description => 'テンプレート本文の MT 構文を検証する（保存はしない）。閉じ忘れたブロックタグや存在しないタグを行番号付きで指摘する。'
                . 'テンプレートを自分で書いたときは、保存前にこのツールで確認すると失敗を減らせる。',
            inputSchema => {
                type     => 'object',
                required => ['blog_id', 'body'],
                properties => {
                    blog_id => { type => 'integer', description => 'ブログID（blog_list で確認）' },
                    body    => { type => 'string',  description => '検証するテンプレート本文' },
                    type    => { type => 'string',  description => 'テンプレートタイプ（省略時は index）' },
                },
            },
        },
        {
            name        => 'template_preview',
            description => 'テンプレートを実際にビルドして出力HTMLを返す（ファイルは書き出さないので公開内容に影響しない）。'
                . 'body を渡せば未保存の本文を、template_id を渡せば保存済みテンプレートをプレビューできる。'
                . '記事コンテキストが必要なテンプレート（individual など）は entry_id も渡すこと。出力は10万文字で打ち切られる。'
                . '本文を評価するため「テンプレートの編集」権限が必要（構文チェックだけなら template_validate を使うこと）。',
            inputSchema => {
                type     => 'object',
                required => ['blog_id'],
                properties => {
                    blog_id     => { type => 'integer', description => 'ブログID（blog_list で確認）' },
                    body        => { type => 'string',  description => 'プレビューするテンプレート本文（template_id と排他。body を優先）' },
                    template_id => { type => 'integer', description => '保存済みテンプレートのID（body を指定しない場合に使用）' },
                    type        => { type => 'string',  description => 'テンプレートタイプ（省略時は index、または元テンプレートのタイプ）' },
                    entry_id    => { type => 'integer', description => '記事コンテキストとして使う記事ID（individual/archive 系テンプレートで必要）' },
                },
            },
        },
        {
            name        => 'template_tag_list',
            description => 'この MT 環境で実際に使える MT テンプレートタグの一覧を取得する。プラグインが追加したタグも含まれる。'
                . 'テンプレートを書く前にこのツールで正しいタグ名を確認すること（存在しないタグを書くと保存時に検証エラーになる）。'
                . '素の MT 9 でも600件以上あるため、keyword で絞り込むこと（例: keyword="Entry" で記事関連のタグ）。',
            inputSchema => {
                type     => 'object',
                properties => {
                    keyword => { type => 'string',  description => 'タグ名に対する部分一致検索キーワード（例: Entry, Category, Asset）' },
                    kind    => { type => 'string',  enum => ['function', 'block', 'modifier'], description => 'function=単体タグ / block=開始終了のあるタグ / modifier=グローバルモディファイア。省略時は全種類' },
                    limit   => { type => 'integer', description => '取得件数（デフォルト100）' },
                },
            },
        },
        {
            name        => 'template_delete',
            description => 'テンプレートを削除する。取り消せない操作なので、実行前に対象のテンプレートを確認すること。confirm: true 必須。',
            inputSchema => {
                type     => 'object',
                required => ['template_id', 'confirm'],
                properties => {
                    template_id => { type => 'integer', description => '削除するテンプレートのID' },
                    confirm => { type => 'boolean', description => 'true のときだけ実行する（取り消せない操作の確認）' },
                },
            },
        },
        {
            name        => 'templatemap_list',
            description => 'アーカイブテンプレートに紐づくテンプレートマップ（URL/出力パス）の一覧。アーカイブテンプレート作成後に rebuild_template できるようにするにはマップが必要。',
            inputSchema => {
                type     => 'object',
                required => ['template_id'],
                properties => {
                    template_id  => { type => 'integer', description => '親テンプレートID' },
                    archive_type => { type => 'string',  description => 'アーカイブタイプで絞る（Individual, Page, Monthly など）' },
                    limit        => { type => 'integer' },
                    offset       => { type => 'integer' },
                },
            },
        },
        {
            name        => 'templatemap_get',
            description => 'テンプレートマップ1件を取得する。',
            inputSchema => {
                type     => 'object',
                required => ['templatemap_id'],
                properties => {
                    templatemap_id => { type => 'integer', description => 'テンプレートマップID' },
                },
            },
        },
        {
            name        => 'templatemap_create',
            description => 'アーカイブテンプレートにマップを追加する。保存時の自動再構築はしない。反映には rebuild_template を使うこと。file_template を省略するとアーカイバのデフォルトを使う。同じ出力パスを複数マップが指しうる点に注意。',
            inputSchema => {
                type     => 'object',
                required => ['template_id', 'archive_type'],
                properties => {
                    template_id   => { type => 'integer', description => '親テンプレートID（individual / page / archive / category / author / ct / ct_archive）' },
                    archive_type  => { type => 'string',  description => '例: Individual, Page, Monthly, Category, ContentType' },
                    file_template => { type => 'string',  description => '出力パスのテンプレート。省略時はデフォルト' },
                    is_preferred  => { type => 'boolean', description => '優先マップにするか' },
                    build_type    => { type => 'integer', enum => [0, 1, 2, 3, 4, 5], description => '0=公開しない / 1=すぐに公開 / 2=手動 / 3=ダイナミック / 4=バックグラウンド / 5=スケジュール。省略時は 1' },
                    cat_field_id  => { type => 'integer', description => 'CT カテゴリアーカイブ用カテゴリフィールドID' },
                    dt_field_id   => { type => 'integer', description => 'CT 日付アーカイブ用日付フィールドID' },
                },
            },
        },
        {
            name        => 'templatemap_update',
            description => 'テンプレートマップを部分更新する（最低1フィールド）。is_preferred を立てると他マップの preferred は外れる。自動再構築はしない。',
            inputSchema => {
                type     => 'object',
                required => ['templatemap_id'],
                properties => {
                    templatemap_id => { type => 'integer' },
                    archive_type   => { type => 'string' },
                    file_template  => { type => 'string' },
                    is_preferred   => { type => 'boolean' },
                    build_type     => { type => 'integer', enum => [0, 1, 2, 3, 4, 5] },
                    cat_field_id   => { type => 'integer' },
                    dt_field_id    => { type => 'integer' },
                },
            },
        },
        {
            name        => 'templatemap_delete',
            description => 'テンプレートマップを削除する。FileInfo は消えるが公開済み静的ファイルは残ることがある。confirm: true 必須。',
            inputSchema => {
                type     => 'object',
                required => ['templatemap_id', 'confirm'],
                properties => {
                    templatemap_id => { type => 'integer' },
                    confirm => { type => 'boolean', description => 'true のときだけ実行する（取り消せない操作の確認）' },
                },
            },
        },
        {
            name        => 'widgetset_list',
            description => '指定ブログのウィジェットセット一覧。各要素に widgets（id+name、割当順）を含む。個別ウィジェット本文は template_*（type: widget）。',
            inputSchema => {
                type     => 'object',
                required => ['blog_id'],
                properties => {
                    blog_id => { type => 'integer' },
                    keyword => { type => 'string', description => 'セット名の部分一致' },
                    limit   => { type => 'integer' },
                    offset  => { type => 'integer' },
                },
            },
        },
        {
            name        => 'widgetset_get',
            description => 'ウィジェットセット1件を取得する。widgets は modulesets 順。本文の編集対象としては返さない。',
            inputSchema => {
                type     => 'object',
                required => ['widgetset_id'],
                properties => {
                    widgetset_id => { type => 'integer' },
                },
            },
        },
        {
            name        => 'widgetset_create',
            description => 'ウィジェットセットを作成する。widget_ids は割当順の整数配列。body は指定できない。反映はセットを含むテンプレート側の rebuild_template / rebuild_site。',
            inputSchema => {
                type     => 'object',
                required => ['blog_id', 'name'],
                properties => {
                    blog_id    => { type => 'integer' },
                    name       => { type => 'string' },
                    widget_ids => { type => 'array', items => { type => 'integer' }, description => 'ウィジェットテンプレートIDの配列（順を保持）。省略時は空セット' },
                },
            },
        },
        {
            name        => 'widgetset_update',
            description => 'ウィジェットセットの名前または割当を更新する。widget_ids は全置換（空配列で全解除）。未指定なら割当は触らない。body は指定できない。',
            inputSchema => {
                type     => 'object',
                required => ['widgetset_id'],
                properties => {
                    widgetset_id => { type => 'integer' },
                    name         => { type => 'string' },
                    widget_ids   => { type => 'array', items => { type => 'integer' }, description => '全置換。[] で全解除' },
                },
            },
        },
        {
            name        => 'widgetset_delete',
            description => 'ウィジェットセットを削除する。中のウィジェット本体は消えない。confirm: true 必須。',
            inputSchema => {
                type     => 'object',
                required => ['widgetset_id', 'confirm'],
                properties => {
                    widgetset_id => { type => 'integer' },
                    confirm => { type => 'boolean', description => 'true のときだけ実行する（取り消せない操作の確認）' },
                },
            },
        },
        {
            name        => 'widget_list',
            description => 'ウィジェット（type=widget）一覧。widgetset_id を付けるとそのセットの割当順。無いときはサイトのウィジェット（グローバル blog_id=0 も含む）。',
            inputSchema => {
                type     => 'object',
                required => ['blog_id'],
                properties => {
                    blog_id      => { type => 'integer' },
                    widgetset_id => { type => 'integer', description => '指定時はそのセット内のみ（割当順）' },
                    keyword      => { type => 'string' },
                    limit        => { type => 'integer' },
                    offset       => { type => 'integer' },
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
            description => 'コンテンツタイプを新規作成する。fields を省略すると「タイトル」「本文」の2フィールドが作られる。type が categories のフィールドには category_set_id（または related_cat_set_id）が必須。',
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
                                required        => { type => 'boolean', description => '必須かどうか' },
                                category_set_id => { type => 'integer', description => 'type=categories のとき必須。category_set_create で作ったセットID' },
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
                    offset          => { type => 'integer', description => '取得開始位置（ページネーション用、デフォルト0）' },
                    status          => { type => 'string',  enum => ['publish','draft','all'], description => 'ステータス' },
                    keyword         => { type => 'string',  description => 'ラベル・テキストフィールドに対する DB 側の部分一致検索キーワード（件数上限なし）' },
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
        {
            name        => 'content_data_delete',
            description => 'コンテンツデータを削除する。取り消せない操作なので、実行前に対象のデータを確認すること。confirm: true 必須。',
            inputSchema => {
                type     => 'object',
                required => ['content_data_id', 'confirm'],
                properties => {
                    content_data_id => { type => 'integer', description => '削除するコンテンツデータID' },
                    confirm => { type => 'boolean', description => 'true のときだけ実行する（取り消せない操作の確認）' },
                },
            },
        },
        {
            name        => 'rebuild_template',
            description => 'テンプレート1枚を再構築（公開）して、変更を実際のファイルに反映する。'
                . 'template_create / template_update のあとに使うのはこのツール（rebuild_site より圧倒的に速い）。'
                . 'インデックステンプレートはそのファイルのみ、アーカイブテンプレートは紐づくアーカイブタイプのみを再構築する（マップ未設定なら失敗するので先に templatemap_create）。',
            inputSchema => {
                type     => 'object',
                required => ['template_id'],
                properties => {
                    template_id => { type => 'integer', description => '再構築するテンプレートのID（template_list で確認）' },
                },
            },
        },
        {
            name        => 'rebuild_entry',
            description => '記事1件を再構築（公開）する。記事の作成・更新後に公開ページへ反映したいときに使う。'
                . '固定ページには rebuild_entry ではなく rebuild_page を使うこと。'
                . 'デフォルトでは月別・カテゴリアーカイブやインデックスなど、その記事に依存するページも一緒に再構築する。',
            inputSchema => {
                type     => 'object',
                required => ['entry_id'],
                properties => {
                    entry_id           => { type => 'integer', description => '再構築する記事のID' },
                    build_dependencies => { type => 'boolean', description => '依存するアーカイブ・インデックスも再構築するか（省略時は true）。false にすると記事ページのみで高速' },
                },
            },
        },
        {
            name        => 'rebuild_page',
            description => '固定ページ1件を再構築（公開）する。page_create / page_update のあとに使う。記事には rebuild_entry を使うこと。',
            inputSchema => {
                type     => 'object',
                required => ['page_id'],
                properties => {
                    page_id            => { type => 'integer', description => '再構築する固定ページのID' },
                    build_dependencies => { type => 'boolean', description => '依存するアーカイブ・インデックスも再構築するか（省略時は true）' },
                },
            },
        },
        {
            name        => 'rebuild_content_data',
            description => 'コンテンツデータ1件を再構築（公開）する。content_data_create / content_data_update のあとに使う。',
            inputSchema => {
                type     => 'object',
                required => ['content_data_id'],
                properties => {
                    content_data_id    => { type => 'integer', description => '再構築するコンテンツデータのID' },
                    build_dependencies => { type => 'boolean', description => '依存するアーカイブ・インデックスも再構築するか（省略時は true）' },
                },
            },
        },
        {
            name        => 'rebuild_site',
            description => 'ブログ全体を再構築（公開）する。記事数の多いサイトでは数分以上かかり、HTTPのタイムアウトで失敗することがある。'
                . 'まずは rebuild_template / rebuild_entry / rebuild_page で範囲を絞れないか検討し、それでも全体再構築が必要なときだけ使うこと。'
                . 'archive_type を指定すると、そのアーカイブタイプのみに絞って再構築できる。',
            inputSchema => {
                type     => 'object',
                required => ['blog_id'],
                properties => {
                    blog_id      => { type => 'integer', description => 'ブログID（blog_list で確認）' },
                    archive_type => { type => 'string',  description => '再構築するアーカイブタイプ（Individual, Monthly, Category, Page など）。省略時は全アーカイブ' },
                    no_indexes   => { type => 'boolean', description => 'true にするとインデックステンプレートの再構築をスキップする' },
                },
            },
        },
        {
            name        => 'log_list',
            description => 'アクティビティログ（システムログ）を新しい順に取得する。公開失敗・権限エラー・プラグイン障害などのトラブルシュート時に、管理画面へ切り替えなくても level・期間・キーワードで原因を追うために使う。'
                . 'blog_id を省略または 0 にすると、権限のある範囲のシステム全体。サイト単位なら blog_id を指定する（ウェブサイト配下の子ブログは自動では含めない）。'
                . '権限はシステムの view_log、または対象サイトの view_blog_log。書き込み・リセット・エクスポートはできない。',
            inputSchema => {
                type       => 'object',
                properties => {
                    blog_id    => { type => 'integer', description => 'サイトID。省略または 0 は権限のある範囲のシステム全体' },
                    limit      => { type => 'integer', description => '取得件数（デフォルト20、最大200）' },
                    offset     => { type => 'integer', description => '取得開始位置（デフォルト0、負値は0）' },
                    level      => {
                        type        => 'string',
                        enum        => [
                            'security', 'error', 'warning', 'notice', 'info', 'debug',
                            'security_or_error', 'security_or_error_or_warning',
                            'not_debug', 'debug_or_error',
                        ],
                        description => 'ログレベル（MT::Log の連番定数。notice は warning ではない）',
                    },
                    class      => { type => 'string', description => 'system / entry / page / comment / ping / plugin など。省略時は全クラス' },
                    category   => { type => 'string', description => 'publish / delete / reset_log など' },
                    date_from  => { type => 'string', description => 'YYYY-MM-DD（created_on 下限、GMT）' },
                    date_to    => { type => 'string', description => 'YYYY-MM-DD（created_on 上限、GMT）' },
                    keyword    => { type => 'string', description => 'message と ip の部分一致（DB LIKE）' },
                },
            },
        },
        {
            name        => 'log_get',
            description => 'ログ1件の詳細（metadata の生文字列を含む）を取得する。log_list で ID を確認してから、長いメッセージや付随データを見るときに使う。'
                . '権限は対象ログのサイトに対する view_log（システム）または view_blog_log。見つからなければ Log not found。',
            inputSchema => {
                type     => 'object',
                required => ['log_id'],
                properties => {
                    log_id => { type => 'integer', description => 'ログID（log_list で確認）' },
                },
            },
        },
        {
            name        => 'user_list',
            description => 'MT のユーザー（MT::Author）一覧を名前順で取得する。コメント投稿者は含まない。'
                . '権限はシステムの「ユーザーとグループの管理」（can_manage_users_groups）。blog_id は不要。'
                . 'ロールの付与・剥奪はこのツールではできない。',
            inputSchema => {
                type       => 'object',
                properties => {
                    limit   => { type => 'integer', description => '取得件数（デフォルト20）' },
                    offset  => { type => 'integer', description => '取得開始位置（デフォルト0）' },
                    keyword => { type => 'string',  description => 'name / nickname / email の部分一致' },
                    status  => {
                        type        => 'string',
                        enum        => ['active', 'disabled', 'pending', 'all'],
                        description => '状態。省略時は all',
                    },
                    lockout => {
                        type        => 'string',
                        enum        => ['locked_out', 'not_locked_out'],
                        description => 'ロック状態で絞り込み',
                    },
                },
            },
        },
        {
            name        => 'user_get',
            description => 'ユーザー1件を取得する。コメント投稿者の ID は User not found。'
                . '権限は can_manage_users_groups。返却にパスワードは含まれない。',
            inputSchema => {
                type     => 'object',
                required => ['user_id'],
                properties => {
                    user_id => { type => 'integer', description => 'ユーザーID（user_list で確認）' },
                },
            },
        },
        {
            name        => 'user_create',
            description => 'ユーザーを作成する。作成直後はサイト権限なし。ロールは管理画面で付与すること（MCP からの権限昇格を避ける）。'
                . '権限は can_manage_users_groups。パスワードはレスポンスに出さない。system_permissions は設定しない。',
            inputSchema => {
                type     => 'object',
                required => ['name', 'password', 'display_name'],
                properties => {
                    name         => { type => 'string', description => 'ログイン名（<> 不可。AUTHOR 内で一意）' },
                    password     => { type => 'string', description => '平文。保存時にハッシュ化。返却しない' },
                    display_name => { type => 'string', description => '表示名（nickname）' },
                    email        => { type => 'string', description => '推奨。パスワード回復に必要' },
                    url          => { type => 'string', description => 'ウェブサイトURL' },
                    status       => {
                        type        => 'string',
                        enum        => ['active', 'disabled', 'pending'],
                        description => '省略時は active',
                    },
                },
            },
        },
        {
            name        => 'user_delete',
            description => 'ユーザーを削除する（取り消せない）。実行前に user_get で対象を確認すること。confirm: true 必須。'
                . '自分自身は削除できない。対象がスーパーユーザーなら呼び出し元もスーパーユーザーである必要がある。'
                . '権限は can_manage_users_groups。',
            inputSchema => {
                type     => 'object',
                required => ['user_id', 'confirm'],
                properties => {
                    user_id => { type => 'integer', description => '削除するユーザーID（user_get で確認）' },
                    confirm => { type => 'boolean', description => 'true のときだけ実行する（取り消せない操作の確認）' },
                },
            },
        },
        {
            name        => 'user_update',
            description => 'ユーザーのプロフィール（表示名・メール・URL・状態）を更新する。パスワードの直接変更はしない（user_recover_password を使う）。'
                . 'ログイン名の変更と権限の付与・剥奪はできない。権限は can_manage_users_groups。返却にパスワードは含まれない。',
            inputSchema => {
                type     => 'object',
                required => ['user_id'],
                properties => {
                    user_id      => { type => 'integer', description => 'ユーザーID（user_get で確認）' },
                    display_name => { type => 'string',  description => '表示名（nickname）' },
                    email        => { type => 'string',  description => 'メールアドレス' },
                    url          => { type => 'string',  description => 'ウェブサイトURL' },
                    status       => {
                        type        => 'string',
                        enum        => ['active', 'disabled', 'pending'],
                        description => '状態',
                    },
                },
            },
        },
        {
            name        => 'user_unlock',
            description => 'ログイン失敗によるロックを解除する。未ロックでもエラーにしない。'
                . '権限は can_manage_users_groups。',
            inputSchema => {
                type     => 'object',
                required => ['user_id'],
                properties => {
                    user_id => { type => 'integer', description => 'ユーザーID' },
                },
            },
        },
        {
            name        => 'user_recover_password',
            description => '指定ユーザーへパスワード回復メールを送る。新しいパスワードは受け取らない（直接変更はしない）。'
                . 'email 未設定や外部認証では失敗する。権限は can_manage_users_groups。公開の未ログイン回復は提供しない。',
            inputSchema => {
                type     => 'object',
                required => ['user_id'],
                properties => {
                    user_id => { type => 'integer', description => 'ユーザーID' },
                },
            },
        },
    ];
}

1;
