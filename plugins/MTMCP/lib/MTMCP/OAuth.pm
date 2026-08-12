package MTMCP::OAuth;
use strict;
use warnings;
use JSON;
use Digest::SHA qw(sha256);
use MIME::Base64 qw(encode_base64);

my $json = JSON->new->ascii->canonical;

use constant CODE_DURATION       => 600;                 # 認可コードの有効期限: 10分
use constant TOKEN_DURATION      => 604800;               # アクセストークンの有効期限: 7日
use constant CLIENT_REG_DURATION => 10 * 365 * 24 * 3600; # クライアント登録の有効期限: 実質無期限（10年）

# 既知の MCP クライアントがクラウド側（ローカルではない）で OAuth を完結させる
# 際に使う、ベンダー自身が管理する固定のHTTPSコールバックURL。
# 任意の外部ホストを許可するわけではなく、完全一致のもののみを個別に信頼する。
my %KNOWN_HTTPS_REDIRECT_URIS = map { $_ => 1 } (
    'https://www.cursor.com/agents/mcp/oauth/callback',   # Cursor Background Agent
);

# ネイティブ／ローカルアプリ向け OAuth のリダイレクト規約（RFC 8252）に従い、
# 以下のパターンのみ許可する。任意の http(s) 外部ホストへのリダイレクトは
# オープンリダイレクト・トークン漏えいの原因になるため許可しない。
#
#   1. ループバックリダイレクト（RFC 8252 §7.3）:
#      http://127.0.0.1:*, http://localhost:*, http://[::1]:*
#   2. プライベートスキームリダイレクト（RFC 8252 §7.1）:
#      Cursor（cursor://...）や Claude Desktop など、OS のカスタムURLスキーム
#      ハンドラで自アプリに戻ってくる方式。http/https 以外のスキームは
#      任意のWebサイトには遷移できず、OSに登録された特定アプリにのみ
#      渡されるため許可する。
#   3. 既知クライアントの固定HTTPSコールバック（完全一致のみ）:
#      %KNOWN_HTTPS_REDIRECT_URIS を参照。
sub is_valid_redirect_uri {
    my ($uri) = @_;
    return 0 unless defined $uri && length $uri;

    # C0制御文字・DELを含むURIは拒否する。スキーム名の直後などに紛れ込ませて
    # 後続処理（$app->redirect のLocationヘッダー生成など）に予期しない
    # 挙動を起こさせないため、スキーム判定より前に弾く。
    return 0 if $uri =~ /[\x00-\x1F\x7F]/;

    # RFC 6749 §3.1.2: redirect_uri にフラグメントを含めてはならない。
    # 含まれていると code/state がフラグメントとして付与されてしまい、
    # サーバー側のリダイレクト先アプリに渡らなくなる。
    return 0 if index($uri, '#') >= 0;

    return 1 if $uri =~ m{^http://(?:127\.0\.0\.1|localhost|\[::1\])(?::\d+)?(?:/|\?|$)}i;

    if ($uri =~ m{^([a-zA-Z][a-zA-Z0-9+.-]*)://}) {
        my $scheme = lc $1;
        return 1 if $scheme ne 'http' && $scheme ne 'https';
    }

    return 1 if $KNOWN_HTTPS_REDIRECT_URIS{$uri};

    return 0;
}

# $client_id が Dynamic Client Registration で登録済みの場合は、その
# redirect_uris への完全一致を要求する（別クライアントの認可コードを
# 意図しないURLへ誘導する取り違え攻撃を防ぐ）。未登録の client_id
# （または client_id 未指定）の場合は、既存のグローバルな検証
# （ループバック／プライベートスキーム／既知の固定HTTPSコールバック）に
# フォールバックする。
sub is_valid_redirect_uri_for_client {
    my ($client_id, $uri) = @_;
    my $registered = _lookup_client_redirect_uris($client_id);
    if ($registered && @$registered) {
        return (grep { $_ eq $uri } @$registered) ? 1 : 0;
    }
    return is_valid_redirect_uri($uri);
}

sub _store_client {
    my ($client_id, $redirect_uris, $client_name) = @_;
    require MT::Session;
    my $session = MT::Session->new;
    $session->id($client_id);
    $session->kind('DR');
    $session->start(time());
    $session->duration(CLIENT_REG_DURATION);
    $session->set('redirect_uris', $json->encode($redirect_uris));
    $session->set('client_name', $client_name // '');
    $session->save or die "Could not store client registration: " . $session->errstr . "\n";
    return;
}

sub _lookup_client_redirect_uris {
    my ($client_id) = @_;
    return undef unless defined $client_id && length $client_id;
    require MT::Session;
    my $session = MT::Session->load({ id => $client_id, kind => 'DR' });
    return undef unless $session;
    my $uris = eval { $json->decode($session->get('redirect_uris') // '[]') };
    return (ref($uris) eq 'ARRAY') ? $uris : [];
}

sub base64url_encode {
    my ($bytes) = @_;
    my $b64 = encode_base64($bytes, '');
    $b64 =~ tr{+/}{-_};
    $b64 =~ s/=+$//;
    return $b64;
}

# PKCE (RFC 7636) の code_challenge を検証する。ダウングレード攻撃を避けるため
# S256 のみをサポートする（plain は受け付けない）。
sub verify_pkce {
    my ($code_verifier, $code_challenge) = @_;
    return 0 unless defined $code_verifier && length $code_verifier;
    return 0 unless defined $code_challenge && length $code_challenge;
    return base64url_encode(sha256($code_verifier)) eq $code_challenge;
}

# consent 画面での承認後に認可コードを発行する。
sub issue_code {
    my (%args) = @_;
    my ($author, $redirect_uri, $code_challenge, $client_id)
        = @args{qw(author redirect_uri code_challenge client_id)};

    my $code = _random_token();
    require MT::Session;
    my $session = MT::Session->new;
    $session->id($code);
    $session->kind('DC');
    $session->start(time());
    $session->duration(CODE_DURATION);
    $session->set('author_id', $author->id);
    $session->set('redirect_uri', $redirect_uri);
    $session->set('code_challenge', $code_challenge);
    $session->set('client_id', $client_id // '');
    $session->save or die "Could not store authorization code: " . $session->errstr . "\n";
    return $code;
}

# POST /v4/mcp/token — 認可コード（+ PKCE code_verifier）またはリフレッシュ
# トークンを、アクセストークンに交換する。
sub handle_token {
    my ($app) = @_;

    unless ($app->request_method eq 'POST') {
        return _oauth_error($app, 405, 'invalid_request', 'Method Not Allowed');
    }

    my $params = _parse_body($app);
    my $grant_type = $params->{grant_type} // '';

    if ($grant_type eq 'authorization_code') {
        return _handle_authorization_code_grant($app, $params);
    }
    if ($grant_type eq 'refresh_token') {
        return _handle_refresh_token_grant($app, $params);
    }
    return _oauth_error($app, 400, 'unsupported_grant_type', 'Only authorization_code and refresh_token are supported');
}

sub _handle_authorization_code_grant {
    my ($app, $params) = @_;

    my $code          = $params->{code};
    my $redirect_uri  = $params->{redirect_uri};
    my $code_verifier = $params->{code_verifier};
    my $client_id     = $params->{client_id} // '';
    unless ($code && $redirect_uri && $code_verifier) {
        return _oauth_error($app, 400, 'invalid_request', 'code, redirect_uri and code_verifier are required');
    }

    require MT::Session;
    my $session = MT::Session->load({ id => $code, kind => 'DC' });

    unless ($session && $session->start + $session->duration >= time()) {
        $session->remove if $session;
        return _oauth_error($app, 400, 'invalid_grant', 'Authorization code is invalid or expired');
    }

    # 認可コードは一度きり。以降の検証結果に関わらず即座に無効化する。
    my $stored_redirect  = $session->get('redirect_uri')   // '';
    my $stored_challenge = $session->get('code_challenge') // '';
    my $stored_client_id = $session->get('client_id')      // '';
    my $author_id         = $session->get('author_id');
    $session->remove;

    unless ($redirect_uri eq $stored_redirect) {
        return _oauth_error($app, 400, 'invalid_grant', 'redirect_uri mismatch');
    }
    # 認可時に記録した client_id とリクエストの client_id を照合し、盗んだ
    # 認可コードを別クライアントとして引き換える取り違え攻撃を防ぐ。
    unless ($client_id eq $stored_client_id) {
        return _oauth_error($app, 400, 'invalid_grant', 'client_id mismatch');
    }
    unless (verify_pkce($code_verifier, $stored_challenge)) {
        return _oauth_error($app, 400, 'invalid_grant', 'code_verifier mismatch');
    }

    require MT::Author;
    my $author = $author_id && MT::Author->load($author_id);
    unless ($author && $author->status == MT::Author::ACTIVE()) {
        return _oauth_error($app, 400, 'invalid_grant', 'User account is not active');
    }

    require MTMCP::Auth;
    my $token         = eval { MTMCP::Auth::issue_token_for($author) };
    my $refresh_token = $token && eval { MTMCP::Auth::issue_refresh_token_for($author) };
    unless ($token && $refresh_token) {
        warn "MTMCP: token issuance failed during OAuth exchange: $@";
        return _oauth_error($app, 500, 'server_error', 'Could not issue access token');
    }

    return _respond($app, 200, {
        access_token  => $token,
        refresh_token => $refresh_token,
        token_type    => 'Bearer',
        expires_in    => TOKEN_DURATION,
        user_id       => $author->id,
        username      => $author->name,
    });
}

# refresh_token グラント: リフレッシュトークンを新しいアクセストークンに
# 交換する。使用済みのリフレッシュトークンは即座に無効化し、新しい
# リフレッシュトークンを発行する（ローテーション。盗用されたトークンの
# 再利用を検知・遮断しやすくするため）。
sub _handle_refresh_token_grant {
    my ($app, $params) = @_;

    my $refresh_token = $params->{refresh_token};
    unless ($refresh_token) {
        return _oauth_error($app, 400, 'invalid_request', 'refresh_token is required');
    }

    require MTMCP::Auth;
    my $session = MTMCP::Auth::resolve_refresh_session($refresh_token);
    unless ($session) {
        return _oauth_error($app, 400, 'invalid_grant', 'Refresh token is invalid or expired');
    }

    my $author_id = $session->get('author_id');
    $session->remove;

    require MT::Author;
    my $author = $author_id && MT::Author->load($author_id);
    unless ($author && $author->status == MT::Author::ACTIVE()) {
        return _oauth_error($app, 400, 'invalid_grant', 'User account is not active');
    }

    my $token         = eval { MTMCP::Auth::issue_token_for($author) };
    my $new_refresh   = $token && eval { MTMCP::Auth::issue_refresh_token_for($author) };
    unless ($token && $new_refresh) {
        warn "MTMCP: token issuance failed during refresh: $@";
        return _oauth_error($app, 500, 'server_error', 'Could not issue access token');
    }

    return _respond($app, 200, {
        access_token  => $token,
        refresh_token => $new_refresh,
        token_type    => 'Bearer',
        expires_in    => TOKEN_DURATION,
        user_id       => $author->id,
        username      => $author->name,
    });
}

# POST /v4/mcp/register — Dynamic Client Registration (RFC 7591)。
# authorization_code フローのみを提供するため、redirect_uris を1つ以上
# 必須とし、登録された redirect_uris を永続化して認可時に完全一致で
# 検証する（is_valid_redirect_uri_for_client）。client_secret は発行しない
# （PKCE を使うパブリッククライアント向けの token_endpoint_auth_method=none）。
sub handle_register {
    my ($app) = @_;

    unless ($app->request_method eq 'POST') {
        return _oauth_error($app, 405, 'invalid_request', 'Method Not Allowed');
    }

    my $body = $app->param('POSTDATA') // $app->request_content // '';
    my $data = eval { $json->decode($body) };
    if ($@ || ref($data) ne 'HASH') {
        return _oauth_error($app, 400, 'invalid_client_metadata', 'Request body must be a valid JSON object');
    }

    my $redirect_uris = $data->{redirect_uris};
    unless (ref($redirect_uris) eq 'ARRAY' && @$redirect_uris) {
        return _oauth_error($app, 400, 'invalid_redirect_uri', 'redirect_uris must be a non-empty array');
    }
    for my $uri (@$redirect_uris) {
        unless (is_valid_redirect_uri($uri)) {
            return _oauth_error($app, 400, 'invalid_redirect_uri', "redirect_uri not allowed: $uri");
        }
    }

    my $client_id   = _random_token();
    my $client_name = $data->{client_name} // 'MCP Client';
    eval { _store_client($client_id, $redirect_uris, $client_name) };
    if ($@) {
        warn "MTMCP: client registration failed: $@";
        return _oauth_error($app, 500, 'server_error', 'Could not register client');
    }

    return _respond($app, 201, {
        client_id                    => $client_id,
        client_id_issued_at          => time(),
        redirect_uris                => $redirect_uris,
        token_endpoint_auth_method   => 'none',
        grant_types                  => ['authorization_code'],
        response_types               => ['code'],
        client_name                  => $client_name,
    });
}

sub _random_token {
    require MTMCP::Auth;
    return MTMCP::Auth::secure_random_hex(32);
}

sub _parse_body {
    my ($app) = @_;
    my $ct = $app->get_header('Content-Type') // $ENV{CONTENT_TYPE} // '';

    if ($ct =~ m{application/json}i) {
        my $body = $app->param('POSTDATA') // $app->request_content // '';
        my $data = eval { $json->decode($body) };
        return (ref($data) eq 'HASH') ? $data : {};
    }

    # application/x-www-form-urlencoded（OAuth トークンエンドポイントの標準形式）は
    # MT のアプリフレームワーク（CGI.pm）側で既にパース済みのため、$app->param() から
    # 直接取得する。生のリクエストボディを手動で再パースしようとしても、
    # CGI.pm が読み切った後では空になっている。
    my %params;
    for my $key (qw(grant_type code redirect_uri code_verifier client_id refresh_token)) {
        my $v = $app->param($key);
        $params{$key} = $v if defined $v;
    }
    return \%params;
}

sub _oauth_error {
    my ($app, $status, $error, $desc) = @_;
    return _respond($app, $status, { error => $error, error_description => $desc });
}

sub _respond {
    my ($app, $status, $data) = @_;
    $app->set_header('Access-Control-Allow-Origin'  => '*');
    $app->set_header('Access-Control-Allow-Methods' => 'GET, POST, OPTIONS');
    $app->set_header('Access-Control-Allow-Headers' => 'Authorization, Content-Type');
    # RFC 6749 §5.1: トークンを含む応答はキャッシュされてはならない
    $app->set_header('Cache-Control' => 'no-store');
    $app->set_header('Pragma'        => 'no-cache');
    $app->response_code($status);
    $app->set_header('Content-Type' => 'application/json; charset=UTF-8');
    return $json->encode($data);
}

1;
