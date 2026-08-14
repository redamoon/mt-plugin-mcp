package MTMCP::Tools::Entry;
use strict;
use warnings;
use utf8;
use JSON;
use MT::Entry;
use MT::Placement;
use MTMCP::Perm;
use MTMCP::Search;

use constant PREVIEW_MAX_CHARS => 100_000;

sub list {
    my ($app, $args) = @_;
    my $blog_id = $args->{blog_id} or die "blog_id is required\n";
    MTMCP::Perm::require_blog_access($app, $blog_id);
    my $limit   = $args->{limit}   // 20;
    my $offset  = $args->{offset}  // 0;
    my $status  = $args->{status}  // 'publish';
    my $keyword = $args->{keyword};
    my %terms = (blog_id => $blog_id);
    $terms{status} = MT::Entry::RELEASE() if $status eq 'publish';
    $terms{status} = MT::Entry::HOLD()    if $status eq 'draft';

    my %load_opts = (
        sort      => 'authored_on',
        direction => 'descend',
        limit     => $limit,
        offset    => $offset,
    );
    my $load_terms = MTMCP::Search::and_like_or(\%terms, $keyword, 'title', 'text');
    my @entries = MT::Entry->load($load_terms, \%load_opts);

    return [ map { _to_hash($_) } @entries ];
}

# mt_entry は Entry と Page で共有される。スカラー load / { id => $id } は
# class フィルタを通さないため、Page ID でもオブジェクトが返る。

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

sub _load_entry {
    my ($entry_id) = @_;
    return MT::Entry->load({ id => $entry_id, class => 'entry' });
}

sub remove {
    my ($app, $args) = @_;
    my $entry_id = $args->{entry_id} or die "entry_id is required\n";
    my $entry = _load_entry($entry_id) or die "Entry not found: $entry_id\n";
    MTMCP::Perm::require_blog_access($app, $entry->blog_id);
    my $title = $entry->title;
    _maybe_remove_entry_archive_file($app, $entry, 'Individual');
    $entry->remove or die $entry->errstr . "\n";
    return { entry_id => $entry_id, status => 'deleted', title => $title };
}

sub get {
    my ($app, $args) = @_;
    my $entry_id = $args->{entry_id} or die "entry_id is required\n";
    my $entry = _load_entry($entry_id) or die "Entry not found: $entry_id\n";
    MTMCP::Perm::require_blog_access($app, $entry->blog_id);
    return _to_hash($entry, 1);
}

