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

    my $user = $app->user;
    unless ($user && !$user->is_anonymous) {
        return '{"error":"Permission denied"}';
    }
    my $xhr = $app->get_header('X-Requested-With') // '';
    unless ($xhr eq 'XMLHttpRequest') {
        return '{"error":"Invalid request"}';
    }

    my $token = eval { MTMCP::Auth::issue_token_for($user) };
    return '{"error":"' . ($@ || 'unknown error') . '"}' unless $token;

    require JSON;
    return JSON->new->ascii->encode({ token => $token });
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
        return $app->error('トークンの保存に失敗しました: ' . $@) unless $token;

        $param->{token} = $token;
    }

    return $app->load_tmpl('mcp_token.tmpl', $param);
}

1;
