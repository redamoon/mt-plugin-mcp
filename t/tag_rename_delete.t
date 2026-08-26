use strict;
use warnings;
use utf8;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../plugins/MTMCP/lib";

use MTMCP::Tools::Tag;
use MT::Tag;
use MT::ObjectTag;

{
    no warnings 'redefine';
    *MTMCP::Perm::require_blog_access     = sub { 1 };
    *MTMCP::Perm::require_blog_permission = sub { 1 };
}

my $app = bless {}, 'FakeApp';

sub _reset {
    MT::Tag::reset();
    MT::ObjectTag::reset();
}

sub _seed_tag {
    my (%args) = @_;
    my $t = MT::Tag->new;
    $t->id($args{id}) if defined $args{id};
    $t->name($args{name} // 'tag');
    $t->n8d_id($args{n8d_id} // 0);
    $t->save;
    return $t;
}

sub _seed_ot {
    my (%args) = @_;
    my $ot = MT::ObjectTag->new;
    $ot->blog_id($args{blog_id} // 1);
    $ot->object_id($args{object_id} // 10);
    $ot->object_datasource($args{object_datasource} // 'entry');
    $ot->tag_id($args{tag_id});
    $ot->cf_id($args{cf_id} // 0);
    $ot->save;
    return $ot;
}

# ------------------------------------------------------------------
# in-place rename when unused elsewhere
# ------------------------------------------------------------------

{
    _reset();
    my $tag = _seed_tag(name => 'old');
    _seed_ot(blog_id => 1, tag_id => $tag->id, object_id => 1);
    my $got = eval {
        MTMCP::Tools::Tag::rename($app, { blog_id => 1, tag_id => $tag->id, name => 'new' });
    };
    ok($got, '他サイト未使用なら rename 成功') or diag($@);
    is($got->{status}, 'renamed', 'status は renamed');
    is($got->{tag_id}, $tag->id, '同じ ID のまま');
    is($got->{old_name}, 'old', 'old_name');
    is($got->{name}, 'new', 'name');
    is($got->{reassigned_count}, 0, 'in-place は ObjectTag 付け替えなし');
    is($got->{remaining_elsewhere}, 0, '他サイト残なし');
    my $reloaded = MT::Tag->load({ id => $tag->id });
    is($reloaded->name, 'new', '同じ ID の name が更新される');
}

# ------------------------------------------------------------------
# other-site use => clone/reassign this blog only; old tag remains
# ------------------------------------------------------------------

{
    _reset();
    my $tag = _seed_tag(name => 'shared');
    _seed_ot(blog_id => 1, tag_id => $tag->id, object_id => 1);
    _seed_ot(blog_id => 2, tag_id => $tag->id, object_id => 2);
    my $got = eval {
        MTMCP::Tools::Tag::rename($app, { blog_id => 1, tag_id => $tag->id, name => 'renamed-here' });
    };
    ok($got, '他サイト使用時の rename 成功') or diag($@);
    is($got->{status}, 'renamed', 'clone パスも renamed');
    isnt($got->{tag_id}, $tag->id, 'このサイトは新しいタグ ID');
    is($got->{reassigned_count}, 1, 'この blog の ObjectTag を付け替え');
    ok($got->{remaining_elsewhere}, '旧タグは他サイトに残る');
    my $old = MT::Tag->load({ id => $tag->id });
    ok($old, '旧タグマスタは残る');
    is($old->name, 'shared', '他サイト側の名前は変わらない');
    my ($ot1) = MT::ObjectTag->load({ blog_id => 1, object_id => 1 });
    is($ot1->tag_id, $got->{tag_id}, 'blog 1 は新タグ');
    my ($ot2) = MT::ObjectTag->load({ blog_id => 2, object_id => 2 });
    is($ot2->tag_id, $tag->id, 'blog 2 は旧タグのまま');
}

# ------------------------------------------------------------------
# merge into existing name; duplicate ObjectTag removed
# ------------------------------------------------------------------

{
    _reset();
    my $old = _seed_tag(name => 'from');
    my $dst = _seed_tag(name => 'to');
    _seed_ot(blog_id => 1, tag_id => $old->id, object_id => 1, object_datasource => 'entry');
    _seed_ot(blog_id => 1, tag_id => $old->id, object_id => 2, object_datasource => 'entry');
    _seed_ot(blog_id => 1, tag_id => $dst->id, object_id => 2, object_datasource => 'entry');
    my $got = eval {
        MTMCP::Tools::Tag::rename($app, { blog_id => 1, tag_id => $old->id, name => 'to' });
    };
    ok($got, 'merge rename 成功') or diag($@);
    is($got->{status}, 'merged', 'status は merged');
    is($got->{tag_id}, $dst->id, 'tag_id は既存の新名タグ');
    is($got->{reassigned_count}, 1, '未重複の 1 件だけ付け替え');
    my @ots_obj2 = MT::ObjectTag->load({ blog_id => 1, object_id => 2, object_datasource => 'entry' });
    is(scalar @ots_obj2, 1, '重複 ObjectTag は削除される');
    is($ots_obj2[0]->tag_id, $dst->id, '残った ObjectTag は新タグ');
    my ($ot1) = MT::ObjectTag->load({ blog_id => 1, object_id => 1 });
    is($ot1->tag_id, $dst->id, 'object 1 も新タグへ');
    ok(!MT::Tag->load({ id => $old->id }), '旧タグに ObjectTag が無ければ削除');
}

# ------------------------------------------------------------------
# empty / unnormalizable name error
# ------------------------------------------------------------------

{
    _reset();
    my $tag = _seed_tag(name => 'ok');
    _seed_ot(blog_id => 1, tag_id => $tag->id);
    my $got = eval {
        MTMCP::Tools::Tag::rename($app, { blog_id => 1, tag_id => $tag->id, name => '!!!' });
    };
    my $err = $@;
    ok(!$got, '正規化不能な name は失敗');
    like($err, qr/Invalid tag name/, 'Invalid tag name');
}

{
    _reset();
    my $tag = _seed_tag(name => 'ok');
    _seed_ot(blog_id => 1, tag_id => $tag->id);
    my $got = eval {
        MTMCP::Tools::Tag::rename($app, { blog_id => 1, tag_id => $tag->id, name => '' });
    };
    ok(!$got, '空 name は失敗');
    like($@, qr/Invalid tag name/, '空も Invalid tag name');
}

# ------------------------------------------------------------------
# same name => unchanged
# ------------------------------------------------------------------

{
    _reset();
    my $tag = _seed_tag(name => 'same');
    _seed_ot(blog_id => 1, tag_id => $tag->id);
    my $got = eval {
        MTMCP::Tools::Tag::rename($app, { blog_id => 1, tag_id => $tag->id, name => 'same' });
    };
    ok($got, '同一名は成功') or diag($@);
    is($got->{status}, 'unchanged', 'status は unchanged');
    is($got->{tag_id}, $tag->id, 'ID は変わらない');
    is(scalar @MT::Tag::SAVED, 1, '同一名では追加 save しない（seed の 1 回のみ）');
}

# ------------------------------------------------------------------
# tag_id not on this site => not found
# ------------------------------------------------------------------

{
    _reset();
    my $tag = _seed_tag(name => 'elsewhere');
    _seed_ot(blog_id => 2, tag_id => $tag->id);
    my $got = eval {
        MTMCP::Tools::Tag::rename($app, { blog_id => 1, tag_id => $tag->id, name => 'x' });
    };
    ok(!$got, '他サイトのタグは rename できない');
    like($@, qr/Tag not found/, 'Tag not found');
}

{
    _reset();
    my $n8d = _seed_tag(name => 'normalized');
    my $real = _seed_tag(name => 'Real', n8d_id => $n8d->id);
    _seed_ot(blog_id => 1, tag_id => $n8d->id);
    my $got = eval {
        MTMCP::Tools::Tag::rename($app, { blog_id => 1, tag_id => $n8d->id, name => 'hack' });
    };
    ok(!$got, 'n8d 専用タグは操作対象にしない');
    like($@, qr/Tag not found/, 'n8d 専用は Tag not found');
}

# ------------------------------------------------------------------
# delete: this-site ObjectTags only
# ------------------------------------------------------------------

{
    _reset();
    my $tag = _seed_tag(name => 'gone');
    _seed_ot(blog_id => 1, tag_id => $tag->id, object_id => 1);
    _seed_ot(blog_id => 1, tag_id => $tag->id, object_id => 2, object_datasource => 'asset');
    my $got = eval {
        MTMCP::Tools::Tag::remove($app, { blog_id => 1, tag_id => $tag->id, confirm => 1 });
    };
    ok($got, '他サイト残なし delete 成功') or diag($@);
    is($got->{status}, 'deleted', 'status は deleted');
    is($got->{removed_count}, 2, 'このサイトの ObjectTag を削除');
    is($got->{remaining_elsewhere}, 0, '残なし');
    ok(!MT::Tag->load({ id => $tag->id }), 'タグマスタも削除');
    ok(!MT::ObjectTag->exist({ tag_id => $tag->id }), 'ObjectTag なし');
}

{
    _reset();
    my $tag = _seed_tag(name => 'keep');
    _seed_ot(blog_id => 1, tag_id => $tag->id, object_id => 1);
    _seed_ot(blog_id => 2, tag_id => $tag->id, object_id => 9);
    my $got = eval {
        MTMCP::Tools::Tag::remove($app, { blog_id => 1, tag_id => $tag->id, confirm => 1 });
    };
    ok($got, '他サイト残あり delete 成功') or diag($@);
    is($got->{status}, 'unlinked', 'status は unlinked');
    is($got->{removed_count}, 1, 'このサイト分のみ');
    ok($got->{remaining_elsewhere}, '他サイトに残る');
    my $left = MT::Tag->load({ id => $tag->id });
    ok($left, 'タグマスタは残る');
    is($left->name, 'keep', '名前は維持');
    ok(!MT::ObjectTag->exist({ blog_id => 1, tag_id => $tag->id }), 'blog 1 の ObjectTag は無い');
    ok(MT::ObjectTag->exist({ blog_id => 2, tag_id => $tag->id }), 'blog 2 の ObjectTag は残る');
}

{
    _reset();
    my $tag = _seed_tag(name => 'nope');
    _seed_ot(blog_id => 2, tag_id => $tag->id);
    my $got = eval {
        MTMCP::Tools::Tag::remove($app, { blog_id => 1, tag_id => $tag->id, confirm => 1 });
    };
    ok(!$got, '当該サイトに無い tag の delete は失敗');
    like($@, qr/Tag not found/, 'delete も Tag not found');
}

# ------------------------------------------------------------------
# tag_list returns non-entry ObjectTags
# ------------------------------------------------------------------

{
    _reset();
    my $entry_tag = _seed_tag(name => 'entry-tag');
    my $asset_tag = _seed_tag(name => 'asset-tag');
    my $cd_tag    = _seed_tag(name => 'cd-tag');
    my $n8d       = _seed_tag(name => 'n8d-only');
    my $visible   = _seed_tag(name => 'visible', n8d_id => $n8d->id);
    _seed_ot(blog_id => 1, tag_id => $entry_tag->id, object_datasource => 'entry');
    _seed_ot(blog_id => 1, tag_id => $asset_tag->id, object_datasource => 'asset');
    _seed_ot(blog_id => 1, tag_id => $cd_tag->id, object_datasource => 'content_data', cf_id => 7);
    _seed_ot(blog_id => 1, tag_id => $n8d->id, object_datasource => 'entry');
    _seed_ot(blog_id => 1, tag_id => $visible->id, object_datasource => 'page');
    my $got = eval { MTMCP::Tools::Tag::list($app, { blog_id => 1 }) };
    ok($got, 'tag_list 成功') or diag($@);
    my %names = map { $_->{name} => 1 } @$got;
    ok($names{'entry-tag'}, 'entry のタグ');
    ok($names{'asset-tag'}, 'asset のタグ');
    ok($names{'cd-tag'}, 'content_data のタグ');
    ok($names{'visible'}, 'page のタグ');
    ok(!$names{'n8d-only'}, 'n8d 専用タグは一覧から除外');
}

# ------------------------------------------------------------------
# missing rename_tag / remove_tag permission
# ------------------------------------------------------------------

{
    _reset();
    my $tag = _seed_tag(name => 'perm');
    _seed_ot(blog_id => 1, tag_id => $tag->id);
    my %allowed = (edit_tags => 1);
    no warnings 'redefine';
    local *MTMCP::Perm::require_blog_permission = sub {
        my ($app, $blog_id, $action, $label) = @_;
        die "「$label」の権限がありません（blog_id: $blog_id）\n"
            unless $allowed{$action};
    };
    my $got = eval {
        MTMCP::Tools::Tag::rename($app, { blog_id => 1, tag_id => $tag->id, name => 'x' });
    };
    ok(!$got, 'rename_tag 欠如は失敗');
    like($@, qr/タグの名前変更/, 'rename_tag のラベル');
}

{
    _reset();
    my $tag = _seed_tag(name => 'perm');
    _seed_ot(blog_id => 1, tag_id => $tag->id);
    my %allowed = (rename_tag => 1);
    no warnings 'redefine';
    local *MTMCP::Perm::require_blog_permission = sub {
        my ($app, $blog_id, $action, $label) = @_;
        die "「$label」の権限がありません（blog_id: $blog_id）\n"
            unless $allowed{$action};
    };
    my $got = eval {
        MTMCP::Tools::Tag::rename($app, { blog_id => 1, tag_id => $tag->id, name => 'x' });
    };
    ok(!$got, 'edit_tags 欠如も失敗');
    like($@, qr/タグの編集/, 'edit_tags のラベル');
}

{
    _reset();
    my $tag = _seed_tag(name => 'perm');
    _seed_ot(blog_id => 1, tag_id => $tag->id);
    my %allowed = ();
    no warnings 'redefine';
    local *MTMCP::Perm::require_blog_permission = sub {
        my ($app, $blog_id, $action, $label) = @_;
        die "「$label」の権限がありません（blog_id: $blog_id）\n"
            unless $allowed{$action};
    };
    my $got = eval {
        MTMCP::Tools::Tag::remove($app, { blog_id => 1, tag_id => $tag->id, confirm => 1 });
    };
    ok(!$got, 'remove_tag 欠如は失敗');
    like($@, qr/タグの削除/, 'remove_tag のラベル');
}

done_testing;
