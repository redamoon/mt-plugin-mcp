package MTMCP::CMS::Token;
use strict;
use warnings;
use Digest::SHA qw(sha256_hex);

sub generate {
    my ($app) = @_;

    $app->set_header('Content-Type' => 'application/json; charset=UTF-8');

    my $user = $app->user;
    unless ($user && $user->is_superuser) {
        return '{"error":"Permission denied"}';
    }
    my $xhr = $app->get_header('X-Requested-With') // '';
    unless ($xhr eq 'XMLHttpRequest') {
        return '{"error":"Invalid request"}';
    }

    my $token = sha256_hex(rand() . time() . $$ . int(rand(1_000_000)));

    require MT::Session;
    my $session = MT::Session->new;
    $session->id($token);
    $session->kind('DA');
    $session->start(time());
    $session->duration(604800);
    $session->save
        or return '{"error":"' . ($session->errstr // 'unknown') . '"}';

    require JSON;
    return JSON->new->ascii->encode({ token => $token });
}

sub show {
    my ($app) = @_;

    my $user = $app->user;
    return $app->permission_denied unless $user && $user->is_superuser;

    my $param = {
        magic_token => $app->current_magic,
    };

    if ($app->request_method eq 'POST') {
        return $app->error('Invalid request') unless $app->validate_magic;

        my $token = sha256_hex(rand() . time() . $$ . int(rand(1_000_000)));

        require MT::Session;
        my $session = MT::Session->new;
        $session->id($token);
        $session->kind('DA');
        $session->start(time());
        $session->duration(604800);    # 7日
        $session->save
            or return $app->error('トークンの保存に失敗しました: ' . $session->errstr);

        $param->{token} = $token;
    }

    return $app->load_tmpl('mcp_token.tmpl', $param);
}

1;