sub create {
    my ($app, $args) = @_;
    my $blog_id = $args->{blog_id} or die "blog_id is required\n";
    my $title   = $args->{title}   or die "title is required\n";
    MTMCP::Perm::require_blog_access($app, $blog_id);
    my $entry = MT::Entry->new;
    $entry->blog_id($blog_id);
    $entry->title($title);
    $entry->text($args->{body} // '');
    $entry->status(($args->{status}//'draft') eq 'publish' ? MT::Entry::RELEASE() : MT::Entry::HOLD());
    my $author_id = $args->{author_id};
    unless ($author_id) {
        my $user = eval { $app->user };
        $author_id = ($user && $user->id && !$user->is_anonymous) ? $user->id : 1;
    }
    $entry->author_id($author_id);
    $entry->save or die $entry->errstr . "\n";
    _set_categories($entry, $args->{category_ids}) if $args->{category_ids};
    return { entry_id => $entry->id, status => 'created', title => $entry->title };
}

sub update {
    my ($app, $args) = @_;
    my $entry_id = $args->{entry_id} or die "entry_id is required\n";
    my $entry = _load_entry($entry_id) or die "Entry not found: $entry_id\n";
    MTMCP::Perm::require_blog_access($app, $entry->blog_id);
    $entry->title($args->{title}) if defined $args->{title};
    $entry->text($args->{body})   if defined $args->{body};
    if (defined $args->{status}) {
        $entry->status($args->{status} eq 'publish' ? MT::Entry::RELEASE() : MT::Entry::HOLD());
    }
    $entry->save or die $entry->errstr . "\n";
    return { entry_id => $entry->id, status => 'updated', title => $entry->title };
}

# Individual アーカイブをメモリ上でビルドする。公開ファイルは書かない。
# MT::CMS::Entry::_build_entry_preview / Data API _preview_common / rebuild_entry は使わない。
sub preview {
    my ($app, $args) = @_;
    my $blog_id = $args->{blog_id} or die "blog_id is required\n";
    MTMCP::Perm::require_blog_permission($app, $blog_id, 'create_post', '記事の作成');

    my $entry_id   = $args->{entry_id};
    my $has_fields = defined $args->{body} || defined $args->{title};
    die "entry_id または body / title が必要です\n"
        unless $entry_id || $has_fields;

    require MT::Blog;
    my $blog = MT::Blog->load($blog_id) or die "Blog not found: $blog_id\n";

    my $entry;
    if ($entry_id) {
        $entry = _load_entry($entry_id) or die "Entry not found: $entry_id\n";
        die "entry_id (blog_id: " . $entry->blog_id . ") と blog_id ($blog_id) が一致しません\n"
            unless $entry->blog_id == $blog_id;
        my $preview = eval { $entry->clone };
        $preview = bless { %$entry }, ref($entry) unless $preview;
        $preview->title($args->{title})       if defined $args->{title};
        $preview->text($args->{body})         if defined $args->{body};
        $preview->text_more($args->{more})    if defined $args->{more};
        $preview->excerpt($args->{excerpt})   if defined $args->{excerpt};
        $preview->convert_breaks($args->{convert_breaks}) if defined $args->{convert_breaks};
        if (defined $args->{status}) {
            $preview->status($args->{status} eq 'publish' ? MT::Entry::RELEASE() : MT::Entry::HOLD());
        }
        $entry = $preview;
    }
    else {
        $entry = MT::Entry->new;
        $entry->id(-1);
        $entry->blog_id($blog_id);
        $entry->title($args->{title} // '');
        $entry->text($args->{body} // '');
        $entry->text_more($args->{more})  if defined $args->{more};
        $entry->excerpt($args->{excerpt}) if defined $args->{excerpt};
        $entry->convert_breaks(
            defined $args->{convert_breaks} ? $args->{convert_breaks} : $blog->convert_paras
        );
        if (defined $args->{status}) {
            $entry->status($args->{status} eq 'publish' ? MT::Entry::RELEASE() : MT::Entry::HOLD());
        }
        else {
            $entry->status(MT::Entry::HOLD());
        }
        my ( $sec, $min, $hour, $day, $mon, $year ) = localtime;
        $entry->authored_on(
            sprintf(
                '%04d%02d%02d%02d%02d%02d',
                $year + 1900, $mon + 1, $day, $hour, $min, $sec
            )
        );
    }

    _stash_preview_categories($entry, $args->{category_ids}) if $args->{category_ids};

    require MT::TemplateMap;
    my $map = MT::TemplateMap->load({
        archive_type => 'Individual',
        is_preferred => 1,
        blog_id      => $blog_id,
    }) or die "記事アーカイブテンプレートが見つかりません\n";

    require MT::Template;
    my $tmpl = MT::Template->load($map->template_id)
        or die "記事アーカイブテンプレートが見つかりません\n";

    my $ctx = $tmpl->context;
    $ctx->stash('blog',                 $blog);
    $ctx->stash('entry',                $entry);
    $ctx->stash('current_archive_type', 'Individual');
    $ctx->stash('current_timestamp',    $entry->authored_on);
    $ctx->stash('preview_template',     1);

    eval {
        my $pub = ( $blog->can('publisher') ) ? $blog->publisher : undef;
        return unless $pub && $pub->can('archiver');
        my $archiver = $pub->archiver('Individual');
        return unless $archiver && $archiver->can('template_params');
        my $vars = {};
        $archiver->template_params($vars);
        if ( $ctx->can('var') ) {
            $ctx->var( $_, $vars->{$_} ) for keys %$vars;
        }
        1;
    };

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

    my $id = $entry->id;
    return {
        output    => $output,
        length    => length($output),
        truncated => $truncated ? JSON::true : JSON::false,
        type      => 'individual',
        entry_id  => ( defined $id && $id > 0 ) ? $id : undef,
        saved     => JSON::false,
    };
}

sub _stash_preview_categories {
    my ( $entry, $cat_ids ) = @_;
    return unless $cat_ids && ref $cat_ids eq 'ARRAY' && @$cat_ids;
    require MT::Category;
    my @cats;
    for my $cid (@$cat_ids) {
        my $cat = MT::Category->load( { id => $cid, class => 'category' } );
        $cat ||= MT::Category->load($cid);
        push @cats, $cat if $cat;
    }
    return unless @cats;
    return unless $entry->can('cache_property');
    $entry->cache_property( 'category',   undef, $cats[0] );
    $entry->cache_property( 'categories', undef, \@cats );
}

sub _to_hash {
    my ($entry, $full) = @_;
    my $hash = {
        id          => $entry->id,
        title       => $entry->title,
        status      => $entry->status == MT::Entry::RELEASE() ? 'publish' : 'draft',
        authored_on => $entry->authored_on,
        permalink   => eval { $entry->permalink } // '',
    };
    if ($full) {
        $hash->{body}    = $entry->text      // '';
        $hash->{excerpt} = $entry->excerpt   // '';
        $hash->{more}    = $entry->text_more // '';
    }
    my @placements = MT::Placement->load({ entry_id => $entry->id });
    if (@placements) {
        require MT::Category;
        $hash->{categories} = [
            map { my $c = MT::Category->load($_->category_id); $c ? { id => $c->id, label => $c->label } : () }
            @placements
        ];
    }
    return $hash;
}

sub _set_categories {
    my ($entry, $cat_ids) = @_;
    MT::Placement->remove({ entry_id => $entry->id });
    my $is_primary = 1;
    for my $cat_id (@$cat_ids) {
        my $p = MT::Placement->new;
        $p->entry_id($entry->id);
        $p->blog_id($entry->blog_id);
        $p->category_id($cat_id);
        $p->is_primary($is_primary);
        $p->save or die $p->errstr . "\n";
        $is_primary = 0;
    }
}

1;
