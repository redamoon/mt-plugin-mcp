use strict;
use warnings;
use utf8;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../plugins/MTMCP/lib";

use JSON;
use MT;
use MT::Author;
use MTMCP::Protocol;
use MTMCP::App;
use MTMCP::CMS::Token;

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
    is($res->{result}{protocolVersion}, '2025-06-18', 'Streamable HTTP の protocolVersion を返す');
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
# App::handle の入口。MT のスタブで発行したトークンを使う。
# ---------------------------------------------------------------------------

delete local $ENV{REDIRECT_HTTP_AUTHORIZATION};
my $author = MT::Author->new;
$author->save or die $author->errstr;
my $token = MTMCP::Auth::issue_token_for($author);

{
    package FakeApp;
    sub new {
        my ($class, %args) = @_;
        return bless { %args, headers => {}, code => undef }, $class;
    }
    sub request_method  { $_[0]{method} // 'POST' }
    sub get_header      { $_[0]{request_headers}{$_[1]} }
    sub request_content { $_[0]{body} }
    sub param           { return undef }
    sub base            { 'https://mt.example.test' }
    sub config          { $_[0] }
    sub DataAPICORSAllowOrigin { $_[0]{allowed_origins} }
    sub user            { my $s = shift; $s->{user} = shift if @_; $s->{user} }
    sub response_code   { my $s = shift; $s->{code} = shift if @_; $s->{code} }
    sub set_header      { my ($s, $k, $v) = @_; $s->{headers}{$k} = $v }
    sub current_magic   { 'test-magic' }
    sub validate_magic  { 1 }
    sub load_tmpl       { $_[2] }
}

sub _post {
    my ($body, $headers) = @_;
    my $app = FakeApp->new(body => $body, request_headers => {
        'Content-Type'  => 'application/json',
        'Authorization' => "Bearer $token",
        %{ $headers // {} },
    });
    my $out = MTMCP::App::handle($app);
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
    my ($app, $out) = _post('{"jsonrpc":"2.0","id":1,"method":"ping"}', {
        'MCP-Protocol-Version' => '2025-06-18',
    });
    is($app->response_code, 200, 'ping は 200');
    is_deeply($json->decode($out)->{result}, {}, 'ping の result は空オブジェクト');
    is($app->user, $author, 'Bearer トークンが紐づくユーザーで処理する');
}

{
    my ($app) = _post('{"jsonrpc":"2.0","id":1,"method":"ping"}', {
        'MCP-Protocol-Version' => 'unsupported',
    });
    is($app->response_code, 400, '未対応の MCP-Protocol-Version は 400');
}

{
    my $app = FakeApp->new(method => 'GET');
    MTMCP::App::handle_get($app);
    is($app->response_code, 405, 'GET は 405');
    is($app->{headers}{Allow}, 'POST, OPTIONS', 'Allow は POST と OPTIONS');
    like($app->{headers}{'Content-Type'}, qr{^application/json}, 'GET は JSON エラーを返す');
}

{
    my ($app) = _post('{"jsonrpc":"2.0","id":1,"method":"ping"}', {
        'Authorization'      => undef,
        'X-MT-Authorization' => "MTAuth accessToken=$token",
    });
    is($app->response_code, 401, 'X-MT-Authorization だけでは認証しない');
    like($app->{headers}{'WWW-Authenticate'}, qr/^Bearer .*resource_metadata=/,
        'Bearer が無い場合は OAuth の discovery 情報を返す');
}

{
    local $ENV{REDIRECT_HTTP_AUTHORIZATION} = "Bearer $token";
    my ($app) = _post('{"jsonrpc":"2.0","id":1,"method":"ping"}', { Authorization => undef });
    is($app->response_code, 200, 'Apache の RewriteRule 経由で Bearer 認証できる');
}

{
    my ($app) = _post('{"jsonrpc":"2.0","id":1,"method":"ping"}', {
        Origin => 'https://other.example.test',
    });
    is($app->response_code, 403, '許可されていない Origin の POST は 403');

    my $get = FakeApp->new(method => 'GET', request_headers => { Origin => 'null' });
    MTMCP::App::handle_get($get);
    is($get->response_code, 403, '無効な Origin の GET は 403');

    my $preflight = FakeApp->new(
        method => 'OPTIONS',
        request_headers => { Origin => 'https://browser.example.test' },
        allowed_origins => 'https://other.example.test, https://browser.example.test',
    );
    is(MTMCP::App::handle_options($preflight), '', 'プリフライト応答は本文なし');
    is($preflight->response_code, 204, '明示的に許可した Origin の OPTIONS は 204');
    like($preflight->{headers}{'Access-Control-Allow-Headers'}, qr/\bMCP-Protocol-Version\b/,
        'プリフライトで MCP-Protocol-Version を許可する');

    my ($same_origin) = _post('{"jsonrpc":"2.0","id":1,"method":"ping"}', {
        Origin => 'https://mt.example.test',
    });
    is($same_origin->response_code, 200, '同一 Origin の POST は 200');
}

{
    no warnings qw(once redefine);
    local *MT::Author::is_anonymous = sub { 0 };
    local *MT::config = sub {
        my %settings = (CGIPath => '/mt/', DataAPIScript => 'data.cgi');
        return $settings{$_[1]};
    };
    my $app = FakeApp->new(user => $author, request_headers => {
        'X-Requested-With' => 'XMLHttpRequest',
    });
    my $param = MTMCP::CMS::Token::show($app);
    my $generated = $json->decode(MTMCP::CMS::Token::generate($app));
    my $url = 'https://mt.example.test/mt/data.cgi/v4/mcp';
    is($generated->{mcp_url}, $url, 'トークン発行 API の mcp_url は Data API の URL');
    for my $output (
        [$json->decode($param->{config_json}), $param->{token}, 'トークン発行画面'],
        [$generated->{mcp_config}, $generated->{token}, 'プラグイン設定画面'],
    ) {
        my ($config, $issued_token, $screen) = @$output;
        is_deeply($config, { mcpServers => { 'movable-type' => {
            type    => 'http',
            url     => $url,
            headers => { Authorization => "Bearer $issued_token" },
        } } }, "$screen は HTTP 用設定を出す");
    }
}

done_testing();
