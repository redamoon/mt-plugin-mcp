use strict;
use warnings;
use utf8;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../plugins/MTMCP/lib";

use MT::Author;
use MT::Lockout;
use MT::Auth;
use MT::CMS::Tools;
use MTMCP::Perm;
use MTMCP::Tools::User;

{
    package FakeUser;
    sub new {
        my ($class, %args) = @_;
        bless \%args, $class;
    }
    sub id                       { $_[0]{id} }
    sub is_superuser             { $_[0]{is_superuser} }
    sub can_manage_users_groups  {
        return 1 if $_[0]{is_superuser};
        return $_[0]{can_manage_users_groups};
    }
}
{
    package FakeConfig;
    sub new {
        my ($class, %args) = @_;
        bless \%args, $class;
    }
    sub ExternalUserManagement { $_[0]{ExternalUserManagement} }
    sub AuthenticationModule   { $_[0]{AuthenticationModule} // 'MT' }
}
{
    package FakeApp;
    sub new {
        my ($class, %args) = @_;
        bless \%args, $class;
    }
    sub user   { $_[0]{user} }
    sub config { $_[0]{config} }
}

sub _app {
    my (%user) = @_;
    return FakeApp->new(
        user   => FakeUser->new(%user),
        config => FakeConfig->new(),
    );
}

sub _seed {
    my (%args) = @_;
    my $u = MT::Author->new;
    $u->id($args{id}) if defined $args{id};
    $u->name($args{name} // 'user');
    $u->nickname($args{nickname} // $args{display_name} // 'Nick');
    $u->email($args{email});
    $u->url($args{url});
    $u->type($args{type} // MT::Author::AUTHOR());
    $u->status($args{status} // MT::Author::ACTIVE());
    $u->is_superuser($args{is_superuser} // 0);
    $u->locked_out_time($args{locked_out_time} // 0);
    $u->created_on($args{created_on} // '20260101120000');
    $u->save;
    return $u;
}

# ------------------------------------------------------------------
# 1. require_manage_users
# ------------------------------------------------------------------

{
    my $got = eval { MTMCP::Perm::require_manage_users(FakeApp->new(user => undef)) };
    my $err = $@;
    ok(!$got && $err, '未認証は die');
    like($err, qr/認証/, '未認証メッセージ');
}

{
    my $ok = eval {
        MTMCP::Perm::require_manage_users(_app(id => 1, can_manage_users_groups => 1));
        1;
    };
    ok($ok, 'can_manage_users_groups は通る') or diag($@);
}

{
    my $ok = eval {
        MTMCP::Perm::require_manage_users(
            _app(id => 1, is_superuser => 1, can_manage_users_groups => 1)
        );
        1;
    };
    ok($ok, 'superuser（can_manage_users_groups 経由）は通る') or diag($@);
}

{
    my $ok = eval {
        MTMCP::Perm::require_manage_users(
            _app(id => 2, is_superuser => 1, can_manage_users_groups => 0)
        );
        1;
    };
    ok($ok, 'is_superuser は can_manage_users_groups 相当で通る') or diag($@);
}

{
    my $got = eval {
        MTMCP::Perm::require_manage_users(_app(id => 3, can_manage_users_groups => 0));
    };
    my $err = $@;
    ok(!$got, '権限なしは拒否');
    like($err, qr/ユーザーを管理する権限がありません/, '権限なしメッセージ');
}

{
    no warnings 'redefine';
    *MTMCP::Perm::require_manage_users = sub { 1 };
}

my $caller = FakeUser->new(id => 99, is_superuser => 1, can_manage_users_groups => 1);
my $app = FakeApp->new(user => $caller, config => FakeConfig->new());

# ------------------------------------------------------------------
# 2. user_list excludes COMMENTER
# ------------------------------------------------------------------

{
    MT::Author::reset();
    _seed(id => 1, name => 'alice', type => MT::Author::AUTHOR());
    _seed(id => 2, name => 'bob-commenter', type => MT::Author::COMMENTER());
    _seed(id => 3, name => 'carol', type => MT::Author::AUTHOR());
    my $got = MTMCP::Tools::User::list($app, {});
    is(ref $got, 'ARRAY', 'user_list は配列を返す');
    my @names = sort map { $_->{name} } @$got;
    is_deeply(\@names, [qw(alice carol)], 'COMMENTER を返さない');
    is($MT::Author::LAST_LOAD_TERMS->{type}, MT::Author::AUTHOR(), 'load は type=AUTHOR');
    is($MT::Author::LAST_LOAD_ARGS->{sort}, 'name', 'sort name');
    is($MT::Author::LAST_LOAD_ARGS->{direction}, 'ascend', 'ascend');
    ok(!exists $got->[0]{password}, 'list に password が無い');
}

{
    MT::Author::reset();
    _seed(id => 1, name => 'active-user', status => MT::Author::ACTIVE());
    _seed(id => 2, name => 'disabled-user', status => MT::Author::INACTIVE());
    _seed(id => 3, name => 'pending-user', status => MT::Author::PENDING());
    my $got = MTMCP::Tools::User::list($app, { status => 'disabled' });
    my @names = map { $_->{name} } @$got;
    is_deeply(\@names, ['disabled-user'], 'status=disabled は INACTIVE のみ');
    is($MT::Author::LAST_LOAD_TERMS->{status}, MT::Author::INACTIVE(), 'disabled は INACTIVE 定数');
}

# ------------------------------------------------------------------
# 3. user_get COMMENTER not found
# ------------------------------------------------------------------

{
    MT::Author::reset();
    _seed(id => 5, name => 'guest', type => MT::Author::COMMENTER());
    my $got = eval { MTMCP::Tools::User::get($app, { user_id => 5 }) };
    my $err = $@;
    ok(!$got, 'COMMENTER の get は失敗');
    like($err, qr/User not found: 5/, 'COMMENTER は User not found');
    is(ref $MT::Author::LAST_LOAD_TERMS, 'HASH', 'user_get はハッシュ load');
    is($MT::Author::LAST_LOAD_TERMS->{type}, MT::Author::AUTHOR(), 'user_get は type=AUTHOR');
    is($MT::Author::LAST_LOAD_TERMS->{id}, 5, 'user_get は id も指定');
}

{
    MT::Author::reset();
    _seed(id => 1, name => 'alice', nickname => 'Alice', email => 'a@example.com');
    my $got = MTMCP::Tools::User::get($app, { user_id => 1 });
    is($got->{name}, 'alice', 'AUTHOR は get できる');
    is($got->{display_name}, 'Alice', 'display_name は nickname');
    is($got->{status}, 'active', 'status は小文字');
    ok(!exists $got->{password}, 'get に password が無い');
}

# ------------------------------------------------------------------
# 4. create missing name/password/display_name
# ------------------------------------------------------------------

{
    MT::Author::reset();
    my $got = eval { MTMCP::Tools::User::create($app, { password => 'p', display_name => 'N' }) };
    like($@, qr/name is required/, 'name なしは失敗');
}

{
    MT::Author::reset();
    my $got = eval { MTMCP::Tools::User::create($app, { name => 'n', display_name => 'N' }) };
    like($@, qr/password is required/, 'password なしは失敗');
}

{
    MT::Author::reset();
    my $got = eval { MTMCP::Tools::User::create($app, { name => 'n', password => 'p' }) };
    like($@, qr/display_name is required/, 'display_name なしは失敗');
}

{
    MT::Author::reset();
    my $got = eval {
        MTMCP::Tools::User::create($app, { name => 'bad<name>', password => 'secret', display_name => 'N' });
    };
    like($@, qr/[<>]/, 'name の <> は拒否');
}

# ------------------------------------------------------------------
# 5. create success: no password in hash
# ------------------------------------------------------------------

{
    MT::Author::reset();
    my $got = MTMCP::Tools::User::create($app, {
        name         => 'newbie',
        password     => 'changeme',
        display_name => 'Newbie',
        email        => 'new@example.com',
    });
    is($got->{name}, 'newbie', 'create 成功');
    is($got->{display_name}, 'Newbie', 'nickname が入る');
    is($got->{status}, 'created', 'status created');
    ok(!exists $got->{password}, 'create 返却に password が無い');
    is($got->{email}, 'new@example.com', 'email を返す');
    my $stored = MT::Author->load({ id => $got->{id}, type => MT::Author::AUTHOR() });
    is($stored->type, MT::Author::AUTHOR(), 'type は AUTHOR');
    isnt($stored->password, 'changeme', '平文パスワードを保存しない');
    like($stored->password, qr/^hashed:/, 'set_password でハッシュ化');
}

# ------------------------------------------------------------------
# 6. duplicate name
# ------------------------------------------------------------------

{
    MT::Author::reset();
    _seed(id => 1, name => 'alice');
    my $got = eval {
        MTMCP::Tools::User::create($app, {
            name => 'alice', password => 'x', display_name => 'A',
        });
    };
    my $err = $@;
    ok(!$got, '同名は失敗');
    like($err, qr/already exists/, 'duplicate name');
}

# ------------------------------------------------------------------
# 7. delete self rejected
# ------------------------------------------------------------------

{
    MT::Author::reset();
    _seed(id => 99, name => 'me');
    my $got = eval { MTMCP::Tools::User::remove($app, { user_id => 99 }) };
    my $err = $@;
    ok(!$got, '自分自身の削除は失敗');
    like($err, qr/自分自身/, '自分削除メッセージ');
    ok(MT::Author->load({ id => 99, type => MT::Author::AUTHOR() }), '自分は残る');
}

# ------------------------------------------------------------------
# 8. non-superuser cannot delete superuser
# ------------------------------------------------------------------

{
    MT::Author::reset();
    _seed(id => 1, name => 'root', is_superuser => 1);
    my $mgr = FakeApp->new(
        user   => FakeUser->new(id => 8, is_superuser => 0, can_manage_users_groups => 1),
        config => FakeConfig->new(),
    );
    my $got = eval { MTMCP::Tools::User::remove($mgr, { user_id => 1 }) };
    my $err = $@;
    ok(!$got, '非 superuser は superuser を消せない');
    like($err, qr/スーパーユーザー/, 'superuser 削除拒否');
}

{
    MT::Author::reset();
    _seed(id => 1, name => 'root', is_superuser => 1);
    my $ok = MTMCP::Tools::User::remove($app, { user_id => 1 });
    is($ok->{status}, 'deleted', 'superuser 同士の他者削除は可');
    ok(!MT::Author->load({ id => 1, type => MT::Author::AUTHOR() }), '削除される');
}

# ------------------------------------------------------------------
# 9. unlock calls Lockout->unlock
# ------------------------------------------------------------------

{
    MT::Author::reset();
    MT::Lockout::reset();
    _seed(id => 4, name => 'locked', locked_out_time => time());
    my $got = MTMCP::Tools::User::unlock($app, { user_id => 4 });
    is(scalar @MT::Lockout::UNLOCKED, 1, 'Lockout->unlock を呼ぶ');
    is($got->{status}, 'unlocked', 'status unlocked');
    is($got->{locked_out}, 0, 'locked_out は 0');
    is($got->{user_id}, 4, 'user_id');
    my $u = MT::Author->load({ id => 4, type => MT::Author::AUTHOR() });
    is($u->locked_out_time, 0, 'locked_out_time をクリア');
}

{
    MT::Author::reset();
    MT::Lockout::reset();
    _seed(id => 4, name => 'open', locked_out_time => 0);
    my $got = MTMCP::Tools::User::unlock($app, { user_id => 4 });
    is($got->{status}, 'unlocked', '未ロックでもエラーにしない');
    is(scalar @MT::Lockout::UNLOCKED, 1, '未ロックでも unlock を呼ぶ');
}

# ------------------------------------------------------------------
# 10. recover fails without email / can_recover_password false
# ------------------------------------------------------------------

{
    MT::Author::reset();
    MT::Auth::reset();
    MT::CMS::Tools::reset();
    _seed(id => 2, name => 'no-mail', email => '');
    my $got = eval { MTMCP::Tools::User::recover_password($app, { user_id => 2 }) };
    my $err = $@;
    ok(!$got, 'email なしは失敗');
    like($err, qr/email is required/, 'email required');
    is(scalar @MT::CMS::Tools::RESET_CALLS, 0, 'email なしでは reset_password しない');
}

{
    MT::Author::reset();
    MT::Auth::reset();
    $MT::Auth::CAN_RECOVER = 0;
    _seed(id => 3, name => 'ldap', email => 'l@example.com');
    my $got = eval { MTMCP::Tools::User::recover_password($app, { user_id => 3 }) };
    my $err = $@;
    ok(!$got, 'can_recover_password 偽は失敗');
    like($err, qr/パスワードを回復できません/, 'recover 不可メッセージ');
}

{
    MT::Author::reset();
    MT::Auth::reset();
    MT::CMS::Tools::reset();
    _seed(id => 7, name => 'ok', email => 'ok@example.com');
    my $got = MTMCP::Tools::User::recover_password($app, { user_id => 7 });
    is($got->{status}, 'sent', 'recover 成功');
    is($got->{email}, 'ok@example.com', '管理者向けに email を返す');
    is($got->{user_id}, 7, 'user_id');
    is(scalar @MT::CMS::Tools::RESET_CALLS, 1, 'reset_password を呼ぶ');
}

{
    my $got = eval {
        MTMCP::Tools::User::recover_password($app, { user_id => 7, password => 'new' });
    };
    like($@, qr/new password must not be passed/, '新しいパスワード引数は拒否');
}

done_testing();
