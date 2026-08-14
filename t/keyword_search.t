use strict;
use warnings;
use utf8;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../plugins/MTMCP/lib";

use MT::ContentData;
use MT::ContentFieldIndex;
use MTMCP::Tools::Entry;
use MTMCP::Tools::Asset;
use MTMCP::Tools::Template;
use MTMCP::Tools::ContentData;

{
    no warnings 'redefine';
    *MTMCP::Perm::require_blog_permission = sub { 1 };
    *MTMCP::Perm::require_blog_access     = sub { 1 };
}

my $app = bless {}, 'FakeApp';

sub _walk {
    my ($node, $cb) = @_;
    return unless defined $node;
    $cb->($node);
    if (ref $node eq 'ARRAY') {
        _walk($_, $cb) for @$node;
    }
    elsif (ref $node eq 'HASH') {
        _walk($_, $cb) for values %$node;
    }
}

sub _like_values {
    my ($terms) = @_;
    my @likes;
    _walk(
        $terms,
        sub {
            my $n = shift;
            return unless ref $n eq 'HASH' && exists $n->{like};
            push @likes, $n->{like};
        }
    );
    return @likes;
}

sub _has_like_on {
    my ($terms, $col) = @_;
    my $found = 0;
    _walk(
        $terms,
        sub {
            my $n = shift;
            return unless ref $n eq 'HASH' && exists $n->{$col};
            my $v = $n->{$col};
            $found = 1 if ref $v eq 'HASH' && exists $v->{like};
        }
    );
    return $found;
}

sub _base_hash {
    my ($terms) = @_;
    return $terms if ref $terms eq 'HASH';
    if (ref $terms eq 'ARRAY') {
        my ($h) = grep { ref $_ eq 'HASH' } @$terms;
        return $h;
    }
    return {};
}

# ------------------------------------------------------------------
# entry_list: keyword なし
# ------------------------------------------------------------------
{
    MT::Entry::reset();
    my $got = eval {
        MTMCP::Tools::Entry::list($app, { blog_id => 1, limit => 5, offset => 3 });
    };
    ok($got, 'entry_list(keyword なし) は成功する') or diag($@);
    my $terms = $MT::Entry::LAST_LOAD_TERMS;
    my $args  = $MT::Entry::LAST_LOAD_ARGS;
    is(ref $terms, 'HASH', 'keyword なしの terms は HASH');
    ok(!_has_like_on($terms, 'title'), 'keyword なしでは LIKE が付かない');
    is($args->{limit},  5, 'keyword なしでも limit が load args に渡る');
    is($args->{offset}, 3, 'keyword なしでも offset が load args に渡る');
    isnt($args->{limit}, 2000, '2000 スキャン上限は使わない');
}

# ------------------------------------------------------------------
# entry_list: keyword あり
# ------------------------------------------------------------------
{
    MT::Entry::reset();
    my $got = eval {
        MTMCP::Tools::Entry::list($app, {
            blog_id => 1,
            status  => 'publish',
            keyword => 'hello',
            limit   => 7,
            offset  => 2,
        });
    };
    ok($got, 'entry_list(keyword あり) は成功する') or diag($@);
    my $terms = $MT::Entry::LAST_LOAD_TERMS;
    my $args  = $MT::Entry::LAST_LOAD_ARGS;
    is(ref $terms, 'ARRAY', 'keyword ありの terms は nested ARRAY');
    is($terms->[1], '-and', 'status/blog_id と LIKE は AND');
    my $base = _base_hash($terms);
    is($base->{blog_id}, 1, 'blog_id は AND 側');
    is($base->{status}, MT::Entry::RELEASE(), 'publish は RELEASE');
    isnt($base->{status}, MT::Entry::HOLD(), 'publish 検索の terms に HOLD は出ない');
    ok(_has_like_on($terms, 'title'), 'title に LIKE');
    ok(_has_like_on($terms, 'text'),  'text に LIKE');
    my $or = $terms->[2];
    ok(ref $or eq 'ARRAY' && grep { $_ eq '-or' } @$or, 'title と text は OR');
    is($args->{limit},  7, 'keyword 時もユーザ limit が残る');
    is($args->{offset}, 2, 'keyword 時も offset が残る');
    isnt($args->{limit}, 2000, 'keyword 時に 2000 スキャン上限は付かない');
}

{
    MT::Entry::reset();
    eval {
        MTMCP::Tools::Entry::list($app, { blog_id => 1, keyword => '%' });
    };
    my @likes = _like_values($MT::Entry::LAST_LOAD_TERMS);
    ok(@likes, 'keyword=% でも LIKE がある');
    for my $like (@likes) {
        like($like, qr/\\%/, 'keyword=% は \\% にエスケープされる');
        isnt($like, '%', '裸の % パターンにならない');
    }
}

# ------------------------------------------------------------------
# asset_list
# ------------------------------------------------------------------
{
    MT::Asset::reset();
    eval {
        MTMCP::Tools::Asset::list($app, {
            blog_id => 1,
            class   => 'image',
            keyword => 'logo',
            limit   => 4,
        });
    };
    my $terms = $MT::Asset::LAST_LOAD_TERMS;
    my $args  = $MT::Asset::LAST_LOAD_ARGS;
    my $base  = _base_hash($terms);
    is($base->{class}, 'image', 'asset class フィルタは残る');
    is($base->{blog_id}, 1, 'asset blog_id は AND');
    ok(_has_like_on($terms, 'label'),     'asset は label LIKE');
    ok(_has_like_on($terms, 'file_name'), 'asset は file_name LIKE');
    is($args->{limit}, 4, 'asset のユーザ limit が残る');
    isnt($args->{limit}, 2000, 'asset に 2000 は付かない');
}

