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
    sub rebuild { die "rebuild should not be called\n" }
    sub rebuild_entry { die "rebuild_entry should not be called\n" }
}

sub _app {
    my (%user) = @_;
    return FakeApp->new(user => FakeUser->new(%user));
}

sub _reset {
    MT::Entry::reset();
    MT::Author::reset();
    MT::Permission::reset();
    MT::Placement::reset();
    MT::Category::reset();
}

my $mt_text = <<'MT';
AUTHOR: stranger
TITLE: Hello
BASENAME: hello
STATUS: Publish
DATE: 08/15/2026 08:00:00 AM
PRIMARY CATEGORY: News
CATEGORY: News
-----
BODY:
line1
line2
-----
EXTENDED BODY:
more
-----
EXCERPT:
ex
-----
--------
MT

{
    _reset();
    eval {
        MTMCP::Tools::Entry::import_entries(
            _app(id => 9, is_superuser => 1),
            { blog_id => 1, body => $mt_text },
        );
    };
    like($@, qr/confirm: true/, 'confirm なしは拒否');
}

{
    _reset();
    eval {
        MTMCP::Tools::Entry::import_entries(
            _app(id => 9, is_superuser => 1),
            { blog_id => 1, body => $mt_text, confirm => JSON::false() },
        );
    };
    like($@, qr/confirm: true/, 'confirm false は拒否');
}

{
    _reset();
    eval {
        MTMCP::Tools::Entry::import_entries(
            _app(id => 9, is_superuser => 1),
            { blog_id => 1, body => $mt_text, confirm => 1, ImportPath => '/tmp/import' },
        );
    };
    like($@, qr/ImportPath/, 'ImportPath は拒否');
}

{
    _reset();
    eval {
        MTMCP::Tools::Entry::import_entries(
            _app(id => 9, is_superuser => 1),
            { blog_id => 1, confirm => 1 },
        );
    };
    like($@, qr/body is required/, 'body なしは ImportPath に落ちない');
}

{
    _reset();
    eval {
        MTMCP::Tools::Entry::import_entries(
            _app(id => 9, is_superuser => 1),
            { blog_id => 1, body => $mt_text, confirm => 1, import_as_me => 0 },
        );
    };
    like($@, qr/import_as_me/, 'import_as_me 無効化は拒否');
}

{
    _reset();
    eval {
        MTMCP::Tools::Entry::import_entries(
            _app(id => 3, is_superuser => 0),
            { blog_id => 1, body => $mt_text, confirm => 1 },
        );
    };
    like($@, qr/権限/, '権限なしは拒否');
}

{
    _reset();
    MT::Permission->add(
        author_id   => 3,
        blog_id     => 1,
        permissions => { import_blog => 0 },
    );
    eval {
        MTMCP::Tools::Entry::import_entries(
            _app(id => 3, is_superuser => 0),
            { blog_id => 1, body => $mt_text, confirm => 1 },
        );
    };
    like($@, qr/ブログのインポート/, 'import_blog が無いと拒否');
}

{
    _reset();
    my $cat = MT::Category->new;
    $cat->id(2);
    $cat->blog_id(1);
    $cat->label('News');
    $cat->class('category');
    $cat->save;

    my $got = MTMCP::Tools::Entry::import_entries(
        _app(id => 9, is_superuser => 1),
        { blog_id => 1, body => $mt_text, confirm => 1 },
    );
    is($got->{imported}, 1, '1件インポート');
    is($got->{status}, 'imported', 'status imported');
    ok(!$got->{rebuilt}, '再構築しない');
    ok($got->{import_as_me}, 'import_as_me');
    my $e = MT::Entry->load({ id => $got->{entry_ids}[0], class => 'entry' });
    ok($e, 'Entry が保存される');
    is($e->class, 'entry', 'class は entry');
    is($e->title, 'Hello', 'title');
    is($e->text, "line1\nline2", 'body');
    is($e->text_more, 'more', 'extended');
    is($e->excerpt, 'ex', 'excerpt');
    is($e->author_id, 9, '著者は呼び出しユーザー（AUTHOR を無視）');
    is($e->status, MT::Entry::HOLD(), '省略時は draft');
    is($e->authored_on, '20260815080000', 'DATE を復元');
    my @pl = MT::Placement->load({ entry_id => $e->id });
    is(scalar @pl, 1, '既存カテゴリを付与');
}

{
    _reset();
    my $got = MTMCP::Tools::Entry::import_entries(
        _app(id => 9, is_superuser => 1),
        { blog_id => 1, body => $mt_text, confirm => 1, default_status => 'publish' },
    );
    my $e = MT::Entry->load({ id => $got->{entry_ids}[0], class => 'entry' });
    is($e->status, MT::Entry::RELEASE(), 'default_status=publish は公開');
}

{
    _reset();
    eval {
        MTMCP::Tools::Entry::import_entries(
            _app(id => 9, is_superuser => 1),
            { blog_id => 1, body => ('x' x 1_000_001), confirm => 1 },
        );
    };
    like($@, qr/1MB/, '1MB 超は拒否');
}

