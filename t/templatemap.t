use strict;
use warnings;
use utf8;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../plugins/MTMCP/lib";

use MT::Blog;
use MT::Template;
use MT::TemplateMap;
use MTMCP::Tools::Template;
use MTMCP::Tools::TemplateMap;

{
    no warnings 'redefine';
    *MTMCP::Perm::require_blog_permission = sub { 1 };
    *MTMCP::Perm::require_blog_access     = sub { 1 };
}

my $app = bless {}, 'FakeApp';

sub _reset {
    MT::Template::reset();
    MT::TemplateMap::reset();
    MT::Blog::reset();
}

sub _seed_tmpl {
    my (%args) = @_;
    my $tmpl = MT::Template->new;
    $tmpl->id($args{id}) if defined $args{id};
    $tmpl->blog_id($args{blog_id} // 1);
    $tmpl->name($args{name} // 'Archive');
    $tmpl->type($args{type} // 'individual');
    $tmpl->text($args{text} // '');
    $tmpl->content_type_id($args{content_type_id}) if defined $args{content_type_id};
    $tmpl->save;
    return $tmpl;
}

sub _create_map {
    my ($tmpl_id, %args) = @_;
    return MTMCP::Tools::TemplateMap::create($app, {
        template_id  => $tmpl_id,
        archive_type => $args{archive_type} // 'Individual',
        %args,
    });
}

# ------------------------------------------------------------------
# list はそのテンプレートのマップだけを返す
# ------------------------------------------------------------------

{
    _reset();
    my $t1 = _seed_tmpl(name => 'Entry A', type => 'individual');
    my $t2 = _seed_tmpl(name => 'Entry B', type => 'individual');
    _create_map($t1->id);
    _create_map($t2->id);

    my $got = eval { MTMCP::Tools::TemplateMap::list($app, { template_id => $t1->id }) };
    my $err = $@;
    ok($got, 'templatemap_list は成功する') or diag($err);
    is(scalar @$got, 1, 'list は指定テンプレートのマップだけを返す');
    is($got->[0]{template_id}, $t1->id, 'list の template_id は指定したテンプレート');
}

{
    _reset();
    my $idx = _seed_tmpl(name => 'Index', type => 'index');
    my $got = eval { MTMCP::Tools::TemplateMap::list($app, { template_id => $idx->id }) };
    my $err = $@;
    ok(!$got, 'index テンプレートの list は失敗する');
    like($err, qr/アーカイブテンプレートではない/, 'index はアーカイブテンプレートではない');
}

# ------------------------------------------------------------------
# create: individual+Individual OK / individual+Monthly NG / index NG
# ------------------------------------------------------------------

{
    _reset();
    my $tmpl = _seed_tmpl(type => 'individual');
    my $got  = eval { _create_map($tmpl->id, archive_type => 'Individual') };
    my $err  = $@;
    ok($got, 'individual + Individual の create は成功する') or diag($err);
    is($got->{status}, 'created', 'status は created');
    is($got->{archive_type}, 'Individual', 'archive_type は Individual');
    is($got->{is_preferred}, 1, '最初のマップは preferred');
    is($got->{build_type}, 1, 'build_type のデフォルトは 1');
    is($got->{file_template}, '%y/%m/%-f', 'file_template 省略時は archiver の default');
}

{
    _reset();
    my $tmpl = _seed_tmpl(type => 'individual');
    my $got  = eval { _create_map($tmpl->id, archive_type => 'Monthly') };
    my $err  = $@;
    ok(!$got, 'individual + Monthly の create は失敗する');
    like($err, qr/無効なアーカイブタイプ/, 'individual に Monthly は無効');
    is(scalar @MT::TemplateMap::SAVED, 0, '無効な組み合わせは保存しない');
}

{
    _reset();
    my $tmpl = _seed_tmpl(name => 'Index', type => 'index');
    my $got  = eval { _create_map($tmpl->id, archive_type => 'Individual') };
    my $err  = $@;
    ok(!$got, 'index への templatemap_create は失敗する');
    like($err, qr/アーカイブテンプレートではない/, 'index にマップは作れない');
}

# ------------------------------------------------------------------
# 最初のマップは preferred、2件目は 0（明示 prefer しない限り）
# ------------------------------------------------------------------

{
    _reset();
    my $tmpl = _seed_tmpl(type => 'individual');
    my $first  = _create_map($tmpl->id, file_template => '%y/%m/%-f');
    my $second = _create_map($tmpl->id, file_template => '%-c/%-f');
    is($first->{is_preferred},  1, '1件目は is_preferred=1');
    is($second->{is_preferred}, 0, '2件目は is_preferred=0');

    my $third = _create_map($tmpl->id, file_template => 'custom/%-f', is_preferred => 1);
    is($third->{is_preferred}, 1, 'is_preferred 指定のマップは preferred');
    my $map1 = MT::TemplateMap->load($first->{templatemap_id});
    is($map1->is_preferred, 0, 'prefer したマップ以外は preferred が外れる');
}

# ------------------------------------------------------------------
# update: 項目なしはエラー / is_preferred の切替
# ------------------------------------------------------------------

{
    _reset();
    my $tmpl = _seed_tmpl(type => 'individual');
    my $created = _create_map($tmpl->id);
    my $got = eval {
        MTMCP::Tools::TemplateMap::update($app, { templatemap_id => $created->{templatemap_id} });
    };
    my $err = $@;
    ok(!$got, '更新項目なしの update は失敗する');
    like($err, qr/更新する項目がありません/, 'template_update と同様のメッセージ');
}

{
    _reset();
    my $tmpl = _seed_tmpl(type => 'individual');
    my $a = _create_map($tmpl->id, file_template => 'a/%-f');
    my $b = _create_map($tmpl->id, file_template => 'b/%-f');
    my $got = eval {
        MTMCP::Tools::TemplateMap::update($app, {
            templatemap_id => $b->{templatemap_id},
            is_preferred   => 1,
        });
    };
    my $err = $@;
    ok($got, 'is_preferred の update は成功する') or diag($err);
    is(MT::TemplateMap->load($b->{templatemap_id})->is_preferred, 1, '指定したマップが preferred');
    is(MT::TemplateMap->load($a->{templatemap_id})->is_preferred, 0, '他のマップの preferred は外れる');
}

{
    _reset();
    my $tmpl = _seed_tmpl(type => 'individual');
    my $created = _create_map($tmpl->id);
    my $got = eval {
        MTMCP::Tools::TemplateMap::update($app, {
            templatemap_id => $created->{templatemap_id},
            file_template  => 'updated/%-f',
            build_type     => 2,
        });
    };
    my $err = $@;
    ok($got, 'file_template / build_type の update は成功する') or diag($err);
    is($got->{file_template}, 'updated/%-f', 'file_template が更新される');
    is($got->{build_type}, 2, 'build_type が更新される');
    ok(@MT::Blog::FLUSHED, 'update 後に archive type キャッシュを flush する');
}

# ------------------------------------------------------------------
# delete: 残りがあれば preferred に昇格 / 最後なら blog.archive_type から除去
# ------------------------------------------------------------------

{
    _reset();
    my $tmpl = _seed_tmpl(type => 'individual');
    my $a = _create_map($tmpl->id, file_template => 'a/%-f');
    my $b = _create_map($tmpl->id, file_template => 'b/%-f');
    is(MT::TemplateMap->load($a->{templatemap_id})->is_preferred, 1, '削除前は1件目が preferred');

    my $got = eval {
        MTMCP::Tools::TemplateMap::remove($app, { templatemap_id => $a->{templatemap_id}, confirm => 1 });
    };
    my $err = $@;
    ok($got, 'templatemap_delete は成功する') or diag($err);
    is($got->{status}, 'deleted', 'status は deleted');
    is(MT::TemplateMap->load($b->{templatemap_id})->is_preferred, 1, '残ったマップが preferred になる');

    my $blog = MT::Blog->load(1);
    like($blog->archive_type, qr/Individual/, 'まだマップがあるので archive_type は残る');

    my $got2 = eval {
        MTMCP::Tools::TemplateMap::remove($app, { templatemap_id => $b->{templatemap_id}, confirm => 1 });
    };
    ok($got2, '最後のマップの delete も成功する') or diag($@);
    my $blog2 = MT::Blog->load(1);
    is($blog2->archive_type, '', '最後のマップ削除で blog.archive_type から除去される');
}

# ------------------------------------------------------------------
# get / belong check
# ------------------------------------------------------------------

{
    _reset();
    my $tmpl = _seed_tmpl(type => 'individual');
    my $created = _create_map($tmpl->id);
    my $got = eval {
        MTMCP::Tools::TemplateMap::get($app, { templatemap_id => $created->{templatemap_id} });
    };
    my $err = $@;
    ok($got, 'templatemap_get は成功する') or diag($err);
    is($got->{id}, $created->{templatemap_id}, 'get は id を返す');
    is($got->{template_id}, $tmpl->id, 'get は template_id を含む');
}

{
    _reset();
    my $got = eval { MTMCP::Tools::TemplateMap::get($app, { templatemap_id => 999 }) };
    my $err = $@;
    ok(!$got, '存在しない templatemap_id は失敗する');
    like($err, qr/TemplateMap not found: 999/, 'not found メッセージ');
}

# ------------------------------------------------------------------
# template_get は maps を含む / template_list は含まない
# ------------------------------------------------------------------

{
    _reset();
    my $tmpl = _seed_tmpl(name => 'Entry Archive', type => 'individual');
    _create_map($tmpl->id);

    my $got = eval { MTMCP::Tools::Template::get($app, { template_id => $tmpl->id }) };
    my $err = $@;
    ok($got, 'template_get は成功する') or diag($err);
    ok($got->{maps}, 'template_get は maps を含む');
    is(scalar @{ $got->{maps} }, 1, 'maps は1件');
    is($got->{maps}[0]{archive_type}, 'Individual', 'maps の archive_type');

    my $list = eval { MTMCP::Tools::Template::list($app, { blog_id => 1 }) };
    ok($list, 'template_list は成功する') or diag($@);
    ok(!exists $list->[0]{maps}, 'template_list は maps を含まない');
}

# ------------------------------------------------------------------
# template_create + archive_type ショートカット / warning / ct
# ------------------------------------------------------------------

{
    _reset();
    my $got = eval {
        MTMCP::Tools::Template::create($app, {
            blog_id      => 1,
            name         => 'Entry',
            type         => 'individual',
            archive_type => 'Individual',
        });
    };
    my $err = $@;
    ok($got, 'template_create(individual, archive_type=Individual) は成功する') or diag($err);
    ok($got->{templatemap_ids} && @{ $got->{templatemap_ids} }, 'マップ ID が返る');
    is(scalar @{ [ MT::TemplateMap->load({ template_id => $got->{template_id} }) ] }, 1, 'マップが1件作られる');
    ok(!$got->{warning}, 'マップ作成時は warning なし');
}

{
    _reset();
    my $got = eval {
        MTMCP::Tools::Template::create($app, {
            blog_id => 1,
            name    => 'Entry only',
            type    => 'individual',
        });
    };
    my $err = $@;
    ok($got, 'template_create(individual) のみでもテンプレートは保存される') or diag($err);
    like($got->{warning}, qr/templatemap_create/, 'マップなしのアーカイブテンプレートは warning を返す');
    is(scalar @{ [ MT::TemplateMap->load({ template_id => $got->{template_id} }) ] }, 0, 'マップは作られない');
}

{
    _reset();
    my $got = eval {
        MTMCP::Tools::Template::create($app, {
            blog_id => 1,
            name    => 'CT',
            type    => 'ct',
        });
    };
    my $err = $@;
    ok(!$got, 'template_create(type=ct) は content_type_id なしで失敗する');
    like($err, qr/content_type_id/, 'ct は content_type_id が必要');
    is(scalar @MT::Template::SAVED, 0, 'ct で失敗した場合は保存しない');
}

{
    _reset();
    my $got = eval {
        MTMCP::Tools::Template::create($app, {
            blog_id         => 1,
            name            => 'CT',
            type            => 'ct',
            content_type_id => 3,
            archive_type    => 'ContentType',
        });
    };
    my $err = $@;
    ok($got, 'template_create(ct + content_type_id + archive_type) は成功する') or diag($err);
    is(MT::Template->load($got->{template_id})->content_type_id, 3, 'content_type_id が保存される');
}

{
    _reset();
    my $tmpl = _seed_tmpl(type => 'ct_archive', content_type_id => 3);
    my $got  = eval {
        _create_map($tmpl->id, archive_type => 'ContentType-Category');
    };
    my $err = $@;
    ok(!$got, 'ContentType-Category は cat_field_id なしで失敗する');
    like($err, qr/cat_field_id/, 'cat_field_id が必要と伝える');
}

{
    _reset();
    my $tmpl = _seed_tmpl(type => 'ct_archive', content_type_id => 3);
    my $got  = eval {
        _create_map($tmpl->id, archive_type => 'ContentType-Category', cat_field_id => 10);
    };
    my $err = $@;
    ok($got, 'ContentType-Category + cat_field_id は成功する') or diag($err);
}

# ------------------------------------------------------------------
# widgetset + body は従来どおり拒否
# ------------------------------------------------------------------

{
    _reset();
    my $got = eval {
        MTMCP::Tools::Template::create($app, {
            blog_id => 1,
            name    => 'WS',
            type    => 'widgetset',
            body    => '<mt:Include widget="Foo">',
        });
    };
    my $err = $@;
    ok(!$got, 'widgetset + body は拒否される');
    like($err, qr/type が widgetset のときは body を指定できません/, 'widgetset body 拒否メッセージ');
}

{
    _reset();
    my $got = eval {
        MTMCP::Tools::Template::create($app, {
            blog_id => 1,
            name    => 'Index',
            type    => 'index',
        });
    };
    my $err = $@;
    ok(!$got, 'index は outfile なしで失敗する');
    like($err, qr/outfile/, 'outfile 必須は維持される');
}

done_testing;
