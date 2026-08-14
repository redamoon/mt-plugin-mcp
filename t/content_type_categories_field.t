use strict;
use warnings;
use utf8;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../plugins/MTMCP/lib";

use MT;
use MT::ContentType;
use MT::ContentField;
use MTMCP::Perm;
use MTMCP::Tools::ContentType;

{
    no warnings 'redefine';
    *MTMCP::Perm::require_blog_access     = sub { 1 };
    *MTMCP::Perm::require_blog_permission = sub { 1 };
}

my $app = bless {}, 'FakeApp';

sub _reset {
    MT::ContentType::reset();
    MT::ContentField::reset();
}

{
    _reset();
    my $got = eval {
        MTMCP::Tools::ContentType::create($app, {
            blog_id => 1,
            name    => 'News',
            fields  => [
                { type => 'categories', label => 'ジャンル' },
            ],
        });
    };
    ok(!$got, 'type=categories で category_set_id なしはエラー');
    like($@, qr/category_set_id is required/, '必須エラー');
}

{
    _reset();
    my $got = eval {
        MTMCP::Tools::ContentType::create($app, {
            blog_id => 1,
            name    => 'News',
            fields  => [
                {
                    type            => 'categories',
                    label           => 'ジャンル',
                    category_set_id => 7,
                },
            ],
        });
    };
    ok($got, 'category_set_id 付きなら作成できる') or diag($@);
    is($got->{status}, 'created', 'status は created');
    my ($cf) = MT::ContentField->load({ content_type_id => $got->{content_type_id} });
    ok($cf, 'ContentField が保存される');
    is($cf->related_cat_set_id, 7, 'related_cat_set_id がセットされる');
    is($cf->type, 'categories', 'type は categories');

    my $full = eval {
        MTMCP::Tools::ContentType::get($app, { content_type_id => $got->{content_type_id} });
    };
    ok($full, 'content_type_get は成功する') or diag($@);
    my ($field) = grep { $_->{type} eq 'categories' } @{ $full->{fields} };
    ok($field, 'categories フィールドがある');
    is($field->{category_set_id}, 7, 'get は category_set_id を返す');
}

{
    _reset();
    my $got = eval {
        MTMCP::Tools::ContentType::create($app, {
            blog_id => 1,
            name    => 'Alt',
            fields  => [
                {
                    type               => 'categories',
                    label              => 'Cats',
                    related_cat_set_id => 9,
                },
            ],
        });
    };
    ok($got, 'related_cat_set_id でも作成できる') or diag($@);
    my ($cf) = MT::ContentField->load({ content_type_id => $got->{content_type_id} });
    is($cf->related_cat_set_id, 9, 'related_cat_set_id エイリアス');
}

done_testing;
