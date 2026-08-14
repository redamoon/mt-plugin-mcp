use strict;
use warnings;
use utf8;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../plugins/MTMCP/lib";

use MTMCP::Tools::Entry;
use MT::Entry;
use MT::Placement;
use MT::Template;
use MT::TemplateMap;
use MT::Blog;
use MT::Category;
use JSON;

my @perm_calls;
{
    no warnings 'redefine';
    *MTMCP::Perm::require_blog_access     = sub { 1 };
    *MTMCP::Perm::require_blog_permission = sub {
        my ( $app, $blog_id, $action, $label ) = @_;
        push @perm_calls, [ $blog_id, $action, $label ];
        1;
    };
}

my $app = bless {}, 'FakeApp';

sub _reset_all {
    MT::Entry::reset();
    MT::Placement::reset();
    MT::Template::reset();
    MT::TemplateMap::reset();
    MT::Blog::reset();
    MT::Category::reset();
    @perm_calls = ();
}

sub _seed_entry {
    my (%args) = @_;
    my $e = MT::Entry->new;
    $e->id( $args{id} // 1 );
    $e->blog_id( $args{blog_id} // 1 );
    $e->title( $args{title} // 'A genuine entry' );
    $e->text( $args{text} // 'entry body' );
    $e->status( $args{status} // MT::Entry::HOLD() );
    $e->class( $args{class} // 'entry' );
    $e->authored_on( $args{authored_on} // '20200101120000' );
    $e->save;
    return $e;
}

sub _seed_page {
    my (%args) = @_;
    return _seed_entry(
        id    => $args{id} // 99,
        title => $args{title} // 'A page, not an entry',
        text  => $args{text} // 'page body',
        class => 'page',
        %args,
    );
}

sub _seed_individual_map {
    my (%args) = @_;
    my $tmpl = MT::Template->new;
    $tmpl->id( $args{template_id} // 1 );
    $tmpl->blog_id( $args{blog_id} // 1 );
    $tmpl->name('Individual Archive');
    $tmpl->type('individual');
    $tmpl->text( $args{text} // 'OUTPUT:' );
    $tmpl->save;
    my $map = MT::TemplateMap->new;
    $map->blog_id( $args{blog_id} // 1 );
    $map->template_id( $tmpl->id );
    $map->archive_type('Individual');
    $map->is_preferred(1);
    $map->save;
    return ( $tmpl, $map );
}

# ------------------------------------------------------------------
# 未保存: build が呼ばれ、save されない
# ------------------------------------------------------------------
{
    _reset_all();
    _seed_individual_map();
    my $saved_n = scalar @MT::Entry::SAVED;
    my $got     = eval {
        MTMCP::Tools::Entry::preview(
            $app,
            { blog_id => 1, title => 'DraftTitle', body => 'draft body' }
        );
    };
    ok( $got, '未保存 preview は成功する' ) or diag($@);
    is( $MT::Template::BUILD_COUNT, 1, 'build が呼ばれる' );
    is( scalar @MT::Entry::SAVED, $saved_n, 'SAVED は増えない' );
    ok( !defined $MT::Entry::LAST_SAVE, 'LAST_SAVE は未設定のまま' );
    is( $MT::Template::WRITE_COUNT,    0, 'write は呼ばれない' );
    is( $MT::Template::PUT_DATA_COUNT, 0, 'put_data は呼ばれない' );
    is( $got->{type}, 'individual', 'type は individual' );
    is( $got->{output}, 'OUTPUT:DraftTitle', 'テンプレートとタイトルでビルド' );
    ok( !$got->{saved}, 'saved は偽' );
    ok( !defined $got->{entry_id}, '未保存の entry_id は undef' );
    is( $perm_calls[0][1], 'create_post', '権限は create_post' );
    is( $perm_calls[0][2], '記事の作成',  '権限ラベルは記事の作成' );
    my $ctx = $MT::Template::LAST_BUILD_CTX;
    ok( $ctx, 'build に context が渡る' );
    is( $ctx->stash('current_archive_type'), 'Individual', 'archive_type stash' );
    is( $ctx->stash('preview_template'),     1,            'preview_template stash' );
    is( $ctx->stash('entry')->id,            -1,           '未保存 Entry の id は -1' );
    is( $ctx->stash('entry')->text,          'draft body', '未保存 body が stash される' );
}

# ------------------------------------------------------------------
# 既存 entry_id overlay は STORE を変えない
# ------------------------------------------------------------------
{
    _reset_all();
    _seed_entry( id => 5, text => 'original', title => 'Orig' );
    _seed_individual_map();
    my $saved_n = scalar @MT::Entry::SAVED;
    my $got     = eval {
        MTMCP::Tools::Entry::preview(
            $app,
            { blog_id => 1, entry_id => 5, body => 'overlay text', title => 'Overlay' }
        );
    };
    ok( $got, '既存 overlay preview は成功する' ) or diag($@);
    is( scalar @MT::Entry::SAVED, $saved_n, 'overlay でも SAVED は増えない' );
    is( MT::Entry->load(5)->text,  'original', 'STORE の text は変わらない' );
    is( MT::Entry->load(5)->title, 'Orig',     'STORE の title は変わらない' );
    my $ctx_entry = $MT::Template::LAST_BUILD_CTX->stash('entry');
    is( $ctx_entry->text,  'overlay text', 'clone 上の text は上書き' );
    is( $ctx_entry->title, 'Overlay',      'clone 上の title は上書き' );
    is( $got->{entry_id},  5,              'entry_id は既存 ID' );
    ok( !$got->{saved}, 'saved は偽' );
    is( $MT::Template::WRITE_COUNT,    0, 'write は呼ばれない' );
    is( $MT::Template::PUT_DATA_COUNT, 0, 'put_data は呼ばれない' );
}

# ------------------------------------------------------------------
# Page ID => Entry not found
# ------------------------------------------------------------------
{
    _reset_all();
    _seed_page( id => 99 );
    _seed_individual_map();
    my $got = eval {
        MTMCP::Tools::Entry::preview( $app, { blog_id => 1, entry_id => 99 } );
    };
    my $err = $@;
    ok( !$got, 'Page ID の preview は成功しない' );
    like( $err, qr/Entry not found: 99/, 'Page ID は Entry not found' );
    is( scalar @MT::Entry::SAVED, 1, 'Page シード以外の save は無い' );
}

# ------------------------------------------------------------------
# blog_id mismatch
# ------------------------------------------------------------------
{
    _reset_all();
    _seed_entry( id => 1, blog_id => 1 );
    _seed_individual_map();
    my $got = eval {
        MTMCP::Tools::Entry::preview( $app, { blog_id => 2, entry_id => 1 } );
    };
    ok( !$got, 'blog mismatch は失敗' );
    like( $@, qr/blog_id.*一致しません/, 'blog_id 不一致エラー' );
}

# ------------------------------------------------------------------
# TemplateMap なし
# ------------------------------------------------------------------
{
    _reset_all();
    _seed_entry( id => 1 );
    my $got = eval {
        MTMCP::Tools::Entry::preview( $app, { blog_id => 1, entry_id => 1 } );
    };
    ok( !$got, 'マップ無しは失敗' );
    like( $@, qr/記事アーカイブテンプレートが見つかりません/, 'アーカイブテンプレートエラー' );
}

# ------------------------------------------------------------------
# 出力 > 100000 => truncated
# ------------------------------------------------------------------
{
    _reset_all();
    _seed_individual_map( text => ( 'x' x 100_001 ) );
    my $got = eval {
        MTMCP::Tools::Entry::preview(
            $app, { blog_id => 1, title => '', body => 'y' }
        );
    };
    ok( $got, '巨大出力 preview は成功する' ) or diag($@);
    ok( $got->{truncated}, 'truncated は真' );
    is( $got->{length}, 100_000, 'length は 100000' );
    is( length( $got->{output} ), 100_000, 'output は 100000 文字' );
}

# ------------------------------------------------------------------
# entry_id も body/title も無い
# ------------------------------------------------------------------
{
    _reset_all();
    my $got = eval {
        MTMCP::Tools::Entry::preview( $app, { blog_id => 1 } );
    };
    ok( !$got, 'entry_id も body/title も無いと失敗' );
    like( $@, qr/entry_id または body \/ title が必要です/, '必須引数エラー' );
}

{
    _reset_all();
    eval { MTMCP::Tools::Entry::preview( $app, { title => 'x' } ) };
    like( $@, qr/blog_id is required/, 'blog_id 必須' );
}

# ------------------------------------------------------------------
# category_ids は cache のみ（Placement を保存しない）
# ------------------------------------------------------------------
{
    _reset_all();
    _seed_individual_map();
    my $cat = MT::Category->new;
    $cat->id(7);
    $cat->blog_id(1);
    $cat->label('News');
    $cat->class('category');
    $cat->save;
    my $pl_n = scalar @MT::Placement::SAVED;
    my $got  = eval {
        MTMCP::Tools::Entry::preview(
            $app,
            {
                blog_id      => 1,
                title        => 'Cat',
                body         => 'b',
                category_ids => [7],
            }
        );
    };
    ok( $got, 'category_ids 付き preview' ) or diag($@);
    is( scalar @MT::Placement::SAVED, $pl_n, 'Placement は保存しない' );
    my $e = $MT::Template::LAST_BUILD_CTX->stash('entry');
    is( $e->cache_property('category')->id, 7, '主カテゴリを stash' );
}

done_testing;
