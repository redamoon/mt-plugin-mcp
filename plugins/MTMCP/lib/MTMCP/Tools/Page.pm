package MTMCP::Tools::Page;
use strict;
use warnings;
use utf8;
use JSON;
use MT::Page;
use MT::Placement;
use MT::Folder;
use MTMCP::Perm;
use MTMCP::Args;

# キーワード検索時にPerl側でスキャンする最大件数。DB側でのLIKE検索ではなく
# 直近のレコードをこの件数までロードしてから絞り込むため、これを超えて
# 古いレコードにしかマッチしないキーワードは検出できない（既知の制約）。
use constant KEYWORD_SCAN_LIMIT => 2000;
use constant PREVIEW_MAX_CHARS  => 100_000;


# Data API と同様、DeleteFilesAtRebuild のときだけ公開アーカイブを消す。
# page_delete と entry_delete で方針を揃える（片方だけ変えないこと）。
sub _maybe_remove_entry_archive_file {
    my ($app, $obj, $archive_type) = @_;
    return unless $app && $obj && defined $archive_type && $archive_type ne '';
    my $cfg = ($app->can('config') ? eval { $app->config } : undef);
    return unless $cfg && eval { $cfg->DeleteFilesAtRebuild };

    my $pub = ($app->can('publisher') ? eval { $app->publisher } : undef);
    if (!$pub) {
        require MT::Blog;
        my $blog = eval { MT::Blog->load($obj->blog_id) };
        $pub = ($blog && $blog->can('publisher')) ? eval { $blog->publisher } : undef;
    }
    return unless $pub && $pub->can('remove_entry_archive_file');
    $pub->remove_entry_archive_file(
        Entry       => $obj,
        ArchiveType => $archive_type,
    );
}

sub _load_page {
    my ($page_id) = @_;
    return MT::Page->load({ id => $page_id, class => 'page' });
}

sub _require_manage_pages {
    my ($app, $blog_id) = @_;
    MTMCP::Perm::require_blog_permission($app, $blog_id, 'manage_pages', 'ページの管理');
}

