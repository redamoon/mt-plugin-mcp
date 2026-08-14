use strict;
use warnings;
use utf8;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../plugins/MTMCP/lib";

use MTMCP::Tools::Folder;
use MT::Folder;

{
    no warnings 'redefine';
    *MTMCP::Perm::require_blog_access     = sub { 1 };
    *MTMCP::Perm::require_blog_permission = sub { 1 };
}

my $app = bless {}, 'FakeApp';

sub _seed_folder {
    my (%args) = @_;
    my $f = MT::Folder->new;
    $f->id($args{id}) if defined $args{id};
    $f->blog_id($args{blog_id} // 1);
    $f->label($args{label} // 'Folder');
    $f->basename($args{basename} // 'folder');
    $f->parent($args{parent} // 0);
    $f->description($args{description} // '');
    $f->class('folder');
    $f->save;
    return $f;
}

sub _seed_category_in_folder_store {
    my (%args) = @_;
    my $id = $args{id} // 5;
    $MT::Folder::STORE{$id} = bless {
        id          => $id,
        blog_id     => $args{blog_id} // 1,
        label       => $args{label} // 'A category',
        basename    => $args{basename} // 'cat',
        parent      => 0,
        description => '',
        class       => 'category',
    }, 'MT::Folder';
    $MT::Folder::NEXT_ID = $id + 1 if $MT::Folder::NEXT_ID <= $id;
    return $MT::Folder::STORE{$id};
}

# ------------------------------------------------------------------
# カテゴリ ID は folder_* で見つからない
# ------------------------------------------------------------------

{
    MT::Folder::reset();
    _seed_category_in_folder_store(id => 5);
    my $got = eval { MTMCP::Tools::Folder::get($app, { folder_id => 5 }) };
    my $err = $@;
    ok(!$got, 'folder_get(カテゴリ ID) は成功しない');
    like($err, qr/Folder not found: 5/, 'folder_get はカテゴリ ID を Folder not found にする');
}

{
    MT::Folder::reset();
    _seed_category_in_folder_store(id => 5);
    my $got = eval {
        MTMCP::Tools::Folder::update($app, { folder_id => 5, label => 'hacked' });
    };
    my $err = $@;
    ok(!$got, 'folder_update(カテゴリ ID) は成功しない');
    like($err, qr/Folder not found: 5/, 'folder_update はカテゴリ ID を Folder not found にする');
    is(scalar @MT::Folder::SAVED, 0, 'folder_update(カテゴリ ID) は保存しない');
}

{
    MT::Folder::reset();
    _seed_category_in_folder_store(id => 5);
    my $got = eval { MTMCP::Tools::Folder::remove($app, { folder_id => 5 }) };
    my $err = $@;
    ok(!$got, 'folder_delete(カテゴリ ID) は成功しない');
    like($err, qr/Folder not found: 5/, 'folder_delete はカテゴリ ID を Folder not found にする');
    is(scalar @MT::Folder::REMOVED, 0, 'folder_delete(カテゴリ ID) は削除しない');
    ok($MT::Folder::STORE{5}, 'カテゴリ行は残っている');
}

{
    MT::Folder::reset();
    _seed_folder(id => 1, label => 'Real Folder', basename => 'real');
    _seed_category_in_folder_store(id => 5, label => 'Not a folder');
    my $got = eval { MTMCP::Tools::Folder::list($app, { blog_id => 1 }) };
    ok($got, 'folder_list は成功する') or diag($@);
    is(scalar @$got, 1, 'folder_list にカテゴリは混ざらない');
    is($got->[0]{id}, 1, '返るのはフォルダだけ');
}

{
    MT::Folder::reset();
    _seed_category_in_folder_store(id => 5);
    my $got = eval {
        MTMCP::Tools::Folder::create($app, {
            blog_id   => 1,
            label     => 'Child',
            parent_id => 5,
        });
    };
    my $err = $@;
    ok(!$got, 'folder_create(parent_id がカテゴリ) は成功しない');
    like($err, qr/Folder not found: 5/, 'parent_id にカテゴリ ID を渡すと Folder not found');
}

# ------------------------------------------------------------------
# 必須・バリデーション
# ------------------------------------------------------------------

{
    MT::Folder::reset();
    my $got = eval { MTMCP::Tools::Folder::create($app, { blog_id => 1 }) };
    my $err = $@;
    ok(!$got, 'folder_create は label 必須');
    like($err, qr/label is required/, 'label is required');
}

{
    MT::Folder::reset();
    my $got = eval { MTMCP::Tools::Folder::list($app, {}) };
    like($@, qr/blog_id is required/, 'folder_list は blog_id 必須');
    ok(!$got);
}

{
    MT::Folder::reset();
    my $long = 'a' x 101;
    my $got = eval {
        MTMCP::Tools::Folder::create($app, { blog_id => 1, label => $long });
    };
    my $err = $@;
    ok(!$got, 'label が 100 文字超はエラー');
    like($err, qr/100/, '100文字制限のエラー');
}

# ------------------------------------------------------------------
# 本物のフォルダ ID は動く
# ------------------------------------------------------------------

{
    MT::Folder::reset();
    _seed_folder(id => 1, label => 'Docs', basename => 'docs', description => 'desc');
    my $got = eval { MTMCP::Tools::Folder::get($app, { folder_id => 1 }) };
    ok($got, 'folder_get(フォルダ ID) は成功する') or diag($@);
    is($got->{id},          1,      'id');
    is($got->{label},       'Docs', 'label');
    is($got->{basename},    'docs', 'basename');
    is($got->{description}, 'desc', 'description');
    is($got->{class},       'folder', 'class は folder');
    is($got->{blog_id},     1,      'blog_id');
    ok(!defined $got->{parent_id}, 'トップレベルは parent_id undef');
}

{
    MT::Folder::reset();
    my $got = eval {
        MTMCP::Tools::Folder::create($app, {
            blog_id     => 1,
            label       => 'About',
            description => 'about pages',
        });
    };
    ok($got, 'folder_create は成功する') or diag($@);
    is($got->{status},   'created', 'status は created');
    is($got->{label},    'About',   'label');
    ok($got->{basename}, 'basename が自動生成される');
    is($got->{basename}, 'about',   'basename は label から');
    my $obj = MT::Folder->load({ id => $got->{folder_id}, class => 'folder' });
    is($obj->class, 'folder', '保存オブジェクトの class は folder');
    is($obj->description, 'about pages', 'description が保存される');
}

{
    MT::Folder::reset();
    _seed_folder(id => 1, label => 'Old', basename => 'old', description => 'keep me');
    @MT::Folder::SAVED = ();
    my $got = eval {
        MTMCP::Tools::Folder::update($app, { folder_id => 1, label => 'New' });
    };
    ok($got, 'folder_update は成功する') or diag($@);
    is($got->{status}, 'updated', 'status は updated');
    is($got->{label},  'New',     '返却 label は更新後');
    my $obj = MT::Folder->load({ id => 1, class => 'folder' });
    is($obj->label,       'New',     'label は更新される');
    is($obj->basename,    'old',     '未指定の basename は保持');
    is($obj->description, 'keep me', '未指定の description は保持');
}

{
    MT::Folder::reset();
    _seed_folder(id => 1, label => 'Delete me', basename => 'del');
    my $got = eval { MTMCP::Tools::Folder::remove($app, { folder_id => 1 }) };
    ok($got, 'folder_delete は成功する') or diag($@);
    is($got->{status}, 'deleted', 'status は deleted');
    is($got->{label},  'Delete me', '削除前の label を返す');
    is(scalar @MT::Folder::REMOVED, 1, 'remove が呼ばれる');
    ok(!MT::Folder->load({ id => 1, class => 'folder' }), 'フォルダはストアから消える');
}

{
    MT::Folder::reset();
    _seed_folder(id => 1, label => 'Parent', basename => 'parent');
    my $got = eval {
        MTMCP::Tools::Folder::create($app, {
            blog_id   => 1,
            label     => 'Child',
            parent_id => 1,
            basename  => 'child',
        });
    };
    ok($got, 'folder_create は親フォルダを付けられる') or diag($@);
    my $obj = MT::Folder->load({ id => $got->{folder_id}, class => 'folder' });
    is($obj->parent, 1, 'parent が設定される');
}

{
    MT::Folder::reset();
    _seed_folder(id => 1, label => 'A', basename => 'dup');
    my $got = eval {
        MTMCP::Tools::Folder::create($app, {
            blog_id  => 1,
            label    => 'B',
            basename => 'dup',
        });
    };
    ok(!$got, '兄弟の basename 衝突はエラー');
    like($@, qr/basename/, 'basename 衝突のメッセージ');
}

{
    MT::Folder::reset();
    my $parent = _seed_folder(id => 1, label => 'P', basename => 'p');
    my $child  = _seed_folder(id => 2, label => 'C', basename => 'c', parent => 1);
    my $got = eval {
        MTMCP::Tools::Folder::update($app, { folder_id => 1, parent_id => 2 });
    };
    ok(!$got, '子孫を親にはできない');
}

{
    MT::Folder::reset();
    _seed_folder(id => 2, label => 'Child', basename => 'c', parent => 1);
    my $got = eval { MTMCP::Tools::Folder::list($app, { blog_id => 1, parent_id => 0 }) };
    ok($got, 'parent_id 0 でトップレベルのみ') or diag($@);
    is(scalar @$got, 0, 'トップレベルは空（parent=1 のみ）');
}

done_testing;
