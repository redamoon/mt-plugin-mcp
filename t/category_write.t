use strict;
use warnings;
use utf8;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../plugins/MTMCP/lib";

use MTMCP::Tools::Category;
use MT::Category;
use MT::Blog;

{
    no warnings 'redefine';
    *MTMCP::Perm::require_blog_access     = sub { 1 };
    *MTMCP::Perm::require_blog_permission = sub { 1 };
}

my $app = bless {}, 'FakeApp';

sub _reset {
    MT::Category::reset();
    MT::Blog::reset();
}

sub _seed_category {
    my (%args) = @_;
    my $c = MT::Category->new;
    $c->id($args{id}) if defined $args{id};
    $c->blog_id($args{blog_id} // 1);
    $c->label($args{label} // 'Cat');
    $c->basename($args{basename} // 'cat');
    $c->parent($args{parent} // 0);
    $c->description($args{description} // '');
    $c->class($args{class} // 'category');
    $c->category_set_id($args{category_set_id} // 0);
    $c->save;
    return $c;
}

sub _seed_folder_in_category_store {
    my (%args) = @_;
    my $id = $args{id} // 5;
    $MT::Category::STORE{$id} = bless {
        id              => $id,
        blog_id         => $args{blog_id} // 1,
        label           => $args{label} // 'A folder',
        basename        => $args{basename} // 'folder',
        parent          => 0,
        description     => '',
        class           => 'folder',
        category_set_id => 0,
    }, 'MT::Category';
    $MT::Category::NEXT_ID = $id + 1 if $MT::Category::NEXT_ID <= $id;
    return $MT::Category::STORE{$id};
}

# ------------------------------------------------------------------
# list: basename / description / category_set_id 0、フォルダ・セット除外
# ------------------------------------------------------------------

{
    _reset();
    _seed_category(id => 1, label => 'News', basename => 'news', description => 'desc');
    _seed_folder_in_category_store(id => 5, label => 'Not a category');
    _seed_category(id => 8, label => 'Set Cat', basename => 'set', category_set_id => 3);
    my $got = eval { MTMCP::Tools::Category::list($app, { blog_id => 1 }) };
    ok($got, 'category_list は成功する') or diag($@);
    is(scalar @$got, 1, 'フォルダとセットカテゴリは混ざらない');
    is($got->[0]{id}, 1, '返るのは記事カテゴリだけ');
    is($got->[0]{basename}, 'news', 'list は basename を返す');
    is($got->[0]{description}, 'desc', 'list は description を返す');
    is($got->[0]{category_set_id}, 0, 'list の category_set_id は 0');
    is(ref $MT::Category::LAST_LOAD_TERMS, 'HASH', 'list はハッシュ load');
    is($MT::Category::LAST_LOAD_TERMS->{class}, 'category', 'list は class=category');
    is($MT::Category::LAST_LOAD_TERMS->{category_set_id}, 0, 'list は category_set_id 0 を明示');
}

{
    _reset();
    _seed_category(id => 1, label => 'Parent', basename => 'p');
    _seed_category(id => 2, label => 'Child', basename => 'c', parent => 1);
    my $got = eval { MTMCP::Tools::Category::list($app, { blog_id => 1, parent_id => 0 }) };
    ok($got, 'parent_id 0 でトップレベルのみ') or diag($@);
    is(scalar @$got, 1, 'トップレベルは1件');
    is($got->[0]{id}, 1, '親だけ返る');
}

# ------------------------------------------------------------------
# Folder ID / セットカテゴリは見つからない
# ------------------------------------------------------------------

{
    _reset();
    _seed_folder_in_category_store(id => 5);
    my $got = eval { MTMCP::Tools::Category::get($app, { category_id => 5 }) };
    my $err = $@;
    ok(!$got, 'category_get(フォルダ ID) は成功しない');
    like($err, qr/Category not found: 5/, 'folder ID は Category not found');
}

{
    _reset();
    _seed_folder_in_category_store(id => 5);
    my $got = eval {
        MTMCP::Tools::Category::update($app, { category_id => 5, label => 'hacked' });
    };
    ok(!$got, 'category_update(フォルダ ID) は成功しない');
    like($@, qr/Category not found: 5/, 'update も Folder ID を not found');
    is(scalar @MT::Category::SAVED, 0, 'update(フォルダ ID) は保存しない');
}

{
    _reset();
    _seed_folder_in_category_store(id => 5);
    my $got = eval { MTMCP::Tools::Category::remove($app, { category_id => 5 }) };
    ok(!$got, 'category_delete(フォルダ ID) は成功しない');
    like($@, qr/Category not found: 5/, 'delete も Folder ID を not found');
    is(scalar @MT::Category::REMOVED, 0, 'delete(フォルダ ID) は削除しない');
    ok($MT::Category::STORE{5}, 'フォルダ行は残っている');
}

{
    _reset();
    _seed_category(id => 9, label => 'From set', category_set_id => 2);
    my $got = eval { MTMCP::Tools::Category::get($app, { category_id => 9 }) };
    ok(!$got, 'セットカテゴリの get は失敗');
    like($@, qr/記事カテゴリではありません/, 'セットは記事カテゴリではない');
}

# ------------------------------------------------------------------
# create: label 必須、悪い親、兄弟同名、basename 自動
# ------------------------------------------------------------------

{
    _reset();
    my $got = eval { MTMCP::Tools::Category::create($app, { blog_id => 1 }) };
    ok(!$got, 'category_create は label 必須');
    like($@, qr/label is required/, 'label is required');
}

{
    _reset();
    _seed_folder_in_category_store(id => 5);
    my $got = eval {
        MTMCP::Tools::Category::create($app, {
            blog_id   => 1,
            label     => 'Child',
            parent_id => 5,
        });
    };
    ok(!$got, 'parent_id がフォルダなら失敗');
    like($@, qr/Category not found: 5/, '悪い親は Category not found');
}

{
    _reset();
    _seed_category(id => 1, label => 'News', basename => 'news');
    my $got = eval {
        MTMCP::Tools::Category::create($app, { blog_id => 1, label => 'News' });
    };
    ok(!$got, '兄弟の同じ label はエラー');
    like($@, qr/News/, '兄弟同名のメッセージ');
}

{
    _reset();
    my $got = eval {
        MTMCP::Tools::Category::create($app, {
            blog_id     => 1,
            label       => 'About',
            description => 'about cat',
        });
    };
    ok($got, 'category_create は成功する') or diag($@);
    is($got->{status}, 'created', 'status は created');
    is($got->{label}, 'About', 'label');
    ok($got->{basename}, 'basename が自動生成される');
    is($got->{basename}, 'about', 'basename は label から');
    is($got->{category_set_id}, 0, 'create の category_set_id は 0');
    ok(!defined $got->{parent_id}, 'トップレベル parent_id undef');
    my $obj = MT::Category->load({ id => $got->{category_id}, class => 'category' });
    is($obj->class, 'category', '保存オブジェクトの class は category');
    is($obj->description, 'about cat', 'description が保存される');
    is($obj->category_set_id, 0, '保存時 category_set_id は 0');
}

{
    _reset();
    my $got = eval {
        MTMCP::Tools::Category::create($app, {
            blog_id         => 1,
            label           => 'From set',
            category_set_id => 4,
        });
    };
    ok(!$got, 'category_set_id != 0 は拒否');
    like($@, qr/カテゴリセット/, 'セット ID 拒否メッセージ');
}

# ------------------------------------------------------------------
# update: 部分更新
# ------------------------------------------------------------------

{
    _reset();
    _seed_category(id => 1, label => 'Old', basename => 'old', description => 'keep me');
    @MT::Category::SAVED = ();
    my $got = eval {
        MTMCP::Tools::Category::update($app, { category_id => 1, label => 'New' });
    };
    ok($got, 'category_update は成功する') or diag($@);
    is($got->{status}, 'updated', 'status は updated');
    is($got->{label}, 'New', '返却 label は更新後');
    my $obj = MT::Category->load({ id => 1, class => 'category' });
    is($obj->label, 'New', 'label は更新される');
    is($obj->basename, 'old', '未指定の basename は保持');
    is($obj->description, 'keep me', '未指定の description は保持');
}

{
    _reset();
    _seed_category(id => 1, label => 'A', basename => 'a');
    my $got = eval { MTMCP::Tools::Category::update($app, { category_id => 1 }) };
    ok(!$got, '更新項目なしはエラー');
    like($@, qr/更新する項目がありません/, '部分更新は最低1フィールド');
}

# ------------------------------------------------------------------
# delete
# ------------------------------------------------------------------

{
    _reset();
    _seed_category(id => 1, label => 'Delete me', basename => 'del');
    _seed_category(id => 2, label => 'Child', basename => 'c', parent => 1);
    my $got = eval { MTMCP::Tools::Category::remove($app, { category_id => 1 }) };
    ok($got, 'category_delete は成功する') or diag($@);
    is($got->{status}, 'deleted', 'status は deleted');
    is($got->{label}, 'Delete me', '削除前の label を返す');
    is(scalar @MT::Category::REMOVED, 1, 'remove が呼ばれる');
    ok(!MT::Category->load({ id => 1, class => 'category' }), 'カテゴリはストアから消える');
    my $child = MT::Category->load({ id => 2, class => 'category' });
    is($child->parent, 0, '子は親へ繰り上がる（コア相当）');
}

# ------------------------------------------------------------------
# permutate: 全 ID 一致が必要
# ------------------------------------------------------------------

{
    _reset();
    _seed_category(id => 1, label => 'A', basename => 'a');
    _seed_category(id => 2, label => 'B', basename => 'b');
    _seed_category(id => 3, label => 'C', basename => 'c');
    _seed_category(id => 9, label => 'Set', basename => 's', category_set_id => 1);
    my $got = eval {
        MTMCP::Tools::Category::permutate($app, {
            blog_id      => 1,
            category_ids => [ 3, 1, 2 ],
        });
    };
    ok($got, '全 ID 一致なら permutate 成功') or diag($@);
    is($got->{status}, 'permutated', 'status は permutated');
    is($got->{category_order}, '3,1,2', 'blog.category_order に保存');
    my $blog = MT::Blog->load(1);
    is($blog->category_order, '3,1,2', 'Blog オブジェクトの順');
}

{
    _reset();
    _seed_category(id => 1, label => 'A', basename => 'a');
    _seed_category(id => 2, label => 'B', basename => 'b');
    my $got = eval {
        MTMCP::Tools::Category::permutate($app, {
            blog_id      => 1,
            category_ids => [1],
        });
    };
    ok(!$got, '欠ける ID はエラー');
    like($@, qr/全件と一致/, '不足 ID のエラー');
}

{
    _reset();
    _seed_category(id => 1, label => 'A', basename => 'a');
    my $got = eval {
        MTMCP::Tools::Category::permutate($app, {
            blog_id      => 1,
            category_ids => [ 1, 99 ],
        });
    };
    ok(!$got, '範囲外 ID はエラー');
    like($@, qr/全件と一致/, '余分な ID のエラー');
}

done_testing;