sub list {
    my ($app, $args) = @_;
    my $blog_id = $args->{blog_id} or die "blog_id is required\n";
    _require_manage_pages($app, $blog_id);
    my $limit   = $args->{limit}   // 20;
    my $offset  = $args->{offset}  // 0;
    my $status  = $args->{status}  // 'publish';
    my $keyword = $args->{keyword};

    my %terms = (blog_id => $blog_id);
    $terms{status} = MT::Entry::RELEASE() if $status eq 'publish';
    $terms{status} = MT::Entry::HOLD()    if $status eq 'draft';

    my %id_ok;
    my $filter_folder = $args->{folder_id} ? 1 : 0;
    if ($filter_folder) {
        my $folder_id = $args->{folder_id};
        MT::Folder->load({ id => $folder_id, blog_id => $blog_id, class => 'folder' })
            or die "Folder not found\n";
        my @placements = MT::Placement->load({ category_id => $folder_id });
        %id_ok = map { $_->entry_id => 1 } @placements;
        return [] unless %id_ok;
    }

    my %load_opts = ( sort => 'modified_on', direction => 'descend' );
    if ($keyword || $filter_folder) {
        $load_opts{limit} = KEYWORD_SCAN_LIMIT if $keyword;
    }
    else {
        $load_opts{limit}  = $limit;
        $load_opts{offset} = $offset;
    }

    my @pages = MT::Page->load(\%terms, \%load_opts);
    @pages = grep { $id_ok{ $_->id } } @pages if $filter_folder;

    if ($keyword) {
        my $kw = lc $keyword;
        @pages = grep {
            index(lc($_->title // ''), $kw) >= 0
                || index(lc($_->text // ''), $kw) >= 0
        } @pages;
    }
    if ($keyword || $filter_folder) {
        @pages = splice(@pages, $offset, $limit);
    }

    return [ map { _to_hash($_) } @pages ];
}

sub get {
    my ($app, $args) = @_;
    my $page_id = $args->{page_id} or die "page_id is required\n";
    my $page = _load_page($page_id) or die "Page not found: $page_id\n";
    _require_manage_pages($app, $page->blog_id);
    return _to_hash($page, 1);
}

sub create {
    my ($app, $args) = @_;
    my $blog_id = $args->{blog_id} or die "blog_id is required\n";
    my $title   = $args->{title}   or die "title is required\n";
    _require_manage_pages($app, $blog_id);

    my $page = MT::Page->new;
    $page->blog_id($blog_id);
    $page->title($title);
    $page->text($args->{body} // '');
    $page->status(($args->{status} // 'draft') eq 'publish' ? MT::Entry::RELEASE() : MT::Entry::HOLD());
    my $author_id = $args->{author_id};
    unless ($author_id) {
        my $user = eval { $app->user };
        $author_id = ($user && $user->id && !$user->is_anonymous) ? $user->id : 1;
    }
    $page->author_id($author_id);

    if ($args->{folder_id}) {
        my $folder = MT::Folder->load({ id => $args->{folder_id}, class => 'folder' })
            or die "'folder_id' はフォルダである必要があります\n";
        die "'folder_id' はフォルダである必要があります\n"
            unless $folder->blog_id == $blog_id;
    }

    if (defined $args->{basename} && $args->{basename} ne '') {
        $page->basename($args->{basename});
        if (MT::Page->exist({ blog_id => $blog_id, basename => $page->basename })) {
            require MT::Util;
            $page->basename(MT::Util::make_unique_basename($page));
        }
    }

    $page->save or die $page->errstr . "\n";
    _set_folder($page, $args->{folder_id}) if $args->{folder_id};
    return { page_id => $page->id, status => 'created', title => $page->title };
}

sub update {
    my ($app, $args) = @_;
    my $page_id = $args->{page_id} or die "page_id is required\n";
    my $page = _load_page($page_id) or die "Page not found: $page_id\n";
    _require_manage_pages($app, $page->blog_id);

    my @updatable = qw(title body status folder_id basename);
    die "更新する項目がありません（" . join(', ', @updatable) . " のいずれかを指定してください）\n"
        unless grep { exists $args->{$_} } @updatable;

    $page->title($args->{title})       if defined $args->{title};
    $page->text($args->{body})         if defined $args->{body};
    $page->basename($args->{basename}) if defined $args->{basename};
    if (defined $args->{status}) {
        $page->status($args->{status} eq 'publish' ? MT::Entry::RELEASE() : MT::Entry::HOLD());
    }
    $page->save or die $page->errstr . "\n";

    if (exists $args->{folder_id}) {
        my $fid = $args->{folder_id};
        if (!defined $fid || !$fid) {
            _set_folder($page, undef);
        }
        else {
            _set_folder($page, $fid);
        }
    }

    return { page_id => $page->id, status => 'updated', title => $page->title };
}

sub remove {
    my ($app, $args) = @_;
    my $page_id = $args->{page_id} or die "page_id is required\n";
    MTMCP::Args::require_confirm($args, "固定ページを削除する取り消せない操作です");
    my $page = _load_page($page_id) or die "Page not found: $page_id\n";
    _require_manage_pages($app, $page->blog_id);
    my $title = $page->title;
    _maybe_remove_entry_archive_file($app, $page, 'Page');
    $page->remove or die $page->errstr . "\n";
    return { page_id => $page_id, status => 'deleted', title => $title };
}

sub preview {
    my ($app, $args) = @_;

    my $page;
    if (my $page_id = $args->{page_id}) {
        $page = _load_page($page_id) or die "Page not found: $page_id\n";
        $page->text($args->{body}) if defined $args->{body};
    }
    elsif (my $blog_id = $args->{blog_id}) {
        $page = MT::Page->new;
        $page->blog_id($blog_id);
        $page->title($args->{title} // '');
        $page->text($args->{body} // '');
    }
    else {
        die "page_id または blog_id が必要です\n";
    }

    my $blog_id = $page->blog_id;
    _require_manage_pages($app, $blog_id);

    require MT::Blog;
    my $blog = MT::Blog->load($blog_id) or die "Blog not found: $blog_id\n";

    require MT::TemplateMap;
    my $map = MT::TemplateMap->load({
        archive_type => 'Page',
        is_preferred => 1,
        blog_id      => $blog_id,
    }) or die "Page アーカイブテンプレートが見つかりません\n";

    require MT::Template;
    my $tmpl = MT::Template->load($map->template_id)
        or die "Page アーカイブテンプレートが見つかりません\n";

    my $ctx = $tmpl->context;
    $ctx->stash('blog',  $blog);
    $ctx->stash('entry', $page);

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
        type      => 'page',
    };
}

sub _set_folder {
    my ($page, $folder_id) = @_;
    MT::Placement->remove({ entry_id => $page->id });
    return unless $folder_id;

    my $folder = MT::Folder->load({ id => $folder_id, class => 'folder' })
        or die "'folder_id' はフォルダである必要があります\n";
    die "'folder_id' はフォルダである必要があります\n"
        unless $folder->blog_id == $page->blog_id;

    my $p = MT::Placement->new;
    $p->entry_id($page->id);
    $p->blog_id($page->blog_id);
    $p->category_id($folder_id);
    $p->is_primary(1);
    $p->save or die $p->errstr . "\n";
}

sub _to_hash {
    my ($page, $full) = @_;
    my $hash = {
        id          => $page->id,
        title       => $page->title,
        status      => $page->status == MT::Entry::RELEASE() ? 'publish' : 'draft',
        authored_on => $page->authored_on,
        permalink   => eval { $page->permalink } // '',
    };
    if ($full) {
        $hash->{body}     = $page->text      // '';
        $hash->{excerpt}  = $page->excerpt   // '';
        $hash->{more}     = $page->text_more // '';
        $hash->{basename} = $page->basename;
    }
    if (my $folder = eval { $page->folder }) {
        $hash->{folder} = { id => $folder->id, label => $folder->label };
    }
    return $hash;
}

1;
