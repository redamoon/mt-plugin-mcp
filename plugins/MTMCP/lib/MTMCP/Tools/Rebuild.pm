package MTMCP::Tools::Rebuild;
use strict;
use warnings;
use MTMCP::Perm;

# 再構築（publish）系ツール。
#
# MT の再構築は対象範囲によって実行時間が大きく変わる。MCP は HTTP リクエスト上で
# 動くため、サイト全体の再構築は Web サーバー / CGI のタイムアウトに達する可能性が
# ある。そのため範囲を絞ったツール（テンプレート単体・記事単体）を用意し、
# rebuild_site は最後の手段として使ってもらう方針にしている。

# 再構築は MT の「サイトの再構築」権限（permitted_action: rebuild）を要求する。
sub _require_rebuild_perm {
    my ($app, $blog_id) = @_;
    MTMCP::Perm::require_blog_permission($app, $blog_id, 'rebuild', 'サイトの再構築');
}

sub _load_blog {
    my ($blog_id) = @_;
    require MT::Blog;
    my $blog = MT::Blog->load($blog_id) or die "Blog not found: $blog_id\n";
    die "ブログの公開パス（site_path）が設定されていないため再構築できません（blog_id: $blog_id）\n"
        unless $blog->site_path;
    return $blog;
}

sub site {
    my ($app, $args) = @_;
    my $blog_id = $args->{blog_id} or die "blog_id is required\n";
    _require_rebuild_perm($app, $blog_id);
    my $blog = _load_blog($blog_id);

    my %param = (Blog => $blog);
    $param{ArchiveType} = $args->{archive_type} if $args->{archive_type};
    $param{NoIndexes}   = 1                     if $args->{no_indexes};

    my $started = time;
    $app->rebuild(%param)
        or die _errmsg($app, 'サイトの再構築に失敗しました');

    return {
        blog_id      => $blog->id,
        blog_name    => $blog->name,
        status       => 'rebuilt',
        scope        => $args->{archive_type} ? "archive:$args->{archive_type}" : 'site',
        elapsed_sec  => time - $started,
    };
}

sub template {
    my ($app, $args) = @_;
    my $tmpl_id = $args->{template_id} or die "template_id is required\n";
    require MT::Template;
    my $tmpl = MT::Template->load($tmpl_id) or die "Template not found: $tmpl_id\n";
    _require_rebuild_perm($app, $tmpl->blog_id);
    my $blog = _load_blog($tmpl->blog_id);

    my $started = time;
    my $type = $tmpl->type // '';

    if ($type eq 'index') {
        # インデックステンプレートは1枚だけを対象に再構築できる。
        # Force を立てて「インデックスと一緒に再構築しない」設定のテンプレートも
        # 明示指定されたときは再構築する（MT 管理画面の「公開」と同じ挙動）。
        $app->rebuild_indexes(Blog => $blog, Template => $tmpl, Force => 1)
            or die _errmsg($app, 'インデックステンプレートの再構築に失敗しました');

        return {
            template_id => $tmpl->id,
            name        => $tmpl->name,
            type        => $type,
            status      => 'rebuilt',
            scope       => 'index_template',
            elapsed_sec => time - $started,
        };
    }

    # アーカイブテンプレートは、テンプレートマップで結び付けられた
    # アーカイブタイプ単位でしか再構築できない。
    require MT::TemplateMap;
    my @maps = MT::TemplateMap->load({ template_id => $tmpl->id });
    my %archive_types = map { $_->archive_type => 1 } grep { $_->build_type } @maps;

    unless (%archive_types) {
        # マップはあるが全て「公開しない」の場合と、そもそもマップが無い場合とでは
        # 原因も対処も違うため、メッセージを分ける。
        die "このテンプレートのアーカイブマップはすべて「公開しない」設定のため再構築できません。"
            . "MT 管理画面でアーカイブマップの公開方法を設定してください。\n"
            if @maps;
        die "このテンプレート（type: $type）は単体で再構築できません。"
            . "インデックステンプレート、またはアーカイブテンプレート（テンプレートマップ設定済み）を指定するか、"
            . "rebuild_site でブログ全体を再構築してください。\n";
    }

    my @rebuilt;
    for my $at (sort keys %archive_types) {
        $app->rebuild(
            Blog        => $blog,
            ArchiveType => $at,
            TemplateID  => $tmpl->id,
            NoIndexes   => 1,
        ) or die _errmsg($app, "アーカイブ（$at）の再構築に失敗しました");
        push @rebuilt, $at;
    }

    return {
        template_id   => $tmpl->id,
        name          => $tmpl->name,
        type          => $type,
        status        => 'rebuilt',
        scope         => 'archive_template',
        archive_types => \@rebuilt,
        elapsed_sec   => time - $started,
    };
}

sub entry {
    my ($app, $args) = @_;
    my $entry_id = $args->{entry_id} or die "entry_id is required\n";
    require MT::Entry;
    # スカラー load は Page も返すため、class => 'entry' で記事に限定する。
    my $entry = MT::Entry->load({ id => $entry_id, class => 'entry' })
        or die "Entry not found: $entry_id\n";
    _require_rebuild_perm($app, $entry->blog_id);
    my $blog = _load_blog($entry->blog_id);

    # 依存ページ（月別アーカイブ・カテゴリアーカイブ・インデックス）まで
    # 再構築するかどうか。省略時は記事だけでなく一覧側も更新されるよう有効にする。
    my $deps = exists $args->{build_dependencies} ? ($args->{build_dependencies} ? 1 : 0) : 1;

    my $started = time;
    $app->rebuild_entry(
        Entry             => $entry,
        Blog              => $blog,
        BuildDependencies => $deps,
    ) or die _errmsg($app, '記事の再構築に失敗しました');

    return {
        entry_id           => $entry->id,
        title              => $entry->title,
        status             => 'rebuilt',
        scope              => 'entry',
        build_dependencies => $deps,
        elapsed_sec        => time - $started,
    };
}

sub content_data {
    my ($app, $args) = @_;
    my $cd_id = $args->{content_data_id} or die "content_data_id is required\n";
    require MT::ContentData;
    my $cd = MT::ContentData->load($cd_id) or die "ContentData not found: $cd_id\n";
    _require_rebuild_perm($app, $cd->blog_id);
    my $blog = _load_blog($cd->blog_id);

    my $deps = exists $args->{build_dependencies} ? ($args->{build_dependencies} ? 1 : 0) : 1;

    my $started = time;
    $app->rebuild_content_data(
        ContentData       => $cd,
        Blog              => $blog,
        BuildDependencies => $deps,
    ) or die _errmsg($app, 'コンテンツデータの再構築に失敗しました');

    return {
        content_data_id    => $cd->id,
        status             => 'rebuilt',
        scope              => 'content_data',
        build_dependencies => $deps,
        elapsed_sec        => time - $started,
    };
}

# MT 側のエラー文字列を添えた die 用メッセージを組み立てる。
sub _errmsg {
    my ($app, $prefix) = @_;
    my $err = eval { $app->errstr };
    return $err ? "$prefix: $err\n" : "$prefix\n";
}

1;
