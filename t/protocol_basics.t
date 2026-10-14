use strict;
use warnings;
use utf8;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../plugins/MTMCP/lib";

use JSON;
use MT;
use MTMCP::Protocol;
use MTMCP::App;

my $json = JSON->new->ascii->canonical;

# config.yaml の version を読む（テスト側の期待値の正本）。
sub _config_version {
    my $path = "$FindBin::Bin/../plugins/MTMCP/config.yaml";
    open my $fh, '<', $path or die "config.yaml を開けない: $!";
    while (my $line = <$fh>) {
        return $1 if $line =~ /^version:\s*(\S+)/;
    }
    die 'config.yaml に version が無い';
}

# --- serverInfo.version は config.yaml と一致する ---
{
    my $res = MTMCP::Protocol::dispatch(undef, {
        jsonrpc => '2.0', id => 1, method => 'initialize',
    });

    is($res->{result}{serverInfo}{version}, _config_version(),
        'serverInfo.version は config.yaml の version と一致する');
    is($res->{result}{serverInfo}{name}, 'MT MCP Server', 'serverInfo.name');
    ok($res->{result}{protocolVersion}, 'protocolVersion を返す');
}

# --- config.yaml を上げれば serverInfo も追随する ---
{
    local $MT::VERSION_OVERRIDE = '9.9.9';
    my $res = MTMCP::Protocol::dispatch(undef, {
        jsonrpc => '2.0', id => 1, method => 'initialize',
    });
    is($res->{result}{serverInfo}{version}, '9.9.9',
        'config.yaml の version を上げれば serverInfo も追随する（直書きしていない）');
}

# --- 未知のメソッドは -32601 ---
{
    my $res = MTMCP::Protocol::dispatch(undef, {
        jsonrpc => '2.0', id => 1, method => 'no/such/method',
    });
    is($res->{error}{code}, -32601, '未知のメソッドは -32601');
}

# --- notifications/initialized は応答しない ---
{
    my $res = MTMCP::Protocol::dispatch(undef, {
        jsonrpc => '2.0', method => 'notifications/initialized',
    });
    is($res, undef, 'notifications/initialized は応答を返さない');
}

# ---------------------------------------------------------------------------
# App::handle の入口。認証は通った前提で確かめたいので、_check_auth だけ差し替える。
# ---------------------------------------------------------------------------

{
    no warnings 'redefine';
    *MTMCP::App::_check_auth = sub { return undef };
}

{
    package FakeApp;
    sub new {
        my ($class, %args) = @_;
        return bless { %args, headers => {}, code => undef }, $class;
    }
    sub request_method  { $_[0]{method} // 'POST' }
    sub get_header      { $_[0]{content_type} }
    sub request_content { $_[0]{body} }
    sub param           { return undef }
    sub response_code   { my $s = shift; $s->{code} = shift if @_; $s->{code} }
    sub set_header      { my ($s, $k, $v) = @_; $s->{headers}{$k} = $v }
}

sub _post {
    my ($body) = @_;
    my $app = FakeApp->new(content_type => 'application/json', body => $body);
    my $out = MTMCP::App::handle($app, 'mcp');
    return ($app, $out);
}

# --- バッチ（配列）は 500 ではなく -32600 Invalid Request ---
{
    my ($app, $out) = _post('[{"jsonrpc":"2.0","id":1,"method":"ping"}]');

    is($app->response_code, 400, 'バッチは 400');
    my $res = $json->decode($out);
    is($res->{error}{code}, -32600, 'バッチは -32600 Invalid Request');
    is($res->{id}, undef, 'id は null');
}

# --- オブジェクトでも配列でもない JSON も -32600 ---
{
    my ($app, $out) = _post('"just a string"');
    is($app->response_code, 400, 'スカラー JSON は 400');
    is($json->decode($out)->{error}{code}, -32600, 'スカラー JSON は -32600');
}

# --- 壊れた JSON は従来どおり -32700 ---
{
    my ($app, $out) = _post('{not json');
    is($app->response_code, 400, '壊れた JSON は 400');
    is($json->decode($out)->{error}{code}, -32700, '壊れた JSON は -32700 Parse error');
}

# --- 通知は本文なしの 202（Streamable HTTP の仕様）---
{
    my ($app, $out) = _post('{"jsonrpc":"2.0","method":"notifications/initialized"}');

    is($app->response_code, 202, '通知は 202 Accepted');
    is($out, '', '通知には本文を返さない');
}

# --- 通常のリクエストは 200 ---
{
    my ($app, $out) = _post('{"jsonrpc":"2.0","id":1,"method":"ping"}');

    is($app->response_code, 200, 'ping は 200');
    is_deeply($json->decode($out)->{result}, {}, 'ping の result は空オブジェクト');
}

done_testing();
