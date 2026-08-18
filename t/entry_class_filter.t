use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../plugins/MTMCP/lib";

use MTMCP::Tools::Entry;
use MTMCP::Tools::Rebuild;
use MT::Blog;
use MT::Placement;
use MT::Category;

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
sub config { $_[0]{config} }

package main;

my $app = bless {}, 'FakeApp';

sub _seed_entry {
    my (%args) = @_;
    my $e = MT::Entry->new;
    $e->id($args{id} // 1);
    $e->blog_id($args{blog_id} // 1);
    $e->title($args{title} // 'A genuine entry');
    $e->text($args{text} // 'entry body');
    $e->status($args{status} // MT::Entry::HOLD());
    $e->class('entry');
    $e->save;
    return $e;
}

sub _seed_page {
    my (%args) = @_;
    my $p = MT::Entry->new;
    $p->id($args{id} // 99);
    $p->blog_id($args{blog_id} // 1);
    $p->title($args{title} // 'A page, not an entry');
    $p->text($args{text} // 'page body');
    $p->status($args{status} // MT::Entry::RELEASE());
    $p->class('page');
    $p->save;
    return $p;
}

# ------------------------------------------------------------------
# Page ID は entry_* で見つからない
# ------------------------------------------------------------------

{
    MT::Entry::reset();
    _seed_page(id => 99);
    my $got = eval { MTMCP::Tools::Entry::get($app, { entry_id => 99 }) };
    my $err = $@;
    ok(!$got, 'entry_get(Page ID) は成功しない');
    like($err, qr/Entry not found: 99/, 'entry_get は Page ID を Entry not found にする');
    is(ref $MT::Entry::LAST_LOAD_TERMS, 'HASH', 'entry_get はハッシュで load する');
    is($MT::Entry::LAST_LOAD_TERMS->{class}, 'entry', 'entry_get は class => entry を渡す');
}

{
    MT::Entry::reset();
    _seed_page(id => 99);
    my $got = eval {
        MTMCP::Tools::Entry::update($app, { entry_id => 99, title => 'hacked' });
    };
    my $err = $@;
    ok(!$got, 'entry_update(Page ID) は成功しない');
    like($err, qr/Entry not found: 99/, 'entry_update は Page ID を Entry not found にする');
    is(scalar @MT::Entry::SAVED, 1, 'entry_update(Page ID) は保存しない');
    is(MT::Entry->load(99)->title, 'A page, not an entry', 'Page のタイトルは変わらない');
}

{
    MT::Entry::reset();
    _seed_page(id => 99);
    my $got = eval { MTMCP::Tools::Entry::remove($app, { entry_id => 99 }) };
    my $err = $@;
    ok(!$got, 'entry_delete(Page ID) は成功しない');
    like($err, qr/Entry not found: 99/, 'entry_delete は Page ID を Entry not found にする');
    is(scalar @MT::Entry::REMOVED, 0, 'entry_delete(Page ID) は削除しない');
    ok(MT::Entry->load(99), 'Page は残っている');
}

{
    MT::Entry::reset();
    _seed_page(id => 99);
    my $got = eval { MTMCP::Tools::Rebuild::entry($app, { entry_id => 99 }) };
    my $err = $@;
    ok(!$got, 'rebuild_entry(Page ID) は成功しない');
    like($err, qr/Entry not found: 99/, 'rebuild_entry は Page ID を Entry not found にする');
}

# ------------------------------------------------------------------
# 本物の Entry ID は従来どおり動く
# ------------------------------------------------------------------

{
    MT::Entry::reset();
    _seed_entry(id => 1, title => 'Hello', text => 'world');
    my $got = eval { MTMCP::Tools::Entry::get($app, { entry_id => 1 }) };
    my $err = $@;
    ok($got, 'entry_get(Entry ID) は成功する') or diag($err);
    is($got->{id},    1,       'id は 1');
    is($got->{title}, 'Hello', 'title は Hello');
    is($got->{body},  'world', 'body を返す');
}

{
    MT::Entry::reset();
    _seed_entry(id => 1, title => 'Old');
    @MT::Entry::SAVED = ();
    my $got = eval {
        MTMCP::Tools::Entry::update($app, { entry_id => 1, title => 'New' });
    };
    my $err = $@;
    ok($got, 'entry_update(Entry ID) は成功する') or diag($err);
    is($got->{status}, 'updated', 'status は updated');
    is($got->{title},  'New',     '返却 title は更新後');
    is(MT::Entry->load({ id => 1, class => 'entry' })->title, 'New', '保存された title も更新される');
}

{
    MT::Entry::reset();
    _seed_entry(id => 1, title => 'Delete me');
    my $got = eval { MTMCP::Tools::Entry::remove($app, { entry_id => 1 }) };
    my $err = $@;
    ok($got, 'entry_delete(Entry ID) は成功する') or diag($err);
    is($got->{status}, 'deleted', 'status は deleted');
    is(scalar @MT::Entry::REMOVED, 1, 'remove が呼ばれる');
    ok(!MT::Entry->load({ id => 1, class => 'entry' }), 'Entry はストアから消える');
}

# 同じ ID 空間に Page と Entry が共存しても Entry だけを対象にする
{
    MT::Entry::reset();
    _seed_entry(id => 1);
    _seed_page(id => 99);
    my $got = eval { MTMCP::Tools::Entry::get($app, { entry_id => 1 }) };
    ok($got, 'Entry と Page が共存しても Entry ID は取得できる') or diag($@);
    is($got->{id}, 1, '取得したのは Entry');
    my $page = eval { MTMCP::Tools::Entry::get($app, { entry_id => 99 }) };
    ok(!$page, '共存していても Page ID は取得できない');
}


{
    MT::Entry::reset();
    MT::Blog::reset();
    _seed_entry(id => 1, title => 'Delete files');
    my $app_on = bless { config => FakeConfig->new(1) }, 'FakeApp';
    my $got = eval { MTMCP::Tools::Entry::remove($app_on, { entry_id => 1 }) };
    ok($got, 'DeleteFilesAtRebuild 時も entry_delete は成功') or diag($@);
    is(scalar @MT::Blog::_Publisher::REMOVED_ARCHIVE, 1, 'entry も公開アーカイブ削除を呼ぶ');
    is($MT::Blog::_Publisher::REMOVED_ARCHIVE[0]{ArchiveType}, 'Individual', 'ArchiveType は Individual');
}

{
    MT::Entry::reset();
    MT::Blog::reset();
    _seed_entry(id => 1, title => 'Keep files');
    my $app_off = bless { config => FakeConfig->new(0) }, 'FakeApp';
    my $got = eval { MTMCP::Tools::Entry::remove($app_off, { entry_id => 1 }) };
    ok($got, '無効時も entry_delete は成功') or diag($@);
    is(scalar @MT::Blog::_Publisher::REMOVED_ARCHIVE, 0, 'entry も無効時は公開ファイルを消さない');
}

# ------------------------------------------------------------------
# entry_get のカテゴリ解決（バッチロード。folder は現行どおり除外しない）
# ------------------------------------------------------------------

{
    MT::Entry::reset();
    MT::Placement::reset();
    MT::Category::reset();
    _seed_entry(id => 1);

    for my $spec ([ 2, 'News', 'category' ], [ 3, 'Tech', 'category' ], [ 4, 'Files', 'folder' ]) {
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
    # 参照先が消えている placement は落ちる
    my $dangling = MT::Placement->new;
    $dangling->entry_id(1);
    $dangling->blog_id(1);
    $dangling->category_id(999);
    $dangling->save;

    $MT::Category::LOAD_COUNT = 0;
    my $got = eval { MTMCP::Tools::Entry::get($app, { entry_id => 1 }) };
    ok($got, 'entry_get は成功する') or diag($@);
    is($MT::Category::LOAD_COUNT, 1, 'placement 4件でも MT::Category->load は1回');
    my @labels = sort map { $_->{label} } @{ $got->{categories} };
    is_deeply(\@labels, [ 'Files', 'News', 'Tech' ], 'entry_get は folder を除外しない（現行互換）');
}

done_testing;
