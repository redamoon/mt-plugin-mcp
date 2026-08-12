package MTMCP::OAuth;
use strict;
use warnings;
use JSON;
use Digest::SHA qw(sha256 sha256_hex);
use MIME::Base64 qw(encode_base64);

my $json = JSON->new->ascii->canonical;

use constant CODE_DURATION  => 600;      # 認可コードの有効期限: 10分
use constant TOKEN_DURATION => 604800;   # アクセストークンの有効期限: 7日

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

    return 1 if $uri =~ m{^http://(?:127\.0\.0\.1|localhost|\[::1\])(?::\d+)?(?:/|\?|$)}i;

    if ($uri =~ m{^([a-zA-Z][a-zA-Z0-9+.-]*)://}) {
        my $scheme = lc $1;
        return 1 if $scheme ne 'http' && $scheme ne 'https';
    }

    return 1 if $KNOWN_HTTPS_REDIRECT_URIS{$uri};

    return 0;
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

# POST /v4/mcp/token — 認可コード（+ PKCE code_verifier）をアクセストークンに交換する。
sub handle_token {
    my ($app) = @_;

    unless ($app->request_method eq 'POST') {
        return _oauth_error($app, 405, 'invalid_request', 'Method Not Allowed');
    }

    my $params = _parse_body($app);

    my $grant_type = $params->{grant_type} // '';
    unless ($grant_type eq 'authorization_code') {
        return _oauth_error($app, 400, 'unsupported_grant_type', 'Only authorization_code is supported');
    }

    my $code          = $params->{code};
    my $redirect_uri  = $params->{redirect_uri};
    my $code_verifier = $params->{code_verifier};
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
    my $stored_redirect  = $session->get('redirect_uri')  // '';
    my $stored_challenge = $session->get('code_challenge') // '';
    my $author_id         = $session->get('author_id');
    $session->remove;

    unless ($redirect_uri eq $stored_redirect) {
        return _oauth_error($app, 400, 'invalid_grant', 'redirect_uri mismatch');
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
    my $token = MTMCP::Auth::issue_token_for($author);

    return _respond($app, 200, {
        access_token => $token,
        token_type   => 'Bearer',
        expires_in   => TOKEN_DURATION,
        user_id      => $author->id,
        username     => $author->name,
    });
}

# POST /v4/mcp/register — Dynamic Client Registration (RFC 7591)。
# クライアントの事前登録は行わず、redirect_uri（ループバックのみ許可）と
# PKCE で安全性を担保しているため、リクエストされた内容をそのまま認めて
# ランダムな client_id を発行するだけの簡易実装。client_secret は発行しない
# （PKCE を使うパブリッククライアント向けの token_endpoint_auth_method=none）。
sub handle_register {
    my ($app) = @_;

    unless ($app->request_method eq 'POST') {
        return _oauth_error($app, 405, 'invalid_request', 'Method Not Allowed');
    }

    my $body = $app->param('POSTDATA') // $app->request_content // '';
    my $data = eval { $json->decode($body) };
    $data = {} unless ref($data) eq 'HASH';

    my $redirect_uris = $data->{redirect_uris};
    if (ref($redirect_uris) eq 'ARRAY' && @$redirect_uris) {
        for my $uri (@$redirect_uris) {
            unless (is_valid_redirect_uri($uri)) {
                return _respond($app, 400, {
                    error             => 'invalid_redirect_uri',
                    error_description => "redirect_uri not allowed: $uri",
                });
            }
        }
    } else {
        $redirect_uris = [];
    }

    return _respond($app, 201, {
        client_id                    => _random_token(),
        client_id_issued_at          => time(),
        redirect_uris                => $redirect_uris,
        token_endpoint_auth_method   => 'none',
        grant_types                  => ['authorization_code'],
        response_types               => ['code'],
        client_name                  => $data->{client_name} // 'MCP Client',
    });
}

sub _random_token {
    return sha256_hex(rand() . time() . $$ . int(rand(1_000_000)));
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
    for my $key (qw(grant_type code redirect_uri code_verifier client_id)) {
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
    $app->response_code($status);
    $app->set_header('Content-Type' => 'application/json; charset=UTF-8');
    return $json->encode($data);
}

1;
