use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../plugins/MTMCP/lib";

use MTMCP::Tools::Template;

{
    no warnings 'redefine';
    *MTMCP::Perm::require_blog_permission = sub { 1 };
    *MTMCP::Perm::require_blog_access     = sub { 1 };
}

my $app = bless {}, 'FakeApp';

sub _create {
    my %args = @_;
    return MTMCP::Tools::Template::create($app, {
        blog_id => 1,
        name    => 'Test WidgetSet',
        type    => 'widgetset',
        %args,
    });
}

sub _update {
    my ($tmpl_id, %args) = @_;
    return MTMCP::Tools::Template::update($app, {
        template_id => $tmpl_id,
        %args,
    });
}

my $WIDGETSET_BODY_RE = qr/type が widgetset のときは body を指定できません/;

# ------------------------------------------------------------------
# create
# ------------------------------------------------------------------

{
    MT::Template::reset();
    my $got = eval { _create(body => '<mt:Include widget="Foo">') };
    my $err = $@;
    ok(!$got, 'template_create(widgetset + body) は成功しない');
    like($err, $WIDGETSET_BODY_RE, 'template_create は body が保存されないことをエラーにする');
    is(scalar @MT::Template::SAVED, 0, 'template_create(widgetset + body) は保存しない');
}

{
    MT::Template::reset();
    my $got = eval { _create(body => '') };
    my $err = $@;
    ok(!$got, 'template_create(widgetset + 空の body) も成功しない');
    like($err, $WIDGETSET_BODY_RE, '空文字の body でもエラーになる');
}

{
    MT::Template::reset();
    my $got = eval { _create() };
    my $err = $@;
    ok($got, 'template_create(widgetset, body なし) は成功する') or diag($err);
    is($got->{status}, 'created', 'status は created');
    is($got->{type}, 'widgetset', 'type は widgetset');
    is(scalar @MT::Template::SAVED, 1, 'body なしなら保存される');
}

{
    MT::Template::reset();
    my $got = eval {
        MTMCP::Tools::Template::create($app, {
            blog_id => 1,
            name    => 'Index',
            type    => 'index',
            body    => '<html></html>',
            outfile => 'index.html',
        });
    };
    my $err = $@;
    ok($got, 'index + body の create は従来どおり成功する') or diag($err);
    is($MT::Template::SAVED[0]->text, '<html></html>', 'index の body は保存される');
}

# ------------------------------------------------------------------
# update
# ------------------------------------------------------------------

{
    MT::Template::reset();
    my $tmpl = MT::Template->new;
    $tmpl->id(10);
    $tmpl->blog_id(1);
    $tmpl->name('Existing WidgetSet');
    $tmpl->type('widgetset');
    $tmpl->text('');
    $tmpl->save;
    @MT::Template::SAVED = ();

    my $got = eval { _update(10, body => '<mt:Include widget="Foo">') };
    my $err = $@;
    ok(!$got, 'template_update(既存 widgetset + body) は成功しない');
    like($err, $WIDGETSET_BODY_RE, 'template_update は body が保存されないことをエラーにする');
    is(scalar @MT::Template::SAVED, 0, 'template_update(widgetset + body) は保存しない');
    is(MT::Template->load(10)->text, '', '既存 widgetset の text は変わらない');
}

{
    MT::Template::reset();
    my $tmpl = MT::Template->new;
    $tmpl->id(11);
    $tmpl->blog_id(1);
    $tmpl->name('Existing WidgetSet');
    $tmpl->type('widgetset');
    $tmpl->save;
    @MT::Template::SAVED = ();

    my $got = eval { _update(11, name => 'Renamed WidgetSet') };
    my $err = $@;
    ok($got, 'template_update(既存 widgetset, name のみ) は成功する') or diag($err);
    is($got->{status}, 'updated', 'status は updated');
    is($got->{name}, 'Renamed WidgetSet', 'name は更新される');
}

{
    MT::Template::reset();
    my $tmpl = MT::Template->new;
    $tmpl->id(12);
    $tmpl->blog_id(1);
    $tmpl->name('Index');
    $tmpl->type('index');
    $tmpl->text('old');
    $tmpl->outfile('index.html');
    $tmpl->save;
    @MT::Template::SAVED = ();

    my $got = eval { _update(12, body => '<html>new</html>') };
    my $err = $@;
    ok($got, 'index の body 更新は従来どおり成功する') or diag($err);
    is(MT::Template->load(12)->text, '<html>new</html>', 'index の body は保存される');
}

{
    MT::Template::reset();
    my $tmpl = MT::Template->new;
    $tmpl->id(13);
    $tmpl->blog_id(1);
    $tmpl->name('Custom');
    $tmpl->type('custom');
    $tmpl->text('old');
    $tmpl->save;
    @MT::Template::SAVED = ();

    my $got = eval { _update(13, type => 'widgetset', body => '<mt:Include widget="Foo">') };
    my $err = $@;
    ok(!$got, 'type を widgetset に変更しつつ body を渡すとエラー');
    like($err, $WIDGETSET_BODY_RE, '変更先 type が widgetset でも body は拒否される');
    is(MT::Template->load(13)->type, 'custom', 'type も変更されない');
}

{
    MT::Template::reset();
    my $tmpl = MT::Template->new;
    $tmpl->id(14);
    $tmpl->blog_id(1);
    $tmpl->name('Existing WidgetSet');
    $tmpl->type('widgetset');
    $tmpl->save;
    @MT::Template::SAVED = ();

    my $got = eval { _update(14, body => '<mt:Include widget="Foo">', skip_validation => 1) };
    my $err = $@;
    ok(!$got, 'skip_validation でも widgetset + body はエラー');
    like($err, $WIDGETSET_BODY_RE, 'skip_validation は構文検証のスキップであり body 破棄は防げない');
}

done_testing;
