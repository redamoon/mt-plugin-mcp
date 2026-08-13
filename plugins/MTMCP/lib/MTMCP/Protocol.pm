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
    'category_list'   => sub { require MTMCP::Tools::Category; MTMCP::Tools::Category::list(@_)     },
    'tag_list'        => sub { require MTMCP::Tools::Category; MTMCP::Tools::Category::list_tags(@_)},
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
    'rebuild_site'         => sub { require MTMCP::Tools::Rebuild;      MTMCP::Tools::Rebuild::site(@_)          },
    'rebuild_template'     => sub { require MTMCP::Tools::Rebuild;      MTMCP::Tools::Rebuild::template(@_)      },
    'rebuild_entry'        => sub { require MTMCP::Tools::Rebuild;      MTMCP::Tools::Rebuild::entry(@_)         },
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
            serverInfo      => { name => 'MT MCP Server', version => '0.6.0' },
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
                    keyword => { type => 'string', description => 'タイトル・本文に対する部分一致検索キーワード' },
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
            description => '記事を削除する。取り消せない操作なので、実行前に対象の記事を確認すること。',
            inputSchema => {
                type     => 'object',
                required => ['entry_id'],
                properties => {
                    entry_id => { type => 'integer', description => '削除する記事のID' },
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
                    offset  => { type => 'integer', description => '取得開始位置（ページネーション用、デフォルト0）' },
                    class   => { type => 'string',  description => 'image / file など' },
                    keyword => { type => 'string',  description => 'ラベル・ファイル名に対する部分一致検索キーワード' },
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
            description => 'アセットを削除する。取り消せない操作なので、実行前に対象のアセットを確認すること。',
            inputSchema => {
                type     => 'object',
                required => ['asset_id'],
                properties => {
                    asset_id => { type => 'integer', description => '削除するアセットのID' },
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
                    keyword => { type => 'string',  description => 'テンプレート名に対する部分一致検索キーワード' },
                    limit   => { type => 'integer', description => '取得件数（省略時は全件）' },
                    offset  => { type => 'integer', description => '取得開始位置（ページネーション用、デフォルト0）' },
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
            name        => 'template_create',
            description => '新規テンプレートを作成する。type には index / individual / archive / category / page / widget / custom などを指定する。'
                . '保存前に MT テンプレート構文を自動検証し、エラーがあれば行番号付きで返して保存を中止する（その場合は本文を修正して再実行すること）。'
                . '本文を書く前に template_tag_list で使えるタグを確認し、既存テンプレートの書き方を template_get で参考にすると成功しやすい。'
                . '作成しただけでは公開ファイルは生成されないため、必要に応じて rebuild_template を実行すること。',
            inputSchema => {
                type     => 'object',
                required => ['blog_id', 'name', 'type'],
                properties => {
                    blog_id    => { type => 'integer', description => 'ブログID（blog_list で確認）' },
                    name       => { type => 'string',  description => 'テンプレート名' },
                    type       => { type => 'string',  description => 'テンプレートタイプ（index, individual, archive, category, page, widget, custom など）' },
                    body       => { type => 'string',  description => 'テンプレート本文（MTタグを含む HTML）' },
                    outfile    => { type => 'string',  description => '出力ファイル名（index系テンプレートで使用。例: index.html）' },
                    identifier => { type => 'string',  description => 'テンプレート識別子（<mt:Include identifier="..."> で参照するための名前）' },
                    build_type => { type => 'integer', enum => [0, 1, 2, 3, 4, 5], description => '公開方法。0=公開しない / 1=すぐに公開（オンデマンド） / 2=手動 / 3=ダイナミック / 4=バックグラウンド / 5=スケジュール。省略時は MT のデフォルト' },
                    rebuild_me => { type => 'boolean', description => 'インデックスの再構築時に一緒に再構築するか（index系テンプレート向け）' },
                    skip_validation => { type => 'boolean', description => '構文検証をスキップして強制的に保存する。通常は指定しないこと' },
                },
            },
        },
        {
            name        => 'template_update',
            description => 'テンプレートを更新する。body / name / type / outfile / identifier / build_type / rebuild_me のうち指定した項目のみ上書きされる（最低1つ必要）。'
                . 'body を指定した場合は保存前に構文を自動検証し、エラーがあれば行番号付きで返して保存を中止する。'
                . '更新後に公開ファイルへ反映するには rebuild_template（または rebuild_site）を実行すること。',
            inputSchema => {
                type     => 'object',
                required => ['template_id'],
                properties => {
                    template_id => { type => 'integer', description => 'テンプレートID' },
                    body        => { type => 'string',  description => '新しいテンプレート本文' },
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
                . '記事コンテキストが必要なテンプレート（individual など）は entry_id も渡すこと。出力は10万文字で打ち切られる。',
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
            description => 'テンプレートを削除する。取り消せない操作なので、実行前に対象のテンプレートを確認すること。',
            inputSchema => {
                type     => 'object',
                required => ['template_id'],
                properties => {
                    template_id => { type => 'integer', description => '削除するテンプレートのID' },
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
                    offset          => { type => 'integer', description => '取得開始位置（ページネーション用、デフォルト0）' },
                    status          => { type => 'string',  enum => ['publish','draft','all'], description => 'ステータス' },
                    keyword         => { type => 'string',  description => 'フィールド値に対する部分一致検索キーワード' },
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
            description => 'コンテンツデータを削除する。取り消せない操作なので、実行前に対象のデータを確認すること。',
            inputSchema => {
                type     => 'object',
                required => ['content_data_id'],
                properties => {
                    content_data_id => { type => 'integer', description => '削除するコンテンツデータID' },
                },
            },
        },
        {
            name        => 'rebuild_template',
            description => 'テンプレート1枚を再構築（公開）して、変更を実際のファイルに反映する。'
                . 'template_create / template_update のあとに使うのはこのツール（rebuild_site より圧倒的に速い）。'
                . 'インデックステンプレートはそのファイルのみ、アーカイブテンプレートは紐づくアーカイブタイプのみを再構築する。',
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
                . 'まずは rebuild_template / rebuild_entry で範囲を絞れないか検討し、それでも全体再構築が必要なときだけ使うこと。'
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
    ];
}

1;
