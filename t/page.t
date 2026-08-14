use strict;
use warnings;
use utf8;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../plugins/MTMCP/lib";

use MTMCP::Tools::Page;
use MTMCP::Tools::Rebuild;
use MT::Entry;
use MT::Page;
use MT::Folder;
use MT::Placement;
use MT::Template;
use MT::TemplateMap;
use MT::Blog;
use JSON;

{
    no warnings 'redefine';
    *MTMCP::Perm::require_blog_access     = sub { 1 };
    *MTMCP::Perm::require_blog_permission = sub { 1 };
}

package FakeConfig;
sub new {
    my ($class, $flag) = @_;
    bless { DeleteFilesAtRebuild => $flag }, $class;
}
sub DeleteFilesAtRebuild { $_[0]{DeleteFilesAtRebuild} }

package FakeApp;
sub rebuild_entry {
    my ($self, %param) = @_;
    $self->{called} = \%param;
    return 1;
}
sub errstr { '' }
sub config     { $_[0]{config} }
sub publisher  { $_[0]{publisher} }

package main;

my $app = bless {}, 'FakeApp';

sub _reset_all {
    MT::Entry::reset();
    MT::Folder::reset();
    MT::Placement::reset();
    MT::Template::reset();
    MT::TemplateMap::reset();
    MT::Blog::reset();
}

