package MTMCP::CMS::Authorize;
use strict;
use warnings;
use MTMCP::OAuth;

# GET (mt.cgi 経由): MT に未ログインならコアの仕組みで自動的にログイン画面へ
# 誘導される。ログイン済みなら、MCP クライアントへのアクセス許可を確認する
# consent 画面を表示する。パスワードはこの画面には一切現れない。
sub show {
    my ($app) = @_;
    my $user = $app->user;
    return $app->permission_denied unless $user && !$user->is_anonymous;

    my %q = _oauth_params($app);
    if (my $err = _validate(\%q)) {
        return $app->error($err);
    }

    return $app->load_tmpl('mcp_authorize.tmpl', {
        magic_token => $app->current_magic,
        username    => $user->name,
        %q,
    });
}

# POST: consent 画面での「許可する」「拒否する」の結果を受けて、
# 認可コードを発行（または拒否）し、redirect_uri へリダイレクトする。
sub approve {
    my ($app) = @_;
    my $user = $app->user;
    return $app->permission_denied unless $user && !$user->is_anonymous;
    return $app->error('Invalid request') unless $app->validate_magic;

    my %q = _oauth_params($app);
    if (my $err = _validate(\%q)) {
        return $app->error($err);
    }

    require MT::Util;
    my $redirect_uri = $q{redirect_uri};
    my $sep = ($redirect_uri =~ /\?/) ? '&' : '?';

    my $decision = $app->param('decision') // '';
    if ($decision ne 'approve') {
        my $target = $redirect_uri . $sep . 'error=access_denied';
        $target .= '&state=' . MT::Util::encode_url($q{state}) if length($q{state} // '');
        return $app->redirect($target);
    }

    my $code = MTMCP::OAuth::issue_code(
        author         => $user,
        redirect_uri   => $redirect_uri,
        code_challenge => $q{code_challenge},
        client_id      => $q{client_id},
    );

    my $target = $redirect_uri . $sep . 'code=' . MT::Util::encode_url($code);
    $target .= '&state=' . MT::Util::encode_url($q{state}) if length($q{state} // '');
    return $app->redirect($target);
}

sub _oauth_params {
    my ($app) = @_;
    return (
        response_type         => scalar($app->param('response_type')) // '',
        client_id              => scalar($app->param('client_id')) // '',
        redirect_uri            => scalar($app->param('redirect_uri')) // '',
        state                    => scalar($app->param('state')) // '',
        code_challenge           => scalar($app->param('code_challenge')) // '',
        code_challenge_method    => scalar($app->param('code_challenge_method')) // 'S256',
    );
}

sub _validate {
    my ($q) = @_;
    return 'response_type must be "code"' unless ($q->{response_type} // '') eq 'code';
    return 'redirect_uri is required'      unless length($q->{redirect_uri} // '');
    return 'redirect_uri is not allowed（ループバックアドレスのみ許可されています）'
        unless MTMCP::OAuth::is_valid_redirect_uri($q->{redirect_uri});
    return 'code_challenge is required'    unless length($q->{code_challenge} // '');
    return 'code_challenge_method must be S256' unless ($q->{code_challenge_method} // '') eq 'S256';
    return undef;
}

1;
