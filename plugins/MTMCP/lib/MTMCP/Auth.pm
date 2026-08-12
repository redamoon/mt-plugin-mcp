package MTMCP::Auth;
use strict;
use warnings;
use JSON;
use Digest::SHA qw(sha256_hex);

# 暗号論的に安全な乱数を /dev/urandom から取得する。安全な乱数源が
# 利用できない環境では、弱い乱数へフォールバックせず失敗させる
# （トークン・認可コードの推測可能性はセキュリティ上致命的なため）。
sub secure_random_hex {
    my ($bytes) = @_;
    $bytes //= 32;
    open(my $fh, '<:raw', '/dev/urandom')
        or die "Could not open /dev/urandom for secure random generation: $!\n";
    my $data = '';
    my $read = read($fh, $data, $bytes);
    close $fh;
    die "Could not read secure random bytes\n" unless defined $read && $read == $bytes;
    return unpack('H*', $data);
}

my $json = JSON->new->ascii->canonical;

use constant TOKEN_DURATION         => 604800;            # アクセストークン有効期限: 7日
use constant REFRESH_TOKEN_DURATION => 30 * 24 * 60 * 60;  # リフレッシュトークン有効期限: 30日
use constant FAIL_WINDOW      => 900;      # ロックアウト判定の時間窓: 15分
use constant FAIL_MAX_ATTEMPT => 5;        # ロックアウトまでの失敗回数

# POST /v4/mcp/authenticate — ユーザー名・パスワードでログインし、
# 本人に紐づくアクセストークンを発行する。
sub handle_login {
    my ($app) = @_;

    unless ($app->request_method eq 'POST') {
        return _respond($app, 405, { error => 'Method Not Allowed' });
    }

    my $ct = $app->get_header('Content-Type') // $ENV{CONTENT_TYPE} // '';
    unless ($ct =~ m{application/json}i) {
        return _respond($app, 415, { error => 'Content-Type must be application/json' });
    }

    my $body = $app->param('POSTDATA') // $app->request_content // '';
    my $data = eval { $json->decode($body) };
    if ($@ || ref($data) ne 'HASH') {
        return _respond($app, 400, { error => 'Invalid JSON body' });
    }

    my $username = $data->{username};
    my $password = $data->{password};
    unless (defined $username && length $username && defined $password && length $password) {
        return _respond($app, 400, { error => 'username and password are required' });
    }

    if (_is_locked_out($username)) {
        return _respond($app, 429, { error => 'Too many failed attempts. Try again later.' });
    }

    require MT::Author;
    my $author = MT::Author->load({ name => $username, type => MT::Author::AUTHOR() });

    my $ok = $author
        && $author->status == MT::Author::ACTIVE()
        && eval { $author->is_valid_password($password) };

    unless ($ok) {
        _record_failure($username);
        # ユーザー名の存在有無を推測させないよう、失敗理由は一律で返す
        return _respond($app, 401, { error => 'Invalid username or password' });
    }

    _clear_failures($username);

    my $token         = _issue_token($author);
    my $refresh_token = _issue_refresh_token($author);

    return _respond($app, 200, {
        access_token  => $token,
        refresh_token => $refresh_token,
        token_type    => 'Bearer',
        expires_in    => TOKEN_DURATION,
        user_id       => $author->id,
        username      => $author->name,
    });
}

# トークンを発行し、author_id を紐づけて保存する。
# MTMCP::CMS::Token（管理画面からの発行）・MTMCP::OAuth とも共用する。
sub issue_token_for {
    my ($author) = @_;
    return _issue_token($author);
}

sub issue_refresh_token_for {
    my ($author) = @_;
    return _issue_refresh_token($author);
}

sub _issue_token {
    my ($author) = @_;
    my $token = secure_random_hex(32);

    require MT::Session;
    my $session = MT::Session->new;
    $session->id($token);
    $session->kind('DA');
    $session->start(time());
    $session->duration(TOKEN_DURATION);
    $session->set('author_id', $author->id);
    $session->save or die "Could not create session: " . $session->errstr . "\n";

    return $token;
}

sub _issue_refresh_token {
    my ($author) = @_;
    my $token = secure_random_hex(32);

    require MT::Session;
    my $session = MT::Session->new;
    $session->id($token);
    $session->kind('DT');
    $session->start(time());
    $session->duration(REFRESH_TOKEN_DURATION);
    $session->set('author_id', $author->id);
    $session->save or die "Could not create refresh token session: " . $session->errstr . "\n";

    return $token;
}

# トークンに紐づくユーザーを解決する。author_id が無い（旧形式）トークンは
# undef を返し、呼び出し側で互換動作させる。
sub resolve_author {
    my ($session) = @_;
    my $author_id = eval { $session->get('author_id') };
    return undef unless $author_id;
    require MT::Author;
    return MT::Author->load($author_id);
}

# リフレッシュトークンを検証する。有効なら MT::Session オブジェクトを返す
# （呼び出し側でローテーションのため remove すること）。無効・期限切れなら undef。
sub resolve_refresh_session {
    my ($refresh_token) = @_;
    return undef unless defined $refresh_token && length $refresh_token;
    require MT::Session;
    my $session = MT::Session->load({ id => $refresh_token, kind => 'DT' });
    return undef unless $session;
    return undef if $session->start + $session->duration < time();
    return $session;
}

sub _fail_key {
    my ($username) = @_;
    return 'mcpfail:' . sha256_hex(lc $username);
}

sub _load_fail_record {
    my ($username) = @_;
    require MT::Session;
    return MT::Session->load({ id => _fail_key($username), kind => 'DF' });
}

sub _is_locked_out {
    my ($username) = @_;
    my $rec = _load_fail_record($username) or return 0;
    my $count = $rec->get('count') // 0;
    my $since = $rec->get('since') // 0;
    return 0 unless $count >= FAIL_MAX_ATTEMPT;
    if (time() - $since >= FAIL_WINDOW) {
        $rec->remove;
        return 0;
    }
    return 1;
}

# 既知の制約: 読み取り→更新の間に排他制御がないため、並列リクエストでは
# カウントの取りこぼし（lost update）が起こり得る。ロックアウトは
# パスワード照合自体の防御を補完する多層防御であり、この残存リスクは
# 許容する（完全なアトミック更新には別途DBレベルのロックが必要）。
sub _record_failure {
    my ($username) = @_;
    require MT::Session;
    my $now = time();
    my $rec = _load_fail_record($username);
    if ($rec) {
        my $since = $rec->get('since') // $now;
        if ($now - $since >= FAIL_WINDOW) {
            $rec->set('count', 1);
            $rec->set('since', $now);
        } else {
            $rec->set('count', ($rec->get('count') // 0) + 1);
        }
    } else {
        $rec = MT::Session->new;
        $rec->id(_fail_key($username));
        $rec->kind('DF');
        $rec->start($now);
        $rec->duration(FAIL_WINDOW);
        $rec->set('count', 1);
        $rec->set('since', $now);
    }
    $rec->save or warn "MTMCP: failed to record login failure: " . $rec->errstr . "\n";
}

sub _clear_failures {
    my ($username) = @_;
    my $rec = _load_fail_record($username);
    $rec->remove if $rec;
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