sub _seed_entry {
    my (%args) = @_;
    my $e = MT::Entry->new;
    $e->id($args{id} // 1);
    $e->blog_id($args{blog_id} // 1);
    $e->title($args{title} // 'A genuine entry');
    $e->text($args{text} // 'entry body');
    $e->status($args{status} // MT::Entry::HOLD());
    $e->class('entry');
    $e->modified_on($args{modified_on} // '20200101000000');
    $e->save;
    return $e;
}

sub _seed_page {
    my (%args) = @_;
    my $p = MT::Page->new;
    $p->id($args{id} // 10);
    $p->blog_id($args{blog_id} // 1);
    $p->title($args{title} // 'A page');
    $p->text($args{text} // 'page body');
    $p->status($args{status} // MT::Entry::RELEASE());
    $p->basename($args{basename}) if defined $args{basename};
    $p->modified_on($args{modified_on} // '20240101000000');
    $p->save;
    return $p;
}

sub _seed_folder {
    my (%args) = @_;
    my $f = MT::Folder->new;
    $f->id($args{id}) if defined $args{id};
    $f->blog_id($args{blog_id} // 1);
    $f->label($args{label} // 'Docs');
    $f->basename($args{basename} // 'docs');
    $f->class('folder');
    $f->save;
    return $f;
}

sub _seed_category_in_folder_store {
    my (%args) = @_;
    my $id = $args{id} // 5;
    $MT::Folder::STORE{$id} = bless {
        id       => $id,
        blog_id  => $args{blog_id} // 1,
        label    => $args{label} // 'Category',
        basename => 'cat',
        parent   => 0,
        class    => 'category',
    }, 'MT::Folder';
    $MT::Folder::NEXT_ID = $id + 1 if $MT::Folder::NEXT_ID <= $id;
    return $MT::Folder::STORE{$id};
}

# ------------------------------------------------------------------
# Entry ID は page_* で見つからない
# ------------------------------------------------------------------

{
    _reset_all();
    _seed_entry(id => 1, title => 'Hello', text => 'world');
    my $got = eval { MTMCP::Tools::Page::get($app, { page_id => 1 }) };
    my $err = $@;
    ok(!$got, 'page_get(Entry ID) は成功しない');
    like($err, qr/Page not found: 1/, 'page_get は Entry ID を Page not found にする');
}

{
    _reset_all();
    _seed_page(id => 10, title => 'Hello', text => 'page body');
    my $got = eval { MTMCP::Tools::Page::get($app, { page_id => 10 }) };
    ok($got, 'page_get(Page ID) は成功する') or diag($@);
    is($got->{id},    10,          'id');
    is($got->{title}, 'Hello',     'title');
    is($got->{body},  'page body', 'body を返す');
}

{
    _reset_all();
    my $got = eval {
        MTMCP::Tools::Page::create($app, { blog_id => 1, title => 'New Page', body => 'hi' });
    };
    ok($got, 'page_create は成功する') or diag($@);
    is($got->{status}, 'created', 'status は created');
    my $obj = MT::Page->load({ id => $got->{page_id}, class => 'page' });
    ok($obj, 'Page が保存される');
    is($obj->class, 'page', 'page_create のオブジェクト class は page');
    is($obj->title, 'New Page', 'title');
}

{
    _reset_all();
    _seed_category_in_folder_store(id => 5);
    my $got = eval {
        MTMCP::Tools::Page::create($app, {
            blog_id   => 1,
            title     => 'P',
            folder_id => 5,
        });
    };
    my $err = $@;
    ok(!$got, 'page_create(folder_id がカテゴリ) は成功しない');
    like($err, qr/folder_id.*フォルダ/, 'カテゴリ ID はフォルダではない');
}

{
    _reset_all();
    _seed_entry(id => 1, title => 'Entry', status => MT::Entry::RELEASE(), modified_on => '20250101000000');
    _seed_page(id => 10, title => 'Page', status => MT::Entry::RELEASE(), modified_on => '20240101000000');
    my $got = eval { MTMCP::Tools::Page::list($app, { blog_id => 1, status => 'publish' }) };
    ok($got, 'page_list は成功する') or diag($@);
    is(scalar @$got, 1, 'page_list に Entry は混ざらない');
    is($got->[0]{id}, 10, '返るのは Page');
    ok(!$got->[0]{categories}, 'page_list に categories は付かない');
}

{
    _reset_all();
    _seed_entry(id => 1);
    my $got = eval { MTMCP::Tools::Rebuild::page($app, { page_id => 1 }) };
    my $err = $@;
    ok(!$got, 'rebuild_page(Entry ID) は成功しない');
    like($err, qr/Page not found: 1/, 'rebuild_page は Entry ID を Page not found にする');
    ok(!$app->{called}, 'rebuild_entry は呼ばれない');
}

{
    _reset_all();
    $app = bless {}, 'FakeApp';
    _seed_page(id => 10, title => 'Rebuild me');
    my $got = eval { MTMCP::Tools::Rebuild::page($app, { page_id => 10 }) };
    ok($got, 'rebuild_page(Page ID) は成功する') or diag($@);
    is($got->{status}, 'rebuilt', 'status は rebuilt');
    is($got->{scope},  'page',    'scope は page');
    is($got->{page_id}, 10,       'page_id');
    ok($app->{called}, 'rebuild_entry が呼ばれる');
    is($app->{called}{Entry}->id, 10, 'Entry 引数は Page');
    is($app->{called}{BuildDependencies}, 1, 'build_dependencies のデフォルトは真');
}

# ------------------------------------------------------------------
# CRUD / folder 付け外し
# ------------------------------------------------------------------

{
    _reset_all();
    my $folder = _seed_folder(id => 2, label => 'Docs');
    my $created = eval {
        MTMCP::Tools::Page::create($app, {
            blog_id   => 1,
            title     => 'About',
            body      => 'about body',
            folder_id => 2,
            status    => 'draft',
        });
    };
    ok($created, 'folder 付き page_create') or diag($@);
    my $got = eval { MTMCP::Tools::Page::get($app, { page_id => $created->{page_id} }) };
    ok($got->{folder}, 'folder が付く');
    is($got->{folder}{id},    2,      'folder id');
    is($got->{folder}{label}, 'Docs', 'folder label');

    my $upd = eval {
        MTMCP::Tools::Page::update($app, {
            page_id   => $created->{page_id},
            folder_id => 0,
        });
    };
    ok($upd, 'folder_id 0 で detach') or diag($@);
    my $after = eval { MTMCP::Tools::Page::get($app, { page_id => $created->{page_id} }) };
    ok(!$after->{folder}, 'detach 後は folder が無い');
}

{
    _reset_all();
    _seed_page(id => 10, title => 'Old');
    my $got = eval {
        MTMCP::Tools::Page::update($app, { page_id => 10, title => 'New' });
    };
    ok($got, 'page_update は成功する') or diag($@);
    is($got->{status}, 'updated', 'status は updated');
    is(MT::Page->load({ id => 10, class => 'page' })->title, 'New', 'title が更新される');
}

{
    _reset_all();
    _seed_page(id => 10, title => 'Delete me');
    my $got = eval { MTMCP::Tools::Page::remove($app, { page_id => 10 }) };
    ok($got, 'page_delete は成功する') or diag($@);
    is($got->{status}, 'deleted', 'status は deleted');
    is(scalar @MT::Entry::REMOVED, 1, 'remove が呼ばれる');
    ok(!MT::Page->load({ id => 10, class => 'page' }), 'Page はストアから消える');
    is(scalar @MT::Blog::_Publisher::REMOVED_ARCHIVE, 0, 'config なしでは公開ファイルを消さない');
}

{
    _reset_all();
    _seed_page(id => 10, title => 'Delete files');
    my $app_on = bless { config => FakeConfig->new(1) }, 'FakeApp';
    my $got = eval { MTMCP::Tools::Page::remove($app_on, { page_id => 10 }) };
    ok($got, 'DeleteFilesAtRebuild 時も page_delete は成功') or diag($@);
    is(scalar @MT::Blog::_Publisher::REMOVED_ARCHIVE, 1, '公開アーカイブ削除を呼ぶ');
    is($MT::Blog::_Publisher::REMOVED_ARCHIVE[0]{ArchiveType}, 'Page', 'ArchiveType は Page');
    is($MT::Blog::_Publisher::REMOVED_ARCHIVE[0]{Entry}->id, 10, 'Entry は対象 Page');
}

{
    _reset_all();
    _seed_page(id => 10, title => 'Keep files');
    my $app_off = bless { config => FakeConfig->new(0) }, 'FakeApp';
    my $got = eval { MTMCP::Tools::Page::remove($app_off, { page_id => 10 }) };
    ok($got, 'DeleteFilesAtRebuild 無効でも DB 削除は成功') or diag($@);
    is(scalar @MT::Blog::_Publisher::REMOVED_ARCHIVE, 0, '無効時は公開ファイルを消さない');
    ok(!MT::Page->load({ id => 10, class => 'page' }), 'Page はストアから消える');
}

{
    _reset_all();
    my $folder = _seed_folder(id => 2, label => 'Docs');
    my $in  = _seed_page(id => 10, title => 'In folder');
    my $out = _seed_page(id => 11, title => 'Outside');
    my $pl = MT::Placement->new;
    $pl->entry_id(10);
    $pl->blog_id(1);
    $pl->category_id(2);
    $pl->is_primary(1);
    $pl->save;
    my $got = eval { MTMCP::Tools::Page::list($app, { blog_id => 1, folder_id => 2 }) };
    ok($got, 'folder_id で絞り込める') or diag($@);
    is(scalar @$got, 1, 'フォルダ内の Page だけ');
    is($got->[0]{id}, 10, '対象 Page');
}

{
    _reset_all();
    my $got = eval { MTMCP::Tools::Page::list($app, { blog_id => 1, folder_id => 99 }) };
    ok(!$got, '存在しない folder_id はエラー');
    like($@, qr/Folder not found/, 'Folder not found');
}

# ------------------------------------------------------------------
# preview
# ------------------------------------------------------------------

{
    _reset_all();
    _seed_page(id => 10, title => 'Preview');
    my $got = eval { MTMCP::Tools::Page::preview($app, { page_id => 10 }) };
    ok(!$got, 'マップ無しの page_preview は失敗');
    like($@, qr/Page アーカイブテンプレートが見つかりません/, 'マップ無しエラー');
}

{
    _reset_all();
    _seed_page(id => 10, title => 'HelloPage');
    my $tmpl = MT::Template->new;
    $tmpl->id(1);
    $tmpl->blog_id(1);
    $tmpl->name('Page Archive');
    $tmpl->type('page');
    $tmpl->text('OUTPUT:');
    $tmpl->save;
    my $map = MT::TemplateMap->new;
    $map->blog_id(1);
    $map->template_id(1);
    $map->archive_type('Page');
    $map->is_preferred(1);
    $map->save;

    my $got = eval { MTMCP::Tools::Page::preview($app, { page_id => 10 }) };
    ok($got, 'page_preview は成功する') or diag($@);
    is($got->{type}, 'page', 'type は page');
    is($got->{output}, 'OUTPUT:HelloPage', 'テンプレートとタイトルが結合される');
    ok(!$got->{truncated}, 'truncated は偽');

    my $unsaved = eval {
        MTMCP::Tools::Page::preview($app, {
            blog_id => 1,
            title   => 'DraftTitle',
            body    => 'unused',
        });
    };
    ok($unsaved, '未保存 page_preview') or diag($@);
    is($unsaved->{output}, 'OUTPUT:DraftTitle', '未保存タイトルでビルド');
}

# ------------------------------------------------------------------
# 必須引数
# ------------------------------------------------------------------

{
    _reset_all();
    eval { MTMCP::Tools::Page::list($app, {}) };
    like($@, qr/blog_id is required/, 'page_list は blog_id 必須');
    eval { MTMCP::Tools::Page::get($app, {}) };
    like($@, qr/page_id is required/, 'page_get は page_id 必須');
    eval { MTMCP::Tools::Page::create($app, { blog_id => 1 }) };
    like($@, qr/title is required/, 'page_create は title 必須');
    eval { MTMCP::Tools::Page::update($app, {}) };
    like($@, qr/page_id is required/, 'page_update は page_id 必須');
    eval { MTMCP::Tools::Page::remove($app, {}) };
    like($@, qr/page_id is required/, 'page_delete は page_id 必須');
    eval { MTMCP::Tools::Rebuild::page($app, {}) };
    like($@, qr/page_id is required/, 'rebuild_page は page_id 必須');
}

done_testing;
