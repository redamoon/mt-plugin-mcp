use strict;
use warnings;
use utf8;
use Test::More;
use JSON;
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../plugins/MTMCP/lib";

use MTMCP::Args;

# --- is_true: 真 ---
ok(MTMCP::Args::is_true(1),             '数値 1 は真');
ok(MTMCP::Args::is_true('1'),           '文字列 "1" は真');
ok(MTMCP::Args::is_true(JSON::true()),  'JSON::true は真');
ok(MTMCP::Args::is_true('yes'),         '文字列 "yes" は真');
ok(MTMCP::Args::is_true('true'),        '文字列 "true" は真');
ok(MTMCP::Args::is_true(-1),            '負の数も真');

# --- is_true: 偽 ---
ok(!MTMCP::Args::is_true(undef),          'undef は偽');
ok(!MTMCP::Args::is_true(0),              '数値 0 は偽');
ok(!MTMCP::Args::is_true('0'),            '文字列 "0" は偽');
ok(!MTMCP::Args::is_true(''),             '空文字は偽');
ok(!MTMCP::Args::is_true('false'),        '文字列 "false" は偽');
ok(!MTMCP::Args::is_true('FALSE'),        '大文字 "FALSE" も偽');
ok(!MTMCP::Args::is_true('False'),        '混在 "False" も偽');
ok(!MTMCP::Args::is_true(JSON::false()),  'JSON::false は偽');

# 戻り値は 0/1 に正規化される
is(MTMCP::Args::is_true('yes'), 1, '真は 1 を返す');
is(MTMCP::Args::is_true('no'),  1, '"no" は文字列として真（"false" だけを特別扱いする）');
is(MTMCP::Args::is_true(undef), 0, '偽は 0 を返す');

# --- require_confirm: 通る ---
for my $v (1, '1', JSON::true(), 'yes') {
    my $ok = eval { MTMCP::Args::require_confirm({ confirm => $v }, 'テスト操作'); 1 };
    ok($ok, "confirm=" . (ref $v ? 'JSON::true' : $v) . " は無言で通る");
}
is(MTMCP::Args::require_confirm({ confirm => 1 }, 'テスト操作'), 1, '通ったときは 1 を返す');

# --- require_confirm: die ---
for my $case (
    [ 'confirm なし',    {} ],
    [ 'confirm => 0',    { confirm => 0 } ],
    [ 'confirm => "0"',  { confirm => '0' } ],
    [ 'confirm => ""',   { confirm => '' } ],
    [ 'confirm => undef',{ confirm => undef } ],
    [ 'confirm => "false"', { confirm => 'false' } ],
    [ 'confirm => JSON::false', { confirm => JSON::false() } ],
) {
    my ($name, $args) = @$case;
    eval { MTMCP::Args::require_confirm($args, 'テスト操作') };
    like($@, qr/confirm: true/, "$name は die する");
}

{
    eval { MTMCP::Args::require_confirm({}, '記事を一括作成する破壊的操作です') };
    like($@, qr/\Aconfirm: true が必要です（記事を一括作成する破壊的操作です）\n\z/,
        'label がメッセージに差し込まれる');
}

{
    eval { MTMCP::Args::require_confirm(undef, 'テスト操作') };
    like($@, qr/confirm: true/, '$args が undef でも die する（落ちない）');
}

done_testing;