{
    MT::Asset::reset();
    eval { MTMCP::Tools::Asset::list($app, { blog_id => 1, limit => 9, offset => 1 }) };
    my $terms = $MT::Asset::LAST_LOAD_TERMS;
    is(ref $terms, 'HASH', 'asset keyword なしは HASH');
    ok(!_has_like_on($terms, 'label'), 'asset keyword なしは LIKE なし');
    is($MT::Asset::LAST_LOAD_ARGS->{limit},  9, 'asset keyword なしの limit');
    is($MT::Asset::LAST_LOAD_ARGS->{offset}, 1, 'asset keyword なしの offset');
}

# ------------------------------------------------------------------
# template_list
# ------------------------------------------------------------------
{
    MT::Template::reset();
    eval {
        MTMCP::Tools::Template::list($app, {
            blog_id => 1,
            type    => 'index',
            keyword => 'Main',
            limit   => 3,
            offset  => 1,
        });
    };
    my $terms = $MT::Template::LAST_LOAD_TERMS;
    my $args  = $MT::Template::LAST_LOAD_ARGS;
    my $base  = _base_hash($terms);
    is($base->{type}, 'index', 'template type フィルタは残る');
    ok(_has_like_on($terms, 'name'), 'template は name LIKE');
    ok(!_has_like_on($terms, 'text'), 'template は本文を LIKE しない');
    is($args->{limit},  3, 'template の limit は DB load args');
    is($args->{offset}, 1, 'template の offset は DB load args');
}

{
    MT::Template::reset();
    eval { MTMCP::Tools::Template::list($app, { blog_id => 1, type => 'widgetset' }) };
    my $terms = $MT::Template::LAST_LOAD_TERMS;
    is(ref $terms, 'HASH', 'template keyword なしは HASH');
    is($terms->{type}, 'widgetset', 'type は残る');
    ok(!_has_like_on($terms, 'name'), 'template keyword なしは LIKE なし');
}

# ------------------------------------------------------------------
# content_data_list
# ------------------------------------------------------------------
{
    MT::ContentData::reset();
    eval {
        MTMCP::Tools::ContentData::list($app, {
            content_type_id => 10,
            blog_id         => 1,
            status          => 'publish',
            keyword         => 'fieldval',
            limit           => 6,
            offset          => 0,
        });
    };
    my $err = $@;
    ok(!$err, 'content_data_list(keyword) は成功する') or diag($err);
    my $terms = $MT::ContentData::LAST_LOAD_TERMS;
    my $args  = $MT::ContentData::LAST_LOAD_ARGS;
    my $base  = _base_hash($terms);
    is($base->{content_type_id}, 10, 'content_type_id は AND');
    is($base->{blog_id}, 1, 'blog_id は AND');
    is($base->{status}, MTMCP::Tools::ContentData::RELEASE(), 'publish status は AND');
    ok(_has_like_on($terms, 'label'),          'content_data は label LIKE');
    ok(_has_like_on($terms, 'value_varchar'),  'content_data は value_varchar LIKE');
    ok(_has_like_on($terms, 'value_text'),     'content_data は value_text LIKE');
    ok(!_has_like_on($terms, 'data'),          'data blob には LIKE しない');
    ok($args->{join}, 'ContentFieldIndex を join する');
    my $join = $args->{join};
    is($join->[0], 'MT::ContentFieldIndex', 'join 先は ContentFieldIndex');
    is($join->[1], 'content_data_id', 'join キーは content_data_id');
    is($join->[3]{unique}, 1, 'join unique => 1');
    my $join_terms = $join->[2];
    ok(_has_like_on($join_terms, 'value_varchar'), 'join terms に varchar LIKE');
    ok(_has_like_on($join_terms, 'value_text'),    'join terms に text LIKE');
    ok(ref $join_terms eq 'ARRAY' && grep { $_ eq '-or' } @$join_terms,
        'varchar と text は OR');
    is($args->{limit}, 6, 'content_data のユーザ limit が残る');
    isnt($args->{limit}, 2000, 'content_data に 2000 は付かない');
}

{
    MT::ContentData::reset();
    eval {
        MTMCP::Tools::ContentData::list($app, {
            content_type_id => 10,
            blog_id         => 1,
            limit           => 8,
            offset          => 4,
        });
    };
    my $terms = $MT::ContentData::LAST_LOAD_TERMS;
    is(ref $terms, 'HASH', 'content_data keyword なしは HASH');
    ok(!_has_like_on($terms, 'label'), 'keyword なしは LIKE なし');
    ok(!$MT::ContentData::LAST_LOAD_ARGS->{join}, 'keyword なしは join しない');
    is($MT::ContentData::LAST_LOAD_ARGS->{limit},  8, 'content_data keyword なしの limit');
    is($MT::ContentData::LAST_LOAD_ARGS->{offset}, 4, 'content_data keyword なしの offset');
}

done_testing;
