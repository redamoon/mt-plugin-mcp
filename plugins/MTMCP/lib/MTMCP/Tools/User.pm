package MTMCP::Tools::User;
use strict;
use warnings;
use utf8;
use MT::Author;
use MTMCP::Perm;

sub list {
    my ($app, $args) = @_;
    MTMCP::Perm::require_manage_users($app);

    my $limit   = $args->{limit}  // 20;
    my $offset  = $args->{offset} // 0;
    my $keyword = $args->{keyword};
    my $status  = $args->{status} // 'all';
    my $lockout = $args->{lockout};

    my %terms = ( type => MT::Author::AUTHOR() );
    if (defined $status && $status ne '' && $status ne 'all') {
        $terms{status} = _status_id($status);
    }

    my $need_post_filter
        = (defined $keyword && $keyword ne '')
        || (defined $lockout && $lockout ne '');

    my %load_opts = ( sort => 'name', direction => 'ascend' );
    unless ($need_post_filter) {
        $load_opts{limit}  = $limit;
        $load_opts{offset} = $offset;
    }

    my @users = MT::Author->load(\%terms, \%load_opts);

    if (defined $keyword && $keyword ne '') {
        my $kw = lc $keyword;
        @users = grep {
            index(lc($_->name     // ''), $kw) >= 0
                || index(lc($_->nickname // ''), $kw) >= 0
                || index(lc($_->email    // ''), $kw) >= 0
        } @users;
    }

    if (defined $lockout && $lockout ne '') {
        if ($lockout eq 'locked_out') {
            @users = grep { $_->locked_out } @users;
        }
        elsif ($lockout eq 'not_locked_out') {
            @users = grep { !$_->locked_out } @users;
        }
        else {
            die "Unknown lockout filter: $lockout\n";
        }
    }

    if ($need_post_filter) {
        @users = splice(@users, $offset, $limit);
    }

    return [ map { _to_hash($_) } @users ];
}

sub get {
    my ($app, $args) = @_;
    MTMCP::Perm::require_manage_users($app);
    my $user_id = $args->{user_id} or die "user_id is required\n";
    my $user = _load_author($user_id) or die "User not found: $user_id\n";
    return _to_hash($user);
}

sub create {
    my ($app, $args) = @_;
    MTMCP::Perm::require_manage_users($app);

    my $name         = $args->{name};
    my $password     = $args->{password};
    my $display_name = $args->{display_name};
    die "name is required\n"         if !defined $name         || $name eq '';
    die "password is required\n"     if !defined $password     || $password eq '';
    die "display_name is required\n" if !defined $display_name || $display_name eq '';

    die "name に < または > は使えません\n" if $name =~ /[<>]/;

    if (eval { $app->config } && eval { $app->config->ExternalUserManagement }) {
        die "外部認証でユーザーを管理しているため、MCP からユーザーを作成できません\n";
    }

    if (MT::Author->exist({ name => $name, type => MT::Author::AUTHOR() })) {
        die "User name already exists: $name\n";
    }

    if (defined $args->{email} && $args->{email} ne '') {
        require MT::Util;
        die "Invalid email\n" unless MT::Util::is_valid_email($args->{email});
    }

    if ($app->can('verify_password_strength')) {
        my $err = $app->verify_password_strength($name, $password);
        die "$err\n" if $err;
    }

    my $user = MT::Author->new;
    $user->type(MT::Author::AUTHOR());
    $user->name($name);
    $user->nickname($display_name);
    $user->set_password($password);
    $user->email($args->{email}) if defined $args->{email};
    $user->url($args->{url})     if defined $args->{url};
    $user->text_format(0);

    my $auth_type = eval { $app->config->AuthenticationModule };
    $user->auth_type($auth_type) if defined $auth_type && $auth_type ne '';

    $user->set_status_by_text($args->{status} // 'active');

    $user->save or die $user->errstr . "\n";

    my $hash = _to_hash($user);
    $hash->{status} = 'created';
    return $hash;
}

sub remove {
    my ($app, $args) = @_;
    MTMCP::Perm::require_manage_users($app);
    my $user_id = $args->{user_id} or die "user_id is required\n";
    my $user = _load_author($user_id) or die "User not found: $user_id\n";

    my $me = eval { $app->user };
    die "自分自身は削除できません\n" if $me && defined $me->id && $me->id == $user->id;

    if ($user->is_superuser) {
        die "スーパーユーザーを削除する権限がありません\n"
            unless $me && $me->is_superuser;
    }

    my $name = $user->name;
    $user->remove or die $user->errstr . "\n";
    return { user_id => $user_id, status => 'deleted', name => $name };
}

sub unlock {
    my ($app, $args) = @_;
    MTMCP::Perm::require_manage_users($app);
    my $user_id = $args->{user_id} or die "user_id is required\n";
    my $user = _load_author($user_id) or die "User not found: $user_id\n";

    require MT::Lockout;
    MT::Lockout->unlock($user);
    $user->save or die $user->errstr . "\n";
    return {
        user_id    => $user->id,
        status     => 'unlocked',
        locked_out => 0,
    };
}

sub recover_password {
    my ($app, $args) = @_;
    MTMCP::Perm::require_manage_users($app);
    my $user_id = $args->{user_id} or die "user_id is required\n";
    die "new password must not be passed; use recover email instead\n"
        if exists $args->{password} || exists $args->{new_password};

    require MT::Auth;
    die "この設定ではパスワードを回復できません\n"
        unless MT::Auth->can_recover_password;

    my $user = _load_author($user_id) or die "User not found: $user_id\n";
    my $email = $user->email;
    die "email is required\n" if !defined $email || $email eq '';

    require MT::CMS::Tools;
    my ($rc, $res) = MT::CMS::Tools::reset_password($app, $user);
    die (($res || 'Failed to send password recovery email') . "\n") unless $rc;

    return {
        user_id => $user->id,
        status  => 'sent',
        email   => $email,
    };
}

sub _load_author {
    my ($user_id) = @_;
    return MT::Author->load({ id => $user_id, type => MT::Author::AUTHOR() });
}

sub _status_id {
    my ($status) = @_;
    return MT::Author::ACTIVE()   if $status eq 'active';
    return MT::Author::INACTIVE() if $status eq 'disabled';
    return MT::Author::PENDING()  if $status eq 'pending';
    die "Unknown user status: $status\n";
}

sub _to_hash {
    my ($user) = @_;
    my $text = eval { $user->get_status_text } // '';
    return {
        id           => $user->id,
        name         => $user->name,
        display_name => $user->nickname,
        email        => $user->email,
        url          => $user->url,
        status       => lc($text),
        locked_out   => $user->locked_out ? 1 : 0,
        is_superuser => $user->is_superuser ? 1 : 0,
        created_on   => $user->created_on,
    };
}

1;
