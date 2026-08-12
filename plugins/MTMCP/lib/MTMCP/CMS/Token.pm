package MTMCP::CMS::Token;
use strict;
use warnings;
use MTMCP::Auth;

# 管理画面からのトークン発行は、MT にログイン中の本人（スーパーユーザーに限らない）
# に紐づくトークンを MTMCP::Auth 経由で発行する。ログイン認証（POST /v4/mcp/authenticate）
# と同じ仕組みに統合されているため、権限まわりの挙動は一致する。

sub generate {
    my ($app) = @_;

    $app->set_header('Content-Type' => 'application/json; charset=UTF-8');
    require JSON;
    my $json = JSON->new->ascii;

    my $user = $app->user;
    unless ($user && !$user->is_anonymous) {
        return $json->encode({ error => 'Permission denied' });
    }
    my $xhr = $app->get_header('X-Requested-With') // '';
    unless ($xhr eq 'XMLHttpRequest') {
        return $json->encode({ error => 'Invalid request' });
    }

    my $token = eval { MTMCP::Auth::issue_token_for($user) };
    unless ($token) {
        warn "MTMCP: token generation failed: $@";
        return $json->encode({ error => 'Could not generate token' });
    }

    return $json->encode({ token => $token, mcp_url => _mcp_url($app) });
}

# Cursor / Claude Desktop の mcp.json にそのまま貼れる完成形JSONを組み立てる
# ため、MCP エンドポイント（mt-data-api.cgi 側）の絶対URLをサーバー側で
# 算出する。CMSアプリ（mt.cgi）自身のURLからは組み立てられないため、
# MT の設定値（CGIPath / DataAPIScript）から直接構築する。
# CGIPath はホスト名を含まない相対パス（例: /cgi-bin/）を指定することも
# 許容されており、その場合は現在のリクエストのオリジン（$app->base）を
# 前置して絶対URLにする（App.pm の handle_sse が組み立てる URL と一致させる）。
sub _mcp_url {
    my ($app) = @_;
    require MT;
    my $cgi_path   = MT->config('CGIPath')      // '';
    my $da_script  = MT->config('DataAPIScript') || 'mt-data-api.cgi';
    $cgi_path =~ s{/*$}{/};

    unless ($cgi_path =~ m{^https?://}i) {
        my $base = eval { $app->base } // '';
        $base =~ s{/$}{};
        $cgi_path = '/' . $cgi_path unless $cgi_path =~ m{^/};
        $cgi_path = $base . $cgi_path;
    }

    return $cgi_path . $da_script . '/v4/mcp';
}

sub show {
    my ($app) = @_;

    my $user = $app->user;
    return $app->permission_denied unless $user && !$user->is_anonymous;

    my $param = {
        magic_token => $app->current_magic,
    };

    if ($app->request_method eq 'POST') {
        return $app->error('Invalid request') unless $app->validate_magic;

        my $token = eval { MTMCP::Auth::issue_token_for($user) };
        unless ($token) {
            warn "MTMCP: token generation failed: $@";
            return $app->error('トークンの発行に失敗しました。しばらくしてから再度お試しください。');
        }

        $param->{token} = $token;

        require JSON;
        $param->{config_json} = JSON->new->utf8(0)->pretty->canonical->encode({
            mcpServers => {
                'movable-type' => {
                    type    => 'sse',
                    url     => _mcp_url($app),
                    headers => { Authorization => "Bearer $token" },
                },
            },
        });
    }

    return $app->load_tmpl('mcp_token.tmpl', $param);
}

1;
