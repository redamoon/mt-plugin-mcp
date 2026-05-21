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
        $app->response_code(204);
        return '';
    }

    return _respond($app, 200, $response);
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

    $app->response_code(200);
    $app->set_header('Content-Type'  => 'text/event-stream');
    $app->set_header('Cache-Control' => 'no-cache');
    $app->set_header('Connection'    => 'keep-alive');
    $app->set_header('Access-Control-Allow-Origin' => '*');

    # endpoint イベントを送信（クライアントはこの URL に JSON-RPC を POST する）
    return "event: endpoint\ndata: $post_url\n\n";
}

sub _check_auth {
    my ($app) = @_;
    my $auth = $app->get_header('Authorization')
            // $ENV{REDIRECT_HTTP_AUTHORIZATION}
            // '';
    unless ($auth =~ /^Bearer\s+(.+)$/i) {
        $app->set_header('WWW-Authenticate' => 'Bearer realm="MT MCP"');
        return _respond($app, 401, { error => 'Unauthorized' });
    }
    my $provided_token = $1;
    my $plugin      = MT->component('MTMCP');
    my $valid_token = $plugin->get_config_value('api_token', 'system') // '';
    unless ($valid_token && $provided_token eq $valid_token) {
        return _respond($app, 401, { error => 'Invalid token' });
    }
    return undef;
}

sub _respond {
    my ($app, $status, $data) = @_;
    $app->response_code($status);
    $app->set_header('Content-Type' => 'application/json; charset=UTF-8');
    return $json->encode($data);
}

1;
