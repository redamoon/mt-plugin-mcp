package MTMCP::Tools::Template;
use strict;
use warnings;
use JSON;
use MT::Template;
use MTMCP::Perm;

# テンプレート本文をレンダリングして返すときの上限（文字数）。
# AI クライアントのコンテキストを溢れさせないためのガード。
use constant PREVIEW_MAX_CHARS => 100_000;

# template_tag_list のデフォルト取得件数。MT のタグは 700 個以上あるため
# 無条件の全件返却はコンテキストを圧迫する。
use constant TAG_LIST_DEFAULT_LIMIT => 100;

sub list {
    my ($app, $args) = @_;
    my $blog_id = $args->{blog_id} or die "blog_id is required\n";
    MTMCP::Perm::require_blog_access($app, $blog_id);
    my $keyword = $args->{keyword};
    my %terms = (blog_id => $blog_id);
    $terms{type} = $args->{type} if $args->{type};
    my @tmpls = MT::Template->load(\%terms, { sort => 'name', direction => 'ascend' });

    if ($keyword) {
        my $kw = lc $keyword;
        @tmpls = grep { index(lc($_->name // ''), $kw) >= 0 } @tmpls;
    }
    if (defined(my $offset = $args->{offset})) {
        $offset = 0 if $offset < 0;
        @tmpls = $offset < @tmpls ? splice(@tmpls, $offset) : ();
    }
    if (defined(my $limit = $args->{limit})) {
        $limit = 0 if $limit < 0;
        @tmpls = splice(@tmpls, 0, $limit);
    }

    return [ map { _to_hash($_) } @tmpls ];
}

sub create {
    my ($app, $args) = @_;
    my $blog_id = $args->{blog_id} or die "blog_id is required\n";
    my $name    = $args->{name}    or die "name is required\n";
    my $type    = $args->{type}    or die "type is required\n";
    MTMCP::Perm::require_blog_permission($app, $blog_id, 'edit_templates', 'テンプレートの編集');

    _assert_widgetset_body($type, $args);

    my $body = $args->{body} // '';
    _assert_valid($blog_id, $body, $type, $args->{skip_validation});
    _assert_outfile($type, $args->{outfile}, $args->{build_type});

    my $tmpl = MT::Template->new;
    $tmpl->blog_id($blog_id);
    $tmpl->name($name);
    $tmpl->type($type);
    $tmpl->text($body);
    _apply_optional_columns($tmpl, $args);
    $tmpl->save or die $tmpl->errstr . "\n";

    return { template_id => $tmpl->id, status => 'created', name => $tmpl->name, type => $tmpl->type };
}

sub remove {
    my ($app, $args) = @_;
    my $tmpl_id = $args->{template_id} or die "template_id is required\n";
    my $tmpl = MT::Template->load($tmpl_id) or die "Template not found: $tmpl_id\n";
    MTMCP::Perm::require_blog_permission($app, $tmpl->blog_id, 'edit_templates', 'テンプレートの編集');
    my $name = $tmpl->name;

    # テンプレート削除は MT::FileInfo のレコードは削除するが、公開済みの
    # 静的ファイル自体は残る。先にファイルパスを控えておき、DBレコード削除後
    # に実ファイルも削除する。
    require MT::FileInfo;
    my @file_paths = map { $_->file_path // () } MT::FileInfo->load({ template_id => $tmpl_id });

    $tmpl->remove or die $tmpl->errstr . "\n";

    if (@file_paths) {
        require MT::FileMgr;
        my $fmgr = eval { MT::FileMgr->new('Local') };
        if ($fmgr) {
            for my $path (@file_paths) {
                eval { $fmgr->delete($path) if $fmgr->exists($path) };
            }
        }
    }

    return { template_id => $tmpl_id, status => 'deleted', name => $name };
}

sub get {
    my ($app, $args) = @_;
    my $tmpl_id = $args->{template_id} or die "template_id is required\n";
    my $tmpl = MT::Template->load($tmpl_id) or die "Template not found: $tmpl_id\n";
    MTMCP::Perm::require_blog_access($app, $tmpl->blog_id);
    return _to_hash($tmpl, 1);
}

sub update {
    my ($app, $args) = @_;
    my $tmpl_id = $args->{template_id} or die "template_id is required\n";
    my $tmpl = MT::Template->load($tmpl_id) or die "Template not found: $tmpl_id\n";
    MTMCP::Perm::require_blog_permission($app, $tmpl->blog_id, 'edit_templates', 'テンプレートの編集');

    # body・name・type・出力設定のいずれも指定がなければ、何も変えずに終わってしまう。
    # AI の呼び出しミスを黙って成功にしないよう、明示的にエラーにする。
    my @updatable = qw(body name type outfile identifier build_type rebuild_me);
    die "更新する項目がありません（" . join(', ', @updatable) . " のいずれかを指定してください）\n"
        unless grep { defined $args->{$_} } @updatable;

    _assert_widgetset_body($args->{type} // $tmpl->type, $args);

    if (defined $args->{body}) {
        _assert_valid($tmpl->blog_id, $args->{body}, $args->{type} // $tmpl->type, $args->{skip_validation});
        $tmpl->text($args->{body});
    }
    # 出力先に関わる項目を触るときだけ検証する。既存の不備なテンプレートに対して
    # 本文だけを直したいケースまで弾いてしまわないようにするため。
    if (grep { exists $args->{$_} } qw(type outfile build_type)) {
        _assert_outfile(
            $args->{type}       // $tmpl->type,
            exists $args->{outfile}    ? $args->{outfile}    : $tmpl->outfile,
            exists $args->{build_type} ? $args->{build_type} : $tmpl->build_type,
        );
    }

    $tmpl->name($args->{name}) if defined $args->{name};
    $tmpl->type($args->{type}) if defined $args->{type};
    _apply_optional_columns($tmpl, $args);
    $tmpl->save or die $tmpl->errstr . "\n";

    return { template_id => $tmpl->id, status => 'updated', name => $tmpl->name, type => $tmpl->type };
}

# 保存せずにテンプレート構文だけを検証する。AI が本文を書いたあと、
# 保存や再構築で失敗する前に自己修正できるようにするためのツール。
sub validate {
    my ($app, $args) = @_;
    my $blog_id = $args->{blog_id} or die "blog_id is required\n";
    die "body is required\n" unless defined $args->{body};
    MTMCP::Perm::require_blog_access($app, $blog_id);

    my $errors = _compile_errors($blog_id, $args->{body}, $args->{type});
    return {
        valid  => @$errors ? JSON::false : JSON::true,
        errors => $errors,
    };
}

# テンプレートを実際にビルドして出力HTMLを返す（ファイルは書き出さない）。
# 構文が通っていても意図した内容が出るとは限らないため、AI が結果を確認する用。
#
# 任意の本文を受け取って MT テンプレートとして評価するため、テンプレートを
# 保存するのと同等の権限を要求する。特に AllowFileInclude が有効な環境では
# <mt:Include file="..."> でサーバー上のファイルを読み出せてしまうため、
# ブログへのアクセス権限だけでは不十分。
# （構文チェックのみの validate は評価を伴わないのでアクセス権限で足りる）
sub preview {
    my ($app, $args) = @_;
    my $blog_id = $args->{blog_id} or die "blog_id is required\n";
    MTMCP::Perm::require_blog_permission($app, $blog_id, 'edit_templates', 'テンプレートの編集');

    my ($body, $type);
    if (defined $args->{body}) {
        $body = $args->{body};
        $type = $args->{type} // 'index';
    }
    elsif (my $tmpl_id = $args->{template_id}) {
        my $src = MT::Template->load($tmpl_id) or die "Template not found: $tmpl_id\n";
        die "template_id (blog_id: " . $src->blog_id . ") と blog_id ($blog_id) が一致しません\n"
            unless $src->blog_id == $blog_id;
        $body = $src->text // '';
        $type = $args->{type} // $src->type;
    }
    else {
        die "body または template_id のどちらかが必要です\n";
    }

    require MT::Blog;
    my $blog = MT::Blog->load($blog_id) or die "Blog not found: $blog_id\n";

    my $tmpl = MT::Template->new;
    $tmpl->blog_id($blog_id);
    $tmpl->name('MCP preview');
    $tmpl->type($type);
    $tmpl->text($body);

    my $ctx = $tmpl->context;
    $ctx->stash('blog',    $blog);
    $ctx->stash('blog_id', $blog_id);

    # individual / archive 系テンプレートは記事コンテキストがないとビルドできない
    # タグを含むことが多いため、entry_id が渡されていればスタッシュしておく。
    if (my $entry_id = $args->{entry_id}) {
        require MT::Entry;
        my $entry = MT::Entry->load($entry_id) or die "Entry not found: $entry_id\n";
        die "entry_id (blog_id: " . $entry->blog_id . ") と blog_id ($blog_id) が一致しません\n"
            unless $entry->blog_id == $blog_id;
        $ctx->stash('entry', $entry);
    }

    my $output = $tmpl->build($ctx);
    unless (defined $output) {
        my $err = $tmpl->errstr // 'unknown error';
        die "テンプレートのビルドに失敗しました: $err\n";
    }

    my $truncated = 0;
    if (length($output) > PREVIEW_MAX_CHARS) {
        $output    = substr($output, 0, PREVIEW_MAX_CHARS);
        $truncated = 1;
    }

    return {
        output    => $output,
        length    => length($output),
        truncated => $truncated ? JSON::true : JSON::false,
        type      => $type,
    };
}

# 利用可能な MT テンプレートタグの一覧。AI が存在しないタグを書くのを防ぐため、
# プラグインが追加したタグも含めた「そのMT環境で実際に使えるタグ」を返す。
sub tag_list {
    my ($app, $args) = @_;

    # タグ一覧はブログに依存しないグローバルな情報だが、認証済みユーザーのみに
    # 返す。$app->user は MTMCP::App::_check_auth が設定している。
    die "認証されていないため、この操作を行えません\n" unless eval { $app->user };

    my %by_kind = (function => {}, block => {}, modifier => {});

    require MT::Component;
    my $tag_sets = MT::Component->registry('tags') || [];
    $tag_sets = [$tag_sets] if ref($tag_sets) eq 'HASH';

    for my $tag_set (@$tag_sets) {
        next unless ref($tag_set) eq 'HASH';
        for my $kind (keys %by_kind) {
            my $tags = $tag_set->{$kind} or next;
            next unless ref($tags) eq 'HASH';
            for my $name (keys %$tags) {
                # 'plugin' はタグではなく登録元コンポーネントへの参照。
                next if $name eq 'plugin';
                # ブロックタグの末尾 '?' は条件タグであることを示す内部マーカー。
                (my $display = $name) =~ s/\?$//;
                $by_kind{$kind}{$display} = 1;
            }
        }
    }

    my @kinds = $args->{kind} ? ($args->{kind}) : sort keys %by_kind;
    for my $kind (@kinds) {
        die "kind は function / block / modifier のいずれかを指定してください（指定値: $kind）\n"
            unless exists $by_kind{$kind};
    }

    my @tags;
    for my $kind (@kinds) {
        push @tags, map { { name => $_, kind => $kind } } keys %{ $by_kind{$kind} };
    }

    if (my $keyword = $args->{keyword}) {
        my $kw = lc $keyword;
        @tags = grep { index(lc($_->{name}), $kw) >= 0 } @tags;
    }

    @tags = sort { $a->{kind} cmp $b->{kind} || lc($a->{name}) cmp lc($b->{name}) } @tags;

    my $total = scalar @tags;
    my $limit = defined $args->{limit} ? $args->{limit} : TAG_LIST_DEFAULT_LIMIT;
    $limit = 0 if $limit < 0;
    @tags = splice(@tags, 0, $limit) if $limit < $total;

    return {
        total     => $total,
        returned  => scalar @tags,
        truncated => (scalar(@tags) < $total) ? JSON::true : JSON::false,
        tags      => \@tags,
    };
}

# ------------------------------------------------------------------
# 内部ヘルパー
# ------------------------------------------------------------------

# MT::Builder でテンプレート本文をコンパイルし、構文エラーの一覧を返す。
# MT::Template オブジェクトを渡してコンパイルすると、最初の1件で打ち切らずに
# 全エラーが $tmpl->errors に行番号付きで溜まる。
sub _compile_errors {
    my ($blog_id, $text, $type) = @_;

    my $tmpl = MT::Template->new;
    $tmpl->blog_id($blog_id);
    $tmpl->name('MCP validation');
    $tmpl->type($type // 'index');
    $tmpl->text($text);

    # タグハンドラが die する可能性があるため eval で包む。
    my $tokens = eval { $tmpl->compile };
    if ($@) {
        (my $err = $@) =~ s/ at .+ line \d+\.?\s*$//;
        chomp $err;
        return [ { message => $err, line => undef } ];
    }

    my $errors = $tmpl->errors || [];
    # トークン化自体に失敗した場合は errors が空でも errstr にメッセージが入る。
    if (!@$errors && !$tokens) {
        return [ { message => $tmpl->errstr // 'テンプレートのコンパイルに失敗しました', line => undef } ];
    }

    return [ map { { message => $_->{message}, line => $_->{line} } } @$errors ];
}

# 構文エラーがあれば die する。skip_validation が真なら検証自体を行わない。
sub _assert_valid {
    my ($blog_id, $text, $type, $skip) = @_;
    return if $skip;

    my $errors = _compile_errors($blog_id, $text, $type);
    return unless @$errors;

    my $detail = join "\n", map {
        my $line = defined $_->{line} ? " (line $_->{line})" : '';
        "  - $_->{message}$line";
    } @$errors;
    die "テンプレート構文にエラーがあります。修正してから再度保存してください"
        . "（意図的に保存する場合は skip_validation: true を指定）:\n$detail\n";
}

# widgetset の text は MT::Template::save が save_widgetset へ分岐し、
# modulesets（ウィジェットテンプレートIDのカンマ区切り）から再生成して上書きする。
# MCP が渡した body は保存されないため、指定されていれば明示的にエラーにする。
# （黙って成功を返すと AI クライアントが「更新できた」と誤認する）
sub _assert_widgetset_body {
    my ($type, $args) = @_;
    return unless ($type // '') eq 'widgetset';
    return unless defined $args->{body};
    die "type が widgetset のときは body を指定できません。"
        . "ウィジェットセットの本文は modulesets（ウィジェットテンプレートIDのカンマ区切り）から自動生成されるため、指定した body は保存されません\n";
}

# 公開されるインデックステンプレートには出力ファイル名が必須。
#
# MT::WeblogPublisher::rebuild_indexes は outfile が空のインデックステンプレートに
# 当たると、そこでループ全体を中断してエラーを返す。つまり outfile 無しのテンプレートを
# 1つ作るだけで、以後そのサイトの rebuild_site と rebuild_entry（依存再構築）が
# すべて失敗するようになる。MT の管理画面では index テンプレートの出力ファイル名は
# 必須項目なので、この状態は MCP 経由でしか作れない。作成時点で防ぐ。
#
# build_type が 0（公開しない）の場合は rebuild_indexes が outfile を見る前に
# スキップするため、対象外とする。
sub _assert_outfile {
    my ($type, $outfile, $build_type) = @_;
    return unless ($type // '') eq 'index';
    return if defined $build_type && !$build_type;
    return if defined $outfile && $outfile ne '';
    die "インデックステンプレートには outfile（出力ファイル名）が必要です。"
        . "例: outfile: \"index.html\"。"
        . "指定しないと、このサイトの rebuild_site / rebuild_entry がすべて失敗するようになります"
        . "（公開しないテンプレートとして作る場合は build_type: 0 を指定してください）\n";
}

# create / update で共通して扱う任意カラムを反映する。
sub _apply_optional_columns {
    my ($tmpl, $args) = @_;
    $tmpl->outfile($args->{outfile})       if defined $args->{outfile};
    $tmpl->identifier($args->{identifier}) if defined $args->{identifier};
    $tmpl->build_type($args->{build_type}) if defined $args->{build_type};
    $tmpl->rebuild_me($args->{rebuild_me} ? 1 : 0) if defined $args->{rebuild_me};
    return;
}

sub _to_hash {
    my ($tmpl, $full) = @_;
    my $hash = { id => $tmpl->id, name => $tmpl->name, type => $tmpl->type };
    if ($full) {
        $hash->{body}       = $tmpl->text // '';
        $hash->{blog_id}    = $tmpl->blog_id;
        $hash->{outfile}    = $tmpl->outfile;
        $hash->{identifier} = $tmpl->identifier;
        $hash->{build_type} = $tmpl->build_type;
    }
    return $hash;
}

1;
