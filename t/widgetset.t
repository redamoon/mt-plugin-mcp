use strict;
use warnings;
use utf8;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../plugins/MTMCP/lib";

use MTMCP::Tools::Widget;

{
    no warnings 'redefine';
    *MTMCP::Perm::require_blog_permission = sub { 1 };
    *MTMCP::Perm::require_blog_access     = sub { 1 };
}

my $app = bless {}, 'FakeApp';

my $WIDGETSET_BODY_RE = qr/type が widgetset のときは body を指定できません/;

sub _seed_widget {
    my %args = @_;
    my $w = MT::Template->new;
    $w->id($args{id}) if defined $args{id};
    $w->blog_id($args{blog_id} // 1);
    $w->name($args{name} // 'Widget');
    $w->type('widget');
    $w->text($args{text} // '');
    $w->save;
    return $w;
}

sub _seed_index {
    my %args = @_;
    my $t = MT::Template->new;
    $t->id($args{id}) if defined $args{id};
    $t->blog_id($args{blog_id} // 1);
    $t->name($args{name} // 'Index');
    $t->type('index');
    $t->text($args{text} // '');
    $t->outfile($args{outfile} // 'index.html');
    $t->save;
    return $t;
}

sub _create {
    my %args = @_;
    return MTMCP::Tools::Widget::create($app, {
        blog_id => 1,
        name    => 'My WidgetSet',
        %args,
    });
}

sub _update {
    my ($ws_id, %args) = @_;
    return MTMCP::Tools::Widget::update($app, {
        widgetset_id => $ws_id,
        %args,
    });
}

sub _widget_ids {
    my ($widgets) = @_;
    return [ map { $_->{id} } @$widgets ];
}

sub _widget_names {
    my ($widgets) = @_;
    return [ map { $_->{name} } @$widgets ];
}

# ------------------------------------------------------------------
# create: widget_ids を modulesets に保存し、順を保持する
# ------------------------------------------------------------------

{
    MT::Template::reset();
    my $a = _seed_widget(name => 'Alpha');
    my $b = _seed_widget(name => 'Beta');
    my $c = _seed_widget(name => 'Gamma');
    @MT::Template::SAVED = ();

    my $got = eval {
        _create(name => 'Ordered Set', widget_ids => [ $c->id, $a->id, $b->id ]);
    };
    my $err = $@;
    ok($got, 'widgetset_create は成功する') or diag($err);
    is($got->{status}, 'created', 'status は created');
    is($got->{name}, 'Ordered Set', 'name が返る');
    is_deeply(_widget_ids($got->{widgets}), [ $c->id, $a->id, $b->id ], 'create の widgets は引数順');
    is_deeply(_widget_names($got->{widgets}), [ 'Gamma', 'Alpha', 'Beta' ], 'create の widgets は名前付き');

    my $saved = MT::Template->load($got->{widgetset_id});
    is($saved->type, 'widgetset', 'type は widgetset');
    is($saved->modulesets, join(',', $c->id, $a->id, $b->id), 'modulesets は引数順のカンマ区切り');
    like($saved->text, qr/widget="Gamma"/, 'save_widgetset が text を再生成する');
}

{
    MT::Template::reset();
    my $got = eval { _create() };
    my $err = $@;
    ok($got, 'widget_ids 省略時は空セットで作成できる') or diag($err);
    is_deeply($got->{widgets}, [], '省略時の widgets は空');
    is(MT::Template->load($got->{widgetset_id})->modulesets, '', 'modulesets は空');
}

{
    MT::Template::reset();
    my $got = eval { _create(widget_ids => []) };
    my $err = $@;
    ok($got, '空の widget_ids でも作成できる') or diag($err);
    is_deeply($got->{widgets}, [], '空配列の widgets は空');
}

# ------------------------------------------------------------------
# list / get: modulesets 順の widgets
# ------------------------------------------------------------------

{
    MT::Template::reset();
    my $a = _seed_widget(name => 'Alpha');
    my $b = _seed_widget(name => 'Beta');
    my $c = _seed_widget(name => 'Gamma');
    my $created = _create(name => 'Ordered Set', widget_ids => [ $c->id, $a->id, $b->id ]);

    my $listed = eval { MTMCP::Tools::Widget::list($app, { blog_id => 1 }) };
    my $err = $@;
    ok($listed, 'widgetset_list は成功する') or diag($err);
    is(scalar @$listed, 1, 'widgetset は1件');
    is_deeply(_widget_ids($listed->[0]{widgets}), [ $c->id, $a->id, $b->id ], 'list の widgets は modulesets 順');
    ok(!exists $listed->[0]{body}, 'list は body を返さない');

    my $got = eval { MTMCP::Tools::Widget::get($app, { widgetset_id => $created->{widgetset_id} }) };
    $err = $@;
    ok($got, 'widgetset_get は成功する') or diag($err);
    is($got->{id}, $created->{widgetset_id}, 'get の id');
    is($got->{blog_id}, 1, 'get の blog_id');
    is($got->{type}, 'widgetset', 'get の type');
    is($got->{modulesets}, join(',', $c->id, $a->id, $b->id), 'get の modulesets');
    is_deeply(_widget_ids($got->{widgets}), [ $c->id, $a->id, $b->id ], 'get の widgets は modulesets 順');
    ok(!exists $got->{body}, 'get は body を返さない');
    ok(!exists $got->{text}, 'get は text も返さない');
}

{
    MT::Template::reset();
    _seed_index(name => 'Not a set');
    my $idx = MT::Template->load({ name => 'Not a set', type => 'index' });
    my $got = eval { MTMCP::Tools::Widget::get($app, { widgetset_id => $idx->id }) };
    my $err = $@;
    ok(!$got, 'widget 以外の ID で get は失敗する');
    like($err, qr/ウィジェットセットではありません/, 'type が widgetset でなければエラー');
}

{
    MT::Template::reset();
    my $got = eval { MTMCP::Tools::Widget::get($app, { widgetset_id => 999 }) };
    my $err = $@;
    ok(!$got, '存在しない ID で get は失敗する');
    like($err, qr/WidgetSet not found: 999/, '見つからないときは WidgetSet not found');
}

# ------------------------------------------------------------------
# update: 全置換・空配列・name のみ
# ------------------------------------------------------------------

{
    MT::Template::reset();
    my $a = _seed_widget(name => 'Alpha');
    my $b = _seed_widget(name => 'Beta');
    my $c = _seed_widget(name => 'Gamma');
    my $created = _create(widget_ids => [ $a->id, $b->id ]);
    @MT::Template::SAVED = ();

    my $got = eval { _update($created->{widgetset_id}, widget_ids => [ $c->id, $a->id ]) };
    my $err = $@;
    ok($got, 'widgetset_update(widget_ids) は成功する') or diag($err);
    is($got->{status}, 'updated', 'status は updated');
    is_deeply(_widget_ids($got->{widgets}), [ $c->id, $a->id ], 'update は全置換で順を保持する');
    is(MT::Template->load($created->{widgetset_id})->modulesets, join(',', $c->id, $a->id), 'modulesets が置換される');
}

{
    MT::Template::reset();
    my $a = _seed_widget(name => 'Alpha');
    my $created = _create(widget_ids => [ $a->id ]);
    @MT::Template::SAVED = ();

    my $got = eval { _update($created->{widgetset_id}, widget_ids => []) };
    my $err = $@;
    ok($got, '空配列で割当解除できる') or diag($err);
    is_deeply($got->{widgets}, [], 'widgets は空');
    is(MT::Template->load($created->{widgetset_id})->modulesets, '', 'modulesets は空文字');
}

{
    MT::Template::reset();
    my $a = _seed_widget(name => 'Alpha');
    my $b = _seed_widget(name => 'Beta');
    my $created = _create(name => 'Old Name', widget_ids => [ $b->id, $a->id ]);
    my $before  = MT::Template->load($created->{widgetset_id})->modulesets;
    @MT::Template::SAVED = ();

    my $got = eval { _update($created->{widgetset_id}, name => 'New Name') };
    my $err = $@;
    ok($got, 'name のみの update は成功する') or diag($err);
    is($got->{name}, 'New Name', 'name は更新される');
    is(MT::Template->load($created->{widgetset_id})->modulesets, $before, 'name のみでは modulesets を壊さない');
    is_deeply(_widget_ids($got->{widgets}), [ $b->id, $a->id ], 'widgets の順も維持');
}

{
    MT::Template::reset();
    my $created = _create();
    my $got = eval { _update($created->{widgetset_id}) };
    my $err = $@;
    ok(!$got, '更新項目なしはエラー');
    like($err, qr/更新する項目がありません/, 'name / widget_ids が必要');
}

# ------------------------------------------------------------------
# 不正 ID / 非 widget / 他ブログ / 重複 → 保存せずエラー
# ------------------------------------------------------------------

{
    MT::Template::reset();
    my $a = _seed_widget(name => 'Alpha');
    @MT::Template::SAVED = ();
    my $got = eval { _create(widget_ids => [ $a->id, 999 ]) };
    my $err = $@;
    ok(!$got, '存在しない widget_id はエラー');
    like($err, qr/ウィジェットが見つかりません: 999/, '不正 ID を黙って落とさない');
    is(scalar @MT::Template::SAVED, 0, '不正 ID では保存しない');
}

{
    MT::Template::reset();
    my $a   = _seed_widget(name => 'Alpha');
    my $idx = _seed_index(name => 'Not Widget');
    @MT::Template::SAVED = ();
    my $got = eval { _create(widget_ids => [ $a->id, $idx->id ]) };
    my $err = $@;
    ok(!$got, '非 widget の ID はエラー');
    like($err, qr/はウィジェットではありません/, 'type=widget 以外は拒否');
    is(scalar @MT::Template::SAVED, 0, '非 widget では保存しない');
}

{
    MT::Template::reset();
    my $mine  = _seed_widget(name => 'Mine', blog_id => 1);
    my $other = _seed_widget(name => 'Other', blog_id => 2);
    @MT::Template::SAVED = ();
    my $got = eval { _create(widget_ids => [ $mine->id, $other->id ]) };
    my $err = $@;
    ok(!$got, '他ブログの widget はエラー');
    like($err, qr/このサイトに属していません/, '他ブログの widget は拒否');
    is(scalar @MT::Template::SAVED, 0, '他ブログ widget では保存しない');
}

{
    MT::Template::reset();
    my $sys = _seed_widget(name => 'System', blog_id => 0);
    @MT::Template::SAVED = ();
    my $got = eval { _create(widget_ids => [ $sys->id ]) };
    my $err = $@;
    ok($got, 'blog_id=0 のシステムウィジェットは割り当てできる') or diag($err);
    is_deeply(_widget_ids($got->{widgets}), [ $sys->id ], 'グローバル widget が含まれる');
}

{
    MT::Template::reset();
    my $a = _seed_widget(name => 'Alpha');
    @MT::Template::SAVED = ();
    my $got = eval { _create(widget_ids => [ $a->id, $a->id ]) };
    my $err = $@;
    ok(!$got, '重複 ID はエラー');
    like($err, qr/重複があります/, '重複を拒否');
    is(scalar @MT::Template::SAVED, 0, '重複では保存しない');
}

{
    MT::Template::reset();
    my $a = _seed_widget(name => 'Alpha');
    my $created = _create(widget_ids => [ $a->id ]);
    @MT::Template::SAVED = ();
    my $got = eval { _update($created->{widgetset_id}, widget_ids => [ 888 ]) };
    my $err = $@;
    ok(!$got, 'update の不正 ID もエラー');
    like($err, qr/ウィジェットが見つかりません: 888/, 'update も黙って落とさない');
    is(scalar @MT::Template::SAVED, 0, 'update の不正 ID では保存しない');
    is(MT::Template->load($created->{widgetset_id})->modulesets, '' . $a->id, '既存の modulesets は変わらない');
}

# ------------------------------------------------------------------
# body 付き create / update はエラー
# ------------------------------------------------------------------

{
    MT::Template::reset();
    my $got = eval { _create(body => '<mt:Include widget="Foo">') };
    my $err = $@;
    ok(!$got, 'widgetset_create + body は成功しない');
    like($err, $WIDGETSET_BODY_RE, 'create は body を拒否する');
    is(scalar @MT::Template::SAVED, 0, 'body 付き create は保存しない');
}

{
    MT::Template::reset();
    my $got = eval { _create(body => '') };
    my $err = $@;
    ok(!$got, '空文字の body でも create はエラー');
    like($err, $WIDGETSET_BODY_RE, '空文字 body も拒否');
}

{
    MT::Template::reset();
    my $created = _create();
    @MT::Template::SAVED = ();
    my $got = eval { _update($created->{widgetset_id}, name => 'X', body => '<mt:Include widget="Foo">') };
    my $err = $@;
    ok(!$got, 'widgetset_update + body は成功しない');
    like($err, $WIDGETSET_BODY_RE, 'update は body を拒否する');
    is(scalar @MT::Template::SAVED, 0, 'body 付き update は保存しない');
}

# ------------------------------------------------------------------
# delete: セットだけ消し、widget は残す
# ------------------------------------------------------------------

{
    MT::Template::reset();
    my $a = _seed_widget(name => 'Keep Me');
    my $created = _create(name => 'To Delete', widget_ids => [ $a->id ]);
    @MT::Template::REMOVED = ();

    my $got = eval {
        MTMCP::Tools::Widget::remove($app, { widgetset_id => $created->{widgetset_id}, confirm => 1 });
    };
    my $err = $@;
    ok($got, 'widgetset_delete は成功する') or diag($err);
    is($got->{status}, 'deleted', 'status は deleted');
    is($got->{name}, 'To Delete', '削除した name が返る');
    is($got->{widgetset_id}, $created->{widgetset_id}, '削除した id が返る');
    ok(!MT::Template->load($created->{widgetset_id}), 'セットは STORE から消える');
    ok(MT::Template->load($a->id), 'ウィジェット本体は残る');
    is(MT::Template->load($a->id)->type, 'widget', '残ったオブジェクトは widget');
}

{
    MT::Template::reset();
    my $idx = _seed_index();
    my $got = eval { MTMCP::Tools::Widget::remove($app, { widgetset_id => $idx->id, confirm => 1 }) };
    my $err = $@;
    ok(!$got, 'index を widgetset_delete できない');
    like($err, qr/ウィジェットセットではありません/, 'type チェック');
    ok(MT::Template->load($idx->id), 'index は削除されない');
}

# ------------------------------------------------------------------
# widget_list: サイト一覧 vs セット内一覧
# ------------------------------------------------------------------

{
    MT::Template::reset();
    my $a   = _seed_widget(name => 'Site A', blog_id => 1);
    my $b   = _seed_widget(name => 'Site B', blog_id => 1);
    my $sys = _seed_widget(name => 'Global', blog_id => 0);
    my $oth = _seed_widget(name => 'Other Blog', blog_id => 2);
    my $set = _create(name => 'Set', widget_ids => [ $b->id, $a->id ]);

    my $site = eval { MTMCP::Tools::Widget::list_widgets($app, { blog_id => 1 }) };
    my $err  = $@;
    ok($site, 'widget_list(サイト) は成功する') or diag($err);
    my %by_id = map { $_->{id} => $_ } @$site;
    ok($by_id{ $a->id },   'サイトの widget が含まれる');
    ok($by_id{ $b->id },   'サイトのもう一つの widget が含まれる');
    ok($by_id{ $sys->id }, 'blog_id=0 のシステムウィジェットが含まれる');
    ok(!$by_id{ $oth->id }, '他ブログの widget は含まれない');
    ok(!$by_id{ $set->{widgetset_id} }, 'widgetset 自体は widget_list に出ない');

    my $in_set = eval {
        MTMCP::Tools::Widget::list_widgets($app, {
            blog_id      => 1,
            widgetset_id => $set->{widgetset_id},
        });
    };
    $err = $@;
    ok($in_set, 'widget_list(セット内) は成功する') or diag($err);
    is_deeply([ map { $_->{id} } @$in_set ], [ $b->id, $a->id ], 'セット内一覧は modulesets 順（load 順に依存しない）');
    is(scalar @$in_set, 2, 'セットに無い widget / グローバルはセット内一覧に出ない');
}

{
    MT::Template::reset();
    my $keep = _seed_widget(name => 'Keep');
    my $skip = _seed_widget(name => 'SkipMe');
    my $listed = eval {
        MTMCP::Tools::Widget::list_widgets($app, { blog_id => 1, keyword => 'Keep' });
    };
    my $err = $@;
    ok($listed, 'keyword 付き widget_list は成功する') or diag($err);
    is(scalar @$listed, 1, 'keyword は name で絞り込む');
    is($listed->[0]{name}, 'Keep', 'マッチした widget だけ');
}

{
    MT::Template::reset();
    _seed_widget(name => 'Alpha');
    my $got = eval {
        MTMCP::Tools::Widget::list_widgets($app, { blog_id => 1, widgetset_id => 999 });
    };
    my $err = $@;
    ok(!$got, '存在しない widgetset_id での widget_list は失敗');
    like($err, qr/WidgetSet not found/, 'セットが無ければエラー');
}

done_testing;
