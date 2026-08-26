use strict;
use warnings;
use utf8;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../plugins/MTMCP/lib";

use MTMCP::Protocol;
use MTMCP::Tools::Entry;
use MTMCP::Tools::Page;
use MTMCP::Tools::Category;
use MTMCP::Tools::CategorySet;
use MTMCP::Tools::Tag;
use MTMCP::Tools::Folder;
use MTMCP::Tools::Asset;
use MTMCP::Tools::Template;
use MTMCP::Tools::TemplateMap;
use MTMCP::Tools::Widget;
use MTMCP::Tools::User;
use MTMCP::Tools::ContentData;

# 破壊的操作は confirm: true が無ければ実行しない（#64）。
# 対象を1本のテストにまとめてあるのは、ツールが増えたときに
# 「confirm を付け忘れた削除系ツール」を機械的に落とすため。

{
    package FakeUser;
    sub new { my ($c, %a) = @_; bless \%a, $c }
    sub id                      { 1 }
    sub is_superuser            { 1 }
    sub is_anonymous            { 0 }
    sub can_manage_users_groups { 1 }
}
{
    package FakeApp;
    sub new { bless {}, shift }
    sub user { FakeUser->new }
}

my $app = FakeApp->new;

# ツール名 => [ 実装, confirm 以外の必須引数 ]
my @TOOLS = (
    [ 'entry_delete'        => \&MTMCP::Tools::Entry::remove,       { entry_id        => 1 } ],
    [ 'page_delete'         => \&MTMCP::Tools::Page::remove,        { page_id         => 1 } ],
    [ 'category_delete'     => \&MTMCP::Tools::Category::remove,    { category_id     => 1 } ],
    [ 'category_set_delete' => \&MTMCP::Tools::CategorySet::remove, { category_set_id => 1 } ],
    [ 'tag_delete'          => \&MTMCP::Tools::Tag::remove,         { blog_id => 1, tag_id => 1 } ],
    [ 'folder_delete'       => \&MTMCP::Tools::Folder::remove,      { folder_id       => 1 } ],
    [ 'asset_delete'        => \&MTMCP::Tools::Asset::remove,       { asset_id        => 1 } ],
    [ 'template_delete'     => \&MTMCP::Tools::Template::remove,    { template_id     => 1 } ],
    [ 'templatemap_delete'  => \&MTMCP::Tools::TemplateMap::remove, { templatemap_id  => 1 } ],
    [ 'widgetset_delete'    => \&MTMCP::Tools::Widget::remove,      { widgetset_id    => 1 } ],
    [ 'user_delete'         => \&MTMCP::Tools::User::remove,        { user_id         => 1 } ],
    [ 'content_data_delete' => \&MTMCP::Tools::ContentData::remove, { content_data_id => 1 } ],
);

subtest 'confirm が無ければ die する' => sub {
    for my $t (@TOOLS) {
        my ($name, $code, $args) = @$t;
        eval { $code->($app, { %$args }) };
        like($@, qr/confirm: true/, "$name: confirm 省略で die");
    }
};

subtest '偽値の confirm も拒否する' => sub {
    for my $falsy (0, '0', '', 'false', 'FALSE') {
        my ($name, $code, $args) = @{ $TOOLS[0] };
        eval { $code->($app, { %$args, confirm => $falsy }) };
        like($@, qr/confirm: true/, "entry_delete: confirm => '$falsy' で die");
    }
};

subtest 'confirm があれば confirm では止まらない' => sub {
    # 対象が存在しないので別の理由で die するが、confirm のせいではないこと。
    for my $t (@TOOLS) {
        my ($name, $code, $args) = @$t;
        eval { $code->($app, { %$args, confirm => 1 }) };
        unlike($@, qr/confirm: true/, "$name: confirm => 1 なら confirm では止まらない");
    }
};

subtest 'inputSchema が confirm を必須にしている' => sub {
    my $defs = MTMCP::Protocol::_tool_definitions();
    my %by_name = map { $_->{name} => $_ } @$defs;

    for my $t (@TOOLS) {
        my $name = $t->[0];
        my $def  = $by_name{$name} or do {
            fail("$name: ツール定義が見つからない");
            next;
        };
        my $schema = $def->{inputSchema};
        ok((grep { $_ eq 'confirm' } @{ $schema->{required} // [] }),
            "$name: required に confirm がある");
        is($schema->{properties}{confirm}{type}, 'boolean',
            "$name: confirm は boolean");
    }
};

# 将来 *_delete を足したときに confirm を付け忘れないための網。
subtest '_delete で終わるツールはすべて confirm 必須' => sub {
    my $defs = MTMCP::Protocol::_tool_definitions();
    my @missing;
    for my $def (@$defs) {
        next unless $def->{name} =~ /_delete\z/;
        my $req = $def->{inputSchema}{required} // [];
        push @missing, $def->{name} unless grep { $_ eq 'confirm' } @$req;
    }
    is_deeply(\@missing, [], 'confirm が required に無い削除系ツールは無い')
        or diag("confirm 未設定: @missing");
};

done_testing;
