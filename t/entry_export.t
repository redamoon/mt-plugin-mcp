use strict;
use warnings;
use utf8;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../plugins/MTMCP/lib";

use MT::Entry;
use MT::Author;
use MT::Permission;
use MT::Placement;
use MT::Category;
use MTMCP::Tools::Entry;
use MTMCP::Perm;

{
    package FakeUser;
    sub new {
        my ($class, %args) = @_;
        bless \%args, $class;
    }
    sub id           { $_[0]{id} }
    sub is_superuser { $_[0]{is_superuser} }
}
{
    package FakeApp;
    sub new {
        my ($class, %args) = @_;
        bless \%args, $class;
    }
    sub user { $_[0]{user} }
}

sub _app {
    my (%user) = @_;
    return FakeApp->new(user => FakeUser->new(%user));
}

sub _seed_entry {
    my (%args) = @_;
    my $e = MT::Entry->new;
    $e->id($args{id} // 1);
    $e->blog_id($args{blog_id} // 1);
    $e->title($args{title} // 'Hello');
    $e->text($args{text} // 'body text');
    $e->text_more($args{text_more});
    $e->excerpt($args{excerpt});
    $e->basename($args{basename} // 'hello');
    $e->status($args{status} // MT::Entry::RELEASE());
    $e->author_id($args{author_id} // 7);
    $e->authored_on($args{authored_on} // '20260815080000');
    $e->class($args{class} // 'entry');
    $e->save;
    return $e;
}

sub _seed_author {
    my $u = MT::Author->new;
    $u->id(7);
    $u->name('melody');
    $u->type(MT::Author::AUTHOR());
    $u->save;
}

{
    MT::Entry::reset();
    MT::Author::reset();
    eval { MTMCP::Tools::Entry::export(_app(id => 1, is_superuser => 1), {}) };
    like($@, qr/entry_id is required/, 'entry_id 必須');
}

{
    MT::Entry::reset();
    MT::Author::reset();
    _seed_entry(id => 99, class => 'page', title => 'A page');
    my $got = eval {
        MTMCP::Tools::Entry::export(_app(id => 1, is_superuser => 1), { entry_id => 99 });
    };
    my $err = $@;
    ok(!$got, 'Page ID は拒否');
    like($err, qr/Entry not found: 99/, 'Page は Entry not found');
}

{
    MT::Entry::reset();
    MT::Author::reset();
    MT::Permission::reset();
    _seed_entry(id => 1);
    my $got = eval {
        MTMCP::Tools::Entry::export(_app(id => 3, is_superuser => 0), { entry_id => 1 });
    };
    my $err = $@;
    ok(!$got, '権限なしは拒否');
    like($err, qr/権限/, 'export_blog なしメッセージ');
}

{
    MT::Entry::reset();
    MT::Author::reset();
    MT::Permission::reset();
    _seed_entry(id => 1);
    MT::Permission->add(
        author_id   => 3,
        blog_id     => 1,
        permissions => { export_blog => 0 },
    );
    my $got = eval {
        MTMCP::Tools::Entry::export(_app(id => 3, is_superuser => 0), { entry_id => 1 });
    };
    like($@, qr/ブログのエクスポート/, 'export_blog が無いと拒否');
}

{
    MT::Entry::reset();
    MT::Author::reset();
    MT::Permission::reset();
    MT::Placement::reset();
    MT::Category::reset();
    _seed_author();
    _seed_entry(
        id         => 1,
        title      => 'Hello',
        text       => "line1\nline2",
        text_more  => 'more',
        excerpt    => 'ex',
        basename   => 'hello',
        authored_on => '20260815080000',
    );
    my $cat = MT::Category->new;
    $cat->id(2);
    $cat->blog_id(1);
    $cat->label('News');
    $cat->class('category');
    $cat->save;
    my $pl = MT::Placement->new;
    $pl->entry_id(1);
    $pl->blog_id(1);
    $pl->category_id(2);
    $pl->is_primary(1);
    $pl->save;

    my $got = MTMCP::Tools::Entry::export(
        _app(id => 1, is_superuser => 1),
        { entry_id => 1 },
    );
    is($got->{format}, 'mt', 'format は mt');
    is($got->{entry_id}, 1, 'entry_id');
    is($got->{blog_id}, 1, 'blog_id');
    ok(!$got->{truncated}, '短い本文は打ち切らない');
    like($got->{body}, qr/^AUTHOR: melody/m, 'AUTHOR');
    like($got->{body}, qr/^TITLE: Hello/m, 'TITLE');
    like($got->{body}, qr/^STATUS: Publish/m, 'STATUS Publish');
    like($got->{body}, qr/^DATE: 08\/15\/2026 08:00:00 AM/m, 'DATE');
    like($got->{body}, qr/^PRIMARY CATEGORY: News/m, 'PRIMARY CATEGORY');
    like($got->{body}, qr/^CATEGORY: News/m, 'CATEGORY');
    like($got->{body}, qr/^BODY:\nline1\nline2\n-----/m, 'BODY');
    like($got->{body}, qr/^EXTENDED BODY:\nmore/m, 'EXTENDED BODY');
    like($got->{body}, qr/^EXCERPT:\nex/m, 'EXCERPT');
    like($got->{body}, qr/--------\n\z/, 'エントリ終端');
}

{
    MT::Entry::reset();
    MT::Author::reset();
    _seed_entry(id => 1, blog_id => 1);
    my $got = eval {
        MTMCP::Tools::Entry::export(
            _app(id => 1, is_superuser => 1),
            { entry_id => 1, blog_id => 2 },
        );
    };
    like($@, qr/Entry not found: 1/, 'blog_id 不一致は見つからない');
}

{
    MT::Entry::reset();
    MT::Author::reset();
    _seed_entry(id => 1, text => ('x' x 120_000));
    my $got = MTMCP::Tools::Entry::export(
        _app(id => 1, is_superuser => 1),
        { entry_id => 1 },
    );
    ok($got->{truncated}, '長い本文は打ち切る');
    is($got->{length}, 100_000, '打ち切り後の length');
    is(length($got->{body}), 100_000, 'body は上限');
}

{
    MT::Entry::reset();
    MT::Author::reset();
    MT::Permission::reset();
    _seed_entry(id => 1);
    MT::Permission->add(
        author_id   => 3,
        blog_id     => 1,
        permissions => { export_blog => 1 },
    );
    my $got = eval {
        MTMCP::Tools::Entry::export(_app(id => 3, is_superuser => 0), { entry_id => 1 });
    };
    ok($got, 'export_blog があれば成功') or diag($@);
}

# 複数カテゴリが付いていても MT::Category->load は1回で済む（N+1 の解消）。
{
    MT::Entry::reset();
    MT::Author::reset();
    MT::Permission::reset();
    MT::Placement::reset();
    MT::Category::reset();
    _seed_author();
    _seed_entry(id => 1);

    for my $spec ([ 2, 'News', 'category' ], [ 3, 'Tech', 'category' ], [ 4, 'Docs', 'folder' ]) {
        my ($id, $label, $class) = @$spec;
        my $c = MT::Category->new;
        $c->id($id);
        $c->blog_id(1);
        $c->label($label);
        $c->class($class);
        $c->save;
        my $pl = MT::Placement->new;
        $pl->entry_id(1);
        $pl->blog_id(1);
        $pl->category_id($id);
        $pl->is_primary($id == 2 ? 1 : 0);
        $pl->save;
    }

    $MT::Category::LOAD_COUNT = 0;
    my $got = MTMCP::Tools::Entry::export(
        _app(id => 1, is_superuser => 1),
        { entry_id => 1 },
    );
    is($MT::Category::LOAD_COUNT, 1, 'カテゴリ3件でも MT::Category->load は1回');
    like($got->{body}, qr/^CATEGORY: News$/m, 'News が出る');
    like($got->{body}, qr/^CATEGORY: Tech$/m, 'Tech が出る');
    unlike($got->{body}, qr/Docs/, 'folder は除外したまま');
    is(scalar(() = $got->{body} =~ /^PRIMARY CATEGORY: /mg), 1, 'PRIMARY CATEGORY は1行だけ');
    like($got->{body}, qr/^PRIMARY CATEGORY: News$/m, 'PRIMARY は is_primary の placement');
}

# 参照先が消えている category_id は現行どおりスキップする。
{
    MT::Entry::reset();
    MT::Author::reset();
    MT::Permission::reset();
    MT::Placement::reset();
    MT::Category::reset();
    _seed_author();
    _seed_entry(id => 1);
    my $pl = MT::Placement->new;
    $pl->entry_id(1);
    $pl->blog_id(1);
    $pl->category_id(999);
    $pl->is_primary(1);
    $pl->save;

    my $got = MTMCP::Tools::Entry::export(
        _app(id => 1, is_superuser => 1),
        { entry_id => 1 },
    );
    unlike($got->{body}, qr/^CATEGORY: /m, '見つからない category_id は行を出さない');
}

done_testing();
