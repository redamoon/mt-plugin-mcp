package MTMCP::App;
use strict;
use warnings;
use JSON;

my $json = JSON->new->ascii->canonical;

sub handle {
    my ($app, $endpoint) = @_;

    unless ($app->request_method eq 'POST') {
        return _respond($app, 405, { error => 'Method Not Allowed' });
    }

    my $ct = $app->get_header('Content-Type') // $ENV{CONTENT_TYPE} // '';
    unless ($ct =~ m{application/json}i) {
        return _respond($app, 415, { error => 'Content-Type must be application/json' });
    }

    my $err = _check_auth($app);
    return $err if $err;

    my $body = $app->param('POSTDATA') // $app->request_content // '';
    my $req  = eval { $json->decode($body) };
    if ($@) {
        return _respond($app, 400, {
            jsonrpc => '2.0',
            id      => undef,
            error   => { code => -32700, message => 'Parse error' },
        });
    }

    require MTMCP::Protocol;
    my $response = MTMCP::Protocol::dispatch($app, $req);

    unless (defined $response) {
        _set_cors_headers($app);
        $app->response_code(204);
        return '';
    }

    return _respond($app, 200, $response);
}

sub handle_options {
    my ($app) = @_;
    _set_cors_headers($app);
    $app->response_code(204);
    return '';
}

# SSE endpoint — MCP クライアントが GET で接続し、POST 先 URL を受け取る
sub handle_sse {
    my ($app) = @_;

    my $err = _check_auth($app);
    return $err if $err;

    # POST エンドポイント URL を組み立てる
    my $base = $app->base;
    $base =~ s{/$}{};
    my $script = $app->mt_uri // '/mt-data-api.cgi';
    $script =~ s{/$}{};
    my $post_url = $base . $script . '/v4/mcp';

    _set_cors_headers($app);
    $app->response_code(200);
    $app->set_header('Content-Type'  => 'text/event-stream');
    $app->set_header('Cache-Control' => 'no-cache');
    $app->set_header('Connection'    => 'keep-alive');

    # endpoint イベントを送信（クライアントはこの URL に JSON-RPC を POST する）
    return "event: endpoint\ndata: $post_url\n\n";
}

sub _check_auth {
    my ($app) = @_;

    my $token;

    # 優先: Authorization: Bearer <token>  (CGIPassAuth or RewriteRule が必要)
    my $auth = $app->get_header('Authorization')
            // $ENV{REDIRECT_HTTP_AUTHORIZATION}
            // '';
    if ($auth =~ /^Bearer\s+(.+)$/i) {
        $token = $1;
    }

    # フォールバック: X-MT-Authorization: MTAuth accessToken=<token>
    # Apache がカスタムヘッダーをそのまま CGI に渡すため設定不要
    unless ($token) {
        my $mt_auth = $app->get_header('X-MT-Authorization') // '';
        if ($mt_auth =~ /MTAuth\s+accessToken=(\S+)/i) {
            $token = $1;
        }
    }

    unless ($token) {
        $app->set_header('WWW-Authenticate' => 'Bearer realm="MT MCP"');
        return _respond($app, 401, { error => 'Unauthorized' });
    }

    require MT::Session;
    my $session = MT::Session->load($token);
    unless ($session && $session->kind eq 'DA') {
        return _respond($app, 401, { error => 'Invalid token' });
    }
    if ($session->start + $session->duration < time()) {
        return _respond($app, 401, { error => 'Token expired' });
    }
    return undef;
}

sub _set_cors_headers {
    my ($app) = @_;
    $app->set_header('Access-Control-Allow-Origin'  => '*');
    $app->set_header('Access-Control-Allow-Methods' => 'GET, POST, OPTIONS');
    $app->set_header('Access-Control-Allow-Headers' => 'Authorization, Content-Type');
    $app->set_header('Access-Control-Max-Age'       => '86400');
}

sub _respond {
    my ($app, $status, $data) = @_;
    _set_cors_headers($app);
    $app->response_code($status);
    $app->set_header('Content-Type' => 'application/json; charset=UTF-8');
    return $json->encode($data);
}

1;
