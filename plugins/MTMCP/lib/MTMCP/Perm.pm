package MTMCP::Perm;
use strict;
use warnings;
use utf8;

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

# require_blog_access に加えて、MT の権限アクション（can_do の引数）を要求する。
# 再構築やテンプレート編集のように、単にブログへアクセスできるだけでは
# 許可すべきでない操作で使う。
#
# $action は MT の permitted_action 名（例: 'rebuild', 'edit_templates'）。
# $label は権限が足りなかったときにユーザーへ表示する日本語の権限名。
sub require_blog_permission {
    my ($app, $blog_id, $action, $label) = @_;
    require_blog_access($app, $blog_id);

    my $user = $app->user;
    return if $user->is_superuser;

    require MT::Permission;
    my $perm = MT::Permission->load({ author_id => $user->id, blog_id => $blog_id });
    # require_blog_access を通過している以上 $perm は存在するはずだが、
    # 取得できなかった場合はデフォルト拒否とする。
    die "「$label」の権限がありません（blog_id: $blog_id）\n"
        unless $perm && $perm->can_do($action);
    return;
}

# アクティビティログ閲覧。require_blog_access は blog_id=0 を拒否するため使わない。
# 戻り値:
#   undef … 追加の blog_id 制限なし（superuser / view_log）
#   [blog_id, ...] … システム全体要求時、view_blog_log のあるサイトに限定
sub require_log_view {
    my ($app, $blog_id) = @_;

    my $user = eval { $app->user };
    die "認証されていないため、この操作を行えません\n" unless $user;
    return if $user->is_superuser;

    require MT::Permission;

    my $has_view_log = 0;
    my $sys_perm = MT::Permission->load({ author_id => $user->id, blog_id => 0 });
    $has_view_log = 1 if $sys_perm && $sys_perm->can_do('view_log');

    if ($blog_id) {
        return if $has_view_log;
        my $perm = MT::Permission->load({ author_id => $user->id, blog_id => $blog_id });
        die "この操作を行う権限がありません（blog_id: $blog_id）\n"
            unless $perm && $perm->can_do('view_blog_log');
        return;
    }

    # blog_id が 0 / undef: システム全体（権限のある範囲）
    return if $has_view_log;

    my @perms = MT::Permission->load({ author_id => $user->id });
    my @blog_ids;
    for my $perm (@perms) {
        next unless $perm->blog_id;
        next unless $perm->can_do('view_blog_log');
        push @blog_ids, $perm->blog_id;
    }
    die "この操作を行う権限がありません（blog_id: 0）\n" unless @blog_ids;
    return \@blog_ids;
}

1;
