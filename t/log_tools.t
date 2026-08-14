use strict;
use warnings;
use utf8;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../plugins/MTMCP/lib";

use MT::Log;
use MTMCP::Tools::Log;

our $LAST_VIEW_BLOG_ID;
our $VIEW_RETURN;

{
    no warnings 'redefine';
    *MTMCP::Perm::require_log_view = sub {
        my ($app, $blog_id) = @_;
        $LAST_VIEW_BLOG_ID = $blog_id;
        return $VIEW_RETURN;
    };
}

my $app = bless {}, 'FakeApp';

sub _seed {
    my (%args) = @_;
    my $log = MT::Log->new;
    $log->id($args{id}) if defined $args{id};
    $log->blog_id($args{blog_id} // 0);
    $log->level($args{level} // MT::Log::INFO());
    $log->class($args{class} // 'system');
    $log->category($args{category});
    $log->message($args{message} // 'msg');
    $log->ip($args{ip});
    $log->author_id($args{author_id});
    $log->created_on($args{created_on} // '20260101120000');
    $log->metadata($args{metadata});
    $log->save;
    return $log;
}

sub _list {
    my ($args) = @_;
    $LAST_VIEW_BLOG_ID = 'UNSET';
    $VIEW_RETURN       = undef;
    return MTMCP::Tools::Log::list($app, $args // {});
}

# ------------------------------------------------------------------
# class 未指定は class => '*' で system 以外も返す
# ------------------------------------------------------------------

{
    MT::Log::reset();
    _seed(id => 1, class => 'system', message => 'sys');
    _seed(id => 2, class => 'entry',  message => 'ent');
    _seed(id => 3, class => 'plugin', message => 'plug');
    my $got = _list();
    is($got->{total}, 3, 'class 未指定の total は全クラス');
    my @classes = sort map { $_->{class} } @{ $got->{items} };
    is_deeply(\@classes, [qw(entry plugin system)], 'system 以外も返る');
    is($MT::Log::LAST_LOAD_TERMS->{class}, '*', 'load に class => * を渡す');
    is($MT::Log::LAST_COUNT_TERMS->{class}, '*', 'count にも class => * を渡す');
}

{
    MT::Log::reset();
    _seed(id => 1, class => 'system');
    _seed(id => 2, class => 'entry');
    my $got = _list({ class => 'entry' });
    is($got->{total}, 1, 'class=entry は 1 件');
    is($got->{items}[0]{class}, 'entry', 'entry クラスのみ');
}

# ------------------------------------------------------------------
# level
# ------------------------------------------------------------------

{
    MT::Log::reset();
    _seed(id => 1, level => MT::Log::DEBUG(),    message => 'd');
    _seed(id => 2, level => MT::Log::INFO(),     message => 'i');
    _seed(id => 3, level => MT::Log::NOTICE(),   message => 'n');
    _seed(id => 4, level => MT::Log::WARNING(),  message => 'w');
    _seed(id => 5, level => MT::Log::ERROR(),    message => 'e');
    _seed(id => 6, level => MT::Log::SECURITY(), message => 's');

    my $err = _list({ level => 'error' });
    is($err->{total}, 1, 'level=error は ERROR(4) のみ');
    is($err->{items}[0]{level}, 'error', '返却 level は error 文字列');
    is($err->{items}[0]{message}, 'e', 'ERROR のメッセージ');
    is($MT::Log::LAST_LOAD_TERMS->{level}, MT::Log::ERROR(), 'terms.level は 4');

    my $notice = _list({ level => 'notice' });
    is($notice->{total}, 1, 'level=notice は NOTICE(2) のみ');
    is($notice->{items}[0]{level}, 'notice', 'notice は warning に化けない');
    is($notice->{items}[0]{message}, 'n', 'NOTICE のメッセージ');
    is($MT::Log::LAST_LOAD_TERMS->{level}, MT::Log::NOTICE(), 'terms.level は 2 であり WARNING(3) ではない');
    isnt($MT::Log::LAST_LOAD_TERMS->{level}, MT::Log::WARNING(), 'notice を warning ビットマスクにしない');
}

{
    MT::Log::reset();
    my $got = eval { _list({ level => 'not-a-level' }) };
    my $err = $@;
    ok(!$got, '未知 level は成功しない');
    like($err, qr/Unknown log level: not-a-level/, '未知 level は die する');
}

# ------------------------------------------------------------------
# date_from / date_to
# ------------------------------------------------------------------

{
    MT::Log::reset();
    _seed(id => 1, created_on => '20251231000000', message => 'before');
    _seed(id => 2, created_on => '20260101120000', message => 'in');
    _seed(id => 3, created_on => '20260102235959', message => 'end');
    _seed(id => 4, created_on => '20260103000000', message => 'after');
    my $got = _list({ date_from => '2026-01-01', date_to => '2026-01-02' });
    is($got->{total}, 2, '期間内の 2 件');
    my @msgs = sort map { $_->{message} } @{ $got->{items} };
    is_deeply(\@msgs, [qw(end in)], 'date range に入るログだけ');
    is_deeply(
        $MT::Log::LAST_LOAD_TERMS->{created_on},
        [ '20260101000000', '20260102235959' ],
        'date_from/to は created_on range YYYYMMDD000000 .. YYYYMMDD235959'
    );
    ok($MT::Log::LAST_LOAD_ARGS->{range_incl}{created_on}, 'range_incl created_on');
    ok($MT::Log::LAST_COUNT_ARGS->{range_incl}{created_on}, 'count にも range_incl');
}

# ------------------------------------------------------------------
# keyword: message / ip
# ------------------------------------------------------------------

{
    MT::Log::reset();
    _seed(id => 1, message => 'publish failed', ip => '10.0.0.1');
    _seed(id => 2, message => 'ok',             ip => '192.168.1.9');
    _seed(id => 3, message => 'other',          ip => '10.0.0.2');

    my $by_msg = _list({ keyword => 'publish' });
    is($by_msg->{total}, 1, 'keyword は message にマッチ');
    is($by_msg->{items}[0]{id}, 1, 'message ヒット');

    my $by_ip = _list({ keyword => '192.168.1' });
    is($by_ip->{total}, 1, 'keyword は ip にマッチ');
    is($by_ip->{items}[0]{id}, 2, 'ip ヒット');

    my $or_terms = $MT::Log::LAST_LOAD_TERMS->{'-or'};
    ok($or_terms, 'keyword は -or で message/ip を LIKE');
    like($or_terms->[0]{message}{like}, qr/192/, 'LIKE パターンに keyword');
}

{
    MT::Log::reset();
    _seed(id => 1, message => '100% done');
    my $got = _list({ keyword => '100%' });
    is($got->{total}, 1, 'LIKE の % をエスケープしても元メッセージにマッチ');
    like($MT::Log::LAST_LOAD_TERMS->{'-or'}[0]{message}{like}, qr/\\%/, 'keyword の % をエスケープ');
}

# ------------------------------------------------------------------
# log_get metadata / list は省略
# ------------------------------------------------------------------

{
    MT::Log::reset();
    _seed(
        id       => 7,
        message  => 'x' x 600,
        metadata => 'raw-meta-42',
        class    => 'entry',
    );
    my $list = _list();
    ok(!exists $list->{items}[0]{metadata}, 'list は metadata を含めない');
    is(length($list->{items}[0]{message}), 500, 'list の message は 500 文字で切る');
    ok($list->{items}[0]{truncated}, 'list は truncated フラグ');

    my $one = MTMCP::Tools::Log::get($app, { log_id => 7 });
    is($one->{metadata}, 'raw-meta-42', 'log_get は metadata 生文字列');
    is(length($one->{message}), 600, 'log_get は message を切らない');
    ok(!exists $one->{truncated}, 'log_get に truncated は不要');
    ok(!exists $one->{description}, 'HTML description は返さない');
    is($MT::Log::LAST_LOAD_TERMS->{class}, '*', 'log_get は class 制約を外す');
}

{
    MT::Log::reset();
    my $got = eval { MTMCP::Tools::Log::get($app, { log_id => 99 }) };
    my $err = $@;
    ok(!$got, '無い ID は失敗');
    like($err, qr/Log not found: 99/, 'Log not found: N');
}

# ------------------------------------------------------------------
# blog_id 省略と 0 はシステム扱い
# ------------------------------------------------------------------

{
    MT::Log::reset();
    _seed(id => 1, blog_id => 0, message => 'sys');
    _seed(id => 2, blog_id => 3, message => 'site');

    my $omit = _list({});
    ok(!exists $MT::Log::LAST_LOAD_TERMS->{blog_id}, '省略時は blog_id で絞らない');
    is($LAST_VIEW_BLOG_ID, undef, '省略時 require_log_view に undef');
    is($omit->{total}, 2, '権限無制限なら全サイト');

    my $zero = _list({ blog_id => 0 });
    ok(!exists $MT::Log::LAST_LOAD_TERMS->{blog_id}, 'blog_id=0 もシステム全体');
    ok(!$LAST_VIEW_BLOG_ID, 'blog_id=0 は require_log_view に偽');

    my $site = _list({ blog_id => 3 });
    is($MT::Log::LAST_LOAD_TERMS->{blog_id}, 3, 'サイト指定は blog_id のみ（子ブログを含めない）');
    is($LAST_VIEW_BLOG_ID, 3, 'サイト指定は require_log_view(3)');
    is($site->{total}, 1, '指定サイトのみ');
}

{
    MT::Log::reset();
    _seed(id => 1, blog_id => 1);
    _seed(id => 2, blog_id => 2);
    _seed(id => 3, blog_id => 9);
    $VIEW_RETURN = [ 1, 2 ];
    $LAST_VIEW_BLOG_ID = 'UNSET';
    my $got = MTMCP::Tools::Log::list($app, {});
    is_deeply($MT::Log::LAST_LOAD_TERMS->{blog_id}, [ 1, 2 ], 'scoped なシステム全体は許可 blog_id に限定');
    is($got->{total}, 2, '許可サイトのログだけ');
}

{
    MT::Log::reset();
    _seed(id => 1, blog_id => 0, metadata => 'sys-meta');
    _seed(id => 2, blog_id => 5, metadata => 'site-meta');
    $VIEW_RETURN = [ 5 ];
    my $ok = eval { MTMCP::Tools::Log::get($app, { log_id => 2 }) };
    ok($ok, 'scoped ユーザーは許可サイトの log_get ができる') or diag($@);
    my $denied = eval { MTMCP::Tools::Log::get($app, { log_id => 1 }) };
    my $err = $@;
    ok(!$denied, 'scoped ユーザーはシステムログ get ができない');
    like($err, qr/権限/, 'システムログ get は権限エラー');
}

# ------------------------------------------------------------------
# sort created_on descend
# ------------------------------------------------------------------

{
    MT::Log::reset();
    _seed(id => 1, created_on => '20260101000000');
    _seed(id => 2, created_on => '20260103000000');
    _seed(id => 3, created_on => '20260102000000');
    my $got = _list({ limit => 2 });
    is($got->{items}[0]{id}, 2, '新しい順');
    is($got->{items}[1]{id}, 3, '2番目も新しい順');
    is($MT::Log::LAST_LOAD_ARGS->{sort}, 'created_on', 'sort created_on');
    is($MT::Log::LAST_LOAD_ARGS->{direction}, 'descend', 'direction descend');
}

done_testing();
