package MTMCP::App;
use strict;
use warnings;
use JSON::XS;

my $json = JSON::XS->new->utf8->canonical;

sub handle {
    my ($app) = @_;

    unless ($app->request_method eq 'POST') {
        return _respond($app, 405, { error => 'Method Not Allowed' });
    }

    my $ct = $app->request->content_type // '';
    unless ($ct =~ m{application/json}i) {
        return _respond($app, 415, { error => 'Content-Type must be application/json' });
    }

    my $auth = $app->request->header('Authorization') // '';
    unless ($auth =~ /^Bearer\s+(.+)$/i) {
        $app->response->header('WWW-Authenticate' => 'Bearer realm="MT MCP"');
        return _respond($app, 401, { error => 'Unauthorized' });
    }
    my $provided_token = $1;

    my $plugin      = MT->component('MTMCP');
    my $valid_token = $plugin->get_config_value('api_token', 'system') // '';

    unless ($valid_token && $provided_token eq $valid_token) {
        return _respond($app, 401, { error => 'Invalid token' });
    }

    my $body = $app->request->content // '';
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
        $app->response->status(204);
        return '';
    }

    return _respond($app, 200, $response);
}

sub _respond {
    my ($app, $status, $data) = @_;
    $app->response->status($status);
    $app->response->header('Content-Type' => 'application/json; charset=UTF-8');
    return $json->encode($data);
}

1;
