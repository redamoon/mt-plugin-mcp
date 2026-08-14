use strict;
use warnings;
use utf8;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../plugins/MTMCP/lib";

use MTMCP::Search;

is(MTMCP::Search::escape_like('%'),   '\\%',   '% をエスケープする');
is(MTMCP::Search::escape_like('_'),   '\\_',   '_ をエスケープする');
is(MTMCP::Search::escape_like('\\'),  '\\\\',  '\\ をエスケープする');
is(MTMCP::Search::escape_like('a%b_c\\d'), 'a\\%b\\_c\\\\d', '混在してもすべてエスケープする');
is(MTMCP::Search::escape_like('hello'), 'hello', '通常文字はそのまま');

is(MTMCP::Search::like_pattern('foo'), '%foo%', 'like_pattern は前後に % を付ける');
is(MTMCP::Search::like_pattern('%'),   '%\\%%', 'keyword=% は \\% になり裸の % にならない');
is(MTMCP::Search::like_pattern('_'),   '%\\_%', 'keyword=_ は \\_ になる');

{
    my $terms = MTMCP::Search::and_like_or({ blog_id => 1 }, '', 'title', 'text');
    is(ref $terms, 'HASH', '空文字 keyword は LIKE を付けない');
    ok(!exists $terms->{title}, '空文字では title LIKE が無い');
}

{
    my $terms = MTMCP::Search::and_like_or({ blog_id => 1 }, "  \t", 'title');
    is(ref $terms, 'HASH', '空白のみ keyword は未指定と同じ');
}

{
    my $terms = MTMCP::Search::and_like_or({ blog_id => 1 }, undef, 'title');
    is(ref $terms, 'HASH', 'undef keyword は未指定と同じ');
}

{
    my $terms = MTMCP::Search::and_like_or(
        { blog_id => 1, status => 2 },
        'hello',
        'title', 'text',
    );
    is(ref $terms, 'ARRAY', 'keyword ありは nested terms');
    is($terms->[1], '-and', 'base と LIKE は AND');
    is($terms->[0]{blog_id}, 1, 'blog_id は base 側');
    is($terms->[0]{status},  2, 'status は base 側');
    my $or = $terms->[2];
    is(ref $or, 'ARRAY', 'LIKE は OR 配列');
    is($or->[1], '-or', 'title と text は OR');
    is($or->[0]{title}{like}, '%hello%', 'title LIKE');
    is($or->[2]{text}{like},  '%hello%', 'text LIKE');
    ok(!exists $or->[0]{status}, 'status は OR 側に入らない');
}

done_testing;