{
    _reset();
    _seed_roundtrip();
}

sub _seed_roundtrip {
    my $src = MT::Entry->new;
    $src->id(1);
    $src->blog_id(1);
    $src->title('Round');
    $src->text('exported body');
    $src->basename('round');
    $src->status(MT::Entry::RELEASE());
    $src->author_id(1);
    $src->authored_on('20260101120000');
    $src->class('entry');
    $src->save;
    my $exported = MTMCP::Tools::Entry::export(
        _app(id => 9, is_superuser => 1),
        { entry_id => 1 },
    );
    my $got = MTMCP::Tools::Entry::import_entries(
        _app(id => 9, is_superuser => 1),
        { blog_id => 1, body => $exported->{body}, confirm => JSON::true() },
    );
    is($got->{imported}, 1, 'export したテキストを import できる');
    my $e = MT::Entry->load({ id => $got->{entry_ids}[0], class => 'entry' });
    is($e->title, 'Round', 'round-trip title');
    is($e->text, 'exported body', 'round-trip body');
    is($e->author_id, 9, 'round-trip も import_as_me');
    is($e->status, MT::Entry::HOLD(), 'round-trip でも省略時は draft');
}

{
    _reset();
    MT::Permission->add(
        author_id   => 3,
        blog_id     => 1,
        permissions => { import_blog => 1 },
    );
    my $got = eval {
        MTMCP::Tools::Entry::import_entries(
            _app(id => 3, is_superuser => 0),
            { blog_id => 1, body => $mt_text, confirm => 1 },
        );
    };
    ok($got, 'import_blog があれば成功') or diag($@);
}

# 同じカテゴリラベルの記事を複数インポートしても load 回数が記事数に比例しない。
{
    _reset();
    for my $spec ([ 2, 'News' ], [ 3, 'Tech' ]) {
        my ($id, $label) = @$spec;
        my $c = MT::Category->new;
        $c->id($id);
        $c->blog_id(1);
        $c->label($label);
        $c->class('category');
        $c->save;
    }

    my $many = join '', map {
        my $n = $_;
        <<"MT";
TITLE: Bulk $n
BASENAME: bulk-$n
STATUS: Publish
PRIMARY CATEGORY: News
CATEGORY: News
CATEGORY: Tech
-----
BODY:
body $n
-----
--------
MT
    } (1 .. 5);

    $MT::Category::LOAD_COUNT = 0;
    my $got = MTMCP::Tools::Entry::import_entries(
        _app(id => 9, is_superuser => 1),
        { blog_id => 1, body => $many, confirm => 1 },
    );
    is($got->{imported}, 5, '5件インポート');
    is($MT::Category::LOAD_COUNT, 1, '記事5件・ラベル2種でも MT::Category->load は1回');
    for my $eid (@{ $got->{entry_ids} }) {
        my @pl = sort { $a->category_id <=> $b->category_id } MT::Placement->load({ entry_id => $eid });
        is(scalar @pl, 2, "entry $eid に2カテゴリ");
        is($pl[0]->category_id, 2, "entry $eid の News");
        is($pl[1]->category_id, 3, "entry $eid の Tech");
    }
}

# カテゴリが1件も無いインポートではカテゴリを引かない（遅延ロード）。
{
    _reset();
    my $no_cat = <<'MT';
TITLE: NoCat
BASENAME: nocat
STATUS: Publish
-----
BODY:
plain
-----
--------
MT
    $MT::Category::LOAD_COUNT = 0;
    my $got = MTMCP::Tools::Entry::import_entries(
        _app(id => 9, is_superuser => 1),
        { blog_id => 1, body => $no_cat, confirm => 1 },
    );
    is($got->{imported}, 1, 'カテゴリ無しでもインポートできる');
    is($MT::Category::LOAD_COUNT, 0, 'カテゴリが無ければ load しない');
}

# 存在しないラベルは現行どおり黙って落とす。
{
    _reset();
    my $c = MT::Category->new;
    $c->id(2);
    $c->blog_id(1);
    $c->label('News');
    $c->class('category');
    $c->save;
    # 別ブログの同名ラベルは拾わない
    my $other = MT::Category->new;
    $other->id(5);
    $other->blog_id(2);
    $other->label('Ghost');
    $other->class('category');
    $other->save;
    # folder は category として拾わない
    my $folder = MT::Category->new;
    $folder->id(6);
    $folder->blog_id(1);
    $folder->label('Files');
    $folder->class('folder');
    $folder->save;

    my $body = <<'MT';
TITLE: Partial
BASENAME: partial
STATUS: Publish
CATEGORY: News
CATEGORY: Ghost
CATEGORY: Files
-----
BODY:
b
-----
--------
MT
    my $got = MTMCP::Tools::Entry::import_entries(
        _app(id => 9, is_superuser => 1),
        { blog_id => 1, body => $body, confirm => 1 },
    );
    my @pl = MT::Placement->load({ entry_id => $got->{entry_ids}[0] });
    is(scalar @pl, 1, '同ブログの category だけ付与する');
    is($pl[0]->category_id, 2, 'News のみ');
}

done_testing();
