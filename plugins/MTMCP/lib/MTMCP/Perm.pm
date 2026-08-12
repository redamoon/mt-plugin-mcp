package MTMCP::Perm;
use strict;
use warnings;

# $app->user に紐づくユーザーが指定ブログへのアクセス権限を持つか検証する。
# 権限のないユーザーが他ブログのデータを操作するのを防ぐ。
#
# 互換性のため: $app->user が未設定（旧仕様のトークン、または認証を要求しない
# エンドポイント経由）の場合はチェックをスキップする。
sub require_blog_access {
    my ($app, $blog_id) = @_;
    return unless $blog_id;

    my $user = eval { $app->user };
    return unless $user;
    return if $user->is_superuser;

    require MT::Permission;
    my $perm = MT::Permission->load({ author_id => $user->id, blog_id => $blog_id });
    die "この操作を行う権限がありません（blog_id: $blog_id）\n" unless $perm;
    return;
}

1;
