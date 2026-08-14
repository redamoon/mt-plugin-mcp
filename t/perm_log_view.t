use strict;
use warnings;
use utf8;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../plugins/MTMCP/lib";

use MT::Permission;
use MTMCP::Perm;

{
    package FakeUser;
    sub new {
        my ($class, %args) = @_;
        bless \%args, $class;
    }
    sub id            { $_[0]{id} }
    sub is_superuser  { $_[0]{is_superuser} }
}
{
    package FakeApp;
    sub new {
        my ($class, $user) = @_;
        bless { user => $user }, $class;
    }
    sub user { $_[0]{user} }
}

sub _app {
    my (%user) = @_;
    return FakeApp->new(FakeUser->new(%user));
}

{
    my $got = eval { MTMCP::Perm::require_log_view(FakeApp->new(undef), 0) };
    my $err = $@;
    ok(!$got && $err, '未認証は die');
    like($err, qr/認証/, '未認証メッセージ');
}

{
    MT::Permission::reset();
    my $ret = eval { MTMCP::Perm::require_log_view(_app(id => 1, is_superuser => 1), 0) };
    my $err = $@;
    ok(!$err, 'superuser は blog_id=0 でも OK') or diag($err);
    ok(!defined $ret, 'superuser は追加の blog_id 制限なし');
}

{
    MT::Permission::reset();
    my $got = eval { MTMCP::Perm::require_log_view(_app(id => 2, is_superuser => 0), 0) };
    my $err = $@;
    ok(!$got, '権限なしはシステムログを拒否');
    like($err, qr/権限/, '権限なし die');
}

{
    MT::Permission::reset();
    MT::Permission->add(
        author_id   => 3,
        blog_id     => 0,
        permissions => { view_log => 1 },
    );
    my $ret = eval { MTMCP::Perm::require_log_view(_app(id => 3), 0) };
    my $err = $@;
    ok(!$err, 'view_log があれば blog_id=0 は OK') or diag($err);
    ok(!defined $ret, 'view_log は追加制限なし');

    my $site = eval { MTMCP::Perm::require_log_view(_app(id => 3), 9) };
    ok(!$@, 'view_log は任意サイトの閲覧も OK') or diag($@);
}

{
    MT::Permission::reset();
    MT::Permission->add(
        author_id   => 4,
        blog_id     => 7,
        permissions => { view_blog_log => 1 },
    );
    my $ok = eval { MTMCP::Perm::require_log_view(_app(id => 4), 7) };
    ok(!$@, 'サイトは view_blog_log で OK') or diag($@);

    my $other = eval { MTMCP::Perm::require_log_view(_app(id => 4), 8) };
    my $err = $@;
    ok(!$other, '他サイトは拒否');
    like($err, qr/blog_id: 8/, '他サイトの権限エラー');

    my $sys = eval { MTMCP::Perm::require_log_view(_app(id => 4), 0) };
    my $sys_err = $@;
    ok(!$sys_err, 'view_blog_log のみでもシステム全体要求は die せず scoped になる') or diag($sys_err);
    is_deeply($sys, [7], '許可 blog_id のリストを返す');
}

{
    MT::Permission::reset();
    MT::Permission->add(
        author_id   => 5,
        blog_id     => 1,
        permissions => { view_blog_log => 1 },
    );
    MT::Permission->add(
        author_id   => 5,
        blog_id     => 2,
        permissions => { view_blog_log => 1 },
    );
    my $sys = MTMCP::Perm::require_log_view(_app(id => 5), undef);
    is_deeply([ sort { $a <=> $b } @$sys ], [ 1, 2 ], '複数サイトの view_blog_log を列挙');
}

done_testing();
