use strict;
use warnings;
use utf8;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../plugins/MTMCP/lib";

use MTMCP::Tools::CategorySet;
use MTMCP::Tools::Category;
use MT::CategorySet;
use MT::Category;
use MT::Blog;

{
    no warnings 'redefine';
    *MTMCP::Perm::require_blog_access     = sub { 1 };
    *MTMCP::Perm::require_blog_permission = sub { 1 };
}

my $app = bless {}, 'FakeApp';

sub _reset {
    MT::CategorySet::reset();
    MT::Category::reset();
    MT::Blog::reset();
}

sub _seed_set {
    my (%args) = @_;
    my $s = MT::CategorySet->new;
    $s->id($args{id}) if defined $args{id};
    $s->blog_id($args{blog_id} // 1);
    $s->name($args{name} // 'Set');
    $s->order($args{order} // '');
    $s->save;
    return $s;
}

sub _seed_category {
    my (%args) = @_;
    my $c = MT::Category->new;
    $c->id($args{id}) if defined $args{id};
    $c->blog_id($args{blog_id} // 1);
    $c->label($args{label} // 'Cat');
    $c->basename($args{basename} // 'cat');
    $c->parent($args{parent} // 0);
    $c->class('category');
    $c->category_set_id($args{category_set_id} // 0);
    $c->save;
    return $c;
}

{
    _reset();
    _seed_set(id => 1, name => 'Topics');
    my $got = eval {
        MTMCP::Tools::CategorySet::create($app, { blog_id => 1, name => 'Topics' });
    };
    ok(!$got, '同名カテゴリセットは拒否');
    like($@, qr/Topics/, '同名拒否メッセージ');
}

{
    _reset();
    _seed_set(id => 2, name => 'Topics');
    _seed_category(id => 10, label => 'News', basename => 'news', category_set_id => 2);
    _seed_category(id => 11, label => 'Blog', basename => 'blog', category_set_id => 2, parent => 10);
    _seed_category(id => 99, label => 'Article', basename => 'article', category_set_id => 0);
    my $got = eval { MTMCP::Tools::CategorySet::get($app, { category_set_id => 2 }) };
    ok($got, 'category_set_get は成功する') or diag($@);
    is($got->{name}, 'Topics', 'name');
    is($got->{category_count}, 2, 'category_count は配下2件');
    is(scalar @{ $got->{categories} }, 2, 'get は配下カテゴリを含む');
    my %by_id = map { $_->{id} => $_ } @{ $got->{categories} };
    is($by_id{10}{label}, 'News', '子カテゴリ label');
    is($by_id{10}{basename}, 'news', '子カテゴリ basename');
    is($by_id{11}{parent_id}, 10, '子の parent_id');
    ok(!$by_id{99}, '記事カテゴリは混ざらない');
    is(ref $MT::CategorySet::LAST_LOAD_TERMS, 'HASH', 'get はハッシュ load');
    is($MT::CategorySet::LAST_LOAD_TERMS->{id}, 2, 'id で load');
}

{
    _reset();
    _seed_set(id => 3, name => 'ToDelete');
    _seed_category(id => 20, label => 'Child', basename => 'c', category_set_id => 3);
    _seed_category(id => 21, label => 'Keep', basename => 'k', category_set_id => 0);
    my $got = eval { MTMCP::Tools::CategorySet::remove($app, { category_set_id => 3, confirm => 1 }) };
    ok($got, 'category_set_delete は成功する') or diag($@);
    is($got->{status}, 'deleted', 'status は deleted');
    ok(!MT::CategorySet->load({ id => 3 }), 'セットは消える');
    ok(!MT::Category->load({ id => 20, class => 'category' }), '配下カテゴリも消える');
    ok(MT::Category->load({ id => 21, class => 'category' }), '記事カテゴリは残る');
}

{
    _reset();
    _seed_set(id => 4, name => 'CT Cats');
    my $got = eval {
        MTMCP::Tools::Category::create($app, {
            blog_id         => 1,
            label           => 'From set',
            category_set_id => 4,
        });
    };
    ok($got, 'セット内カテゴリ create は成功する') or diag($@);
    is($got->{category_set_id}, 4, '返却 category_set_id');
    my $obj = MT::Category->load({ id => $got->{category_id}, class => 'category' });
    is($obj->category_set_id, 4, '保存オブジェクトの category_set_id');
    is($obj->class, 'category', 'class は category');
}

{
    _reset();
    _seed_set(id => 5, name => 'Order');
    _seed_category(id => 31, label => 'A', basename => 'a', category_set_id => 5);
    _seed_category(id => 32, label => 'B', basename => 'b', category_set_id => 5);
    _seed_category(id => 1, label => 'Article', basename => 'art', category_set_id => 0);
    my $got = eval {
        MTMCP::Tools::Category::permutate($app, {
            blog_id         => 1,
            category_set_id => 5,
            category_ids    => [ 32, 31 ],
        });
    };
    ok($got, 'セットの permutate は成功する') or diag($@);
    is($got->{category_order}, '32,31', 'CategorySet.order に保存');
    my $set = MT::CategorySet->load({ id => 5 });
    is($set->order, '32,31', 'セットオブジェクトの順');
}

{
    _reset();
    my $got = eval {
        MTMCP::Tools::Category::create($app, {
            blog_id         => 1,
            label           => 'Plain',
            category_set_id => 0,
        });
    };
    ok($got, '記事カテゴリ create（set_id 0）は成功する') or diag($@);
    is($got->{category_set_id}, 0, 'set_id 0 のまま');
    my $obj = MT::Category->load({ id => $got->{category_id}, class => 'category' });
    is($obj->category_set_id, 0, '保存時も 0');
}

{
    _reset();
    _seed_set(id => 6, name => 'OldName');
    my $got = eval {
        MTMCP::Tools::CategorySet::update($app, {
            category_set_id => 6,
            name            => 'NewName',
            categories      => [ { label => 'nope' } ],
        });
    };
    ok(!$got, 'update に categories 配列はエラー');
    like($@, qr/name のみ/, 'Data API どおり name のみ');
}

done_testing;
