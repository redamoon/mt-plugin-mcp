package MTMCP::Perm;
use strict;
use warnings;

# $app->user に紐づくユーザーが指定ブログへのアクセス権限を持つか検証する。
# 権限のないユーザーが他ブログのデータを操作するのを防ぐ。
#
# $blog_id が渡されなかった場合（呼び出し元が対象ブログを特定できなかった
# 場合）と、$app->user が未設定の場合はどちらも「権限なし」として拒否する
# （デフォルト拒否。MTMCP::App::_check_auth は認証済みリクエストに必ず
# $app->user を設定するため、通常はここで未設定になることはない）。
sub require_blog_access {
    my ($app, $blog_id) = @_;
    die "blog_id を特定できないため、この操作を行えません\n" unless $blog_id;

    my $user = eval { $app->user };
    die "認証されていないため、この操作を行えません\n" unless $user;
    return if $user->is_superuser;

    require MT::Permission;
    my $perm = MT::Permission->load({ author_id => $user->id, blog_id => $blog_id });
    die "この操作を行う権限がありません（blog_id: $blog_id）\n" unless $perm;
    return;
}

1;
