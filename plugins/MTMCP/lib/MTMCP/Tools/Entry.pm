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
use constant EXPORT_MAX_CHARS  => 100_000;
use constant IMPORT_MAX_BYTES  => 1_000_000;

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

sub export {
    my ($app, $args) = @_;
    my $entry_id = $args->{entry_id} or die "entry_id is required\n";
    my $entry = _load_entry($entry_id) or die "Entry not found: $entry_id\n";
    my $blog_id = $entry->blog_id;
    if (defined $args->{blog_id} && $args->{blog_id} ne '' && $args->{blog_id} != $blog_id) {
        die "Entry not found: $entry_id\n";
    }
    MTMCP::Perm::require_blog_permission($app, $blog_id, 'export_blog', 'ブログのエクスポート');

    my $body = _to_mt_export($entry);
    my $truncated = 0;
    if (length($body) > EXPORT_MAX_CHARS) {
        $body      = substr($body, 0, EXPORT_MAX_CHARS);
        $truncated = 1;
    }
    return {
        entry_id  => $entry->id,
        blog_id   => $blog_id,
        format    => 'mt',
        body      => $body,
        length    => length($body),
        truncated => $truncated ? JSON::true : JSON::false,
    };
}

sub _to_mt_export {
    my ($entry) = @_;
    my $author_name = 'author';
    if (my $aid = $entry->author_id) {
        require MT::Author;
        my $author = eval { MT::Author->load($aid) };
        $author_name = $author->name if $author && defined $author->name && $author->name ne '';
    }

    my $status = ($entry->status == MT::Entry::RELEASE()) ? 'Publish' : 'Draft';
    my @lines  = (
        "AUTHOR: $author_name",
        'TITLE: ' . ($entry->title // ''),
        'BASENAME: ' . ($entry->basename // ''),
        "STATUS: $status",
        'DATE: ' . _export_date($entry->authored_on),
    );

    my @placements = eval { MT::Placement->load({ entry_id => $entry->id }) };
    if (@placements) {
        require MT::Category;
        my $primary_done = 0;
        for my $p (@placements) {
            my $cat = MT::Category->load($p->category_id) or next;
            my $class = eval { $cat->class } // 'category';
            next if $class eq 'folder';
            my $label = $cat->label // '';
            if (!$primary_done && eval { $p->is_primary }) {
                push @lines, "PRIMARY CATEGORY: $label";
                $primary_done = 1;
            }
            push @lines, "CATEGORY: $label";
        }
    }

    push @lines, '-----', 'BODY:', ($entry->text // ''), '-----';
    if (defined $entry->text_more && $entry->text_more ne '') {
        push @lines, 'EXTENDED BODY:', $entry->text_more, '-----';
    }
    if (defined $entry->excerpt && $entry->excerpt ne '') {
        push @lines, 'EXCERPT:', $entry->excerpt, '-----';
    }
    push @lines, '--------';
    return join("\n", @lines) . "\n";
}

sub _export_date {
    my ($ts) = @_;
    return '' unless defined $ts && $ts ne '';
    if ($ts =~ /\A(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})\z/) {
        my ($y, $m, $d, $H, $M, $S) = ($1, $2, $3, $4, $5, $6);
        my $ampm = $H >= 12 ? 'PM' : 'AM';
        my $h12  = $H % 12;
        $h12 = 12 if $h12 == 0;
        return sprintf('%02d/%02d/%04d %02d:%02d:%02d %s', $m, $d, $y, $h12, $M, $S, $ampm);
    }
    return $ts;
}

sub import_entries {
    my ($app, $args) = @_;
    my $blog_id = $args->{blog_id} or die "blog_id is required\n";
    MTMCP::Perm::require_blog_permission($app, $blog_id, 'import_blog', 'ブログのインポート');

    die "ImportPath は使えません。MT 形式の本文を body に渡してください\n"
        if exists $args->{import_path} || exists $args->{ImportPath} || exists $args->{file};

    die "confirm: true が必要です（記事を一括作成する破壊的操作です）\n"
        unless _is_true($args->{confirm});

    if (exists $args->{import_as_me} && !_is_true($args->{import_as_me})) {
        die "import_as_me は常に有効です（ユーザー新規作成はしません）\n";
    }

    my $body = $args->{body};
    die "body is required\n" if !defined $body || $body eq '';

    my $bytes = $body;
    utf8::encode($bytes) if utf8::is_utf8($bytes);
    die "body exceeds 1MB limit\n" if length($bytes) > IMPORT_MAX_BYTES;

    my $default_status = $args->{default_status} // 'draft';
    die "Unknown default_status: $default_status\n"
        unless $default_status eq 'draft' || $default_status eq 'publish';
    my $status_id = $default_status eq 'publish' ? MT::Entry::RELEASE() : MT::Entry::HOLD();

    my $user = eval { $app->user };
    die "認証されていないため、この操作を行えません\n"
        unless $user && defined $user->id;
    my $author_id = $user->id;

    my @parsed = _parse_mt_export($body);
    die "importable entries not found\n" unless @parsed;

    my @ids;
    for my $item (@parsed) {
        my $entry = MT::Entry->new;
        $entry->blog_id($blog_id);
        $entry->class('entry');
        $entry->title($item->{title});
        $entry->text($item->{body} // '');
        $entry->text_more($item->{more})     if defined $item->{more};
        $entry->excerpt($item->{excerpt})    if defined $item->{excerpt};
        $entry->basename($item->{basename})  if defined $item->{basename} && $item->{basename} ne '';
        $entry->status($status_id);
        $entry->author_id($author_id);
        $entry->authored_on($item->{authored_on}) if $item->{authored_on};
        $entry->save or die $entry->errstr . "\n";

        if ($item->{categories} && @{ $item->{categories} }) {
            require MT::Category;
            my @cat_ids;
            my %seen;
            for my $label (@{ $item->{categories} }) {
                my $cat = MT::Category->load({
                    blog_id => $blog_id,
                    label   => $label,
                    class   => 'category',
                }) or next;
                next if $seen{ $cat->id }++;
                push @cat_ids, $cat->id;
            }
            _set_categories($entry, \@cat_ids) if @cat_ids;
        }
        push @ids, $entry->id;
    }

    return {
        imported     => scalar @ids,
        entry_ids    => \@ids,
        status       => 'imported',
        rebuilt      => JSON::false,
        import_as_me => JSON::true,
    };
}

sub _is_true {
    my ($v) = @_;
    return 0 unless defined $v;
    return 0 if !$v;
    return 0 if !ref($v) && lc($v) eq 'false';
    return 1;
}

sub _parse_mt_export {
    my ($text) = @_;
    my @chunks = split /(?m)^--------[ \t]*\n?/, $text;
    my @entries;
    for my $chunk (@chunks) {
        next if !defined $chunk || $chunk =~ /\A\s*\z/;
        my @lines = split /\n/, $chunk, -1;
        my %item;
        my @categories;
        my $i = 0;
        while ($i < @lines) {
            my $line = $lines[$i];
            last if $line eq '-----';
            if ($line =~ /^(TITLE|BASENAME|STATUS|DATE|AUTHOR|PRIMARY CATEGORY|CATEGORY):\s*(.*)\z/) {
                my ($k, $v) = ($1, $2);
                $item{title}    = $v if $k eq 'TITLE';
                $item{basename} = $v if $k eq 'BASENAME';
                $item{authored_on} = _parse_import_date($v) if $k eq 'DATE';
                if ($k eq 'PRIMARY CATEGORY' || $k eq 'CATEGORY') {
                    push @categories, $v if defined $v && $v ne '';
                }
            }
            $i++;
        }
        next unless defined $item{title} && $item{title} ne '';

        my $section;
        my @buf;
        my $flush = sub {
            return unless $section;
            my $val = join("\n", @buf);
            $val =~ s/\n+\z//;
            $item{body}    = $val if $section eq 'BODY';
            $item{more}    = $val if $section eq 'EXTENDED BODY';
            $item{excerpt} = $val if $section eq 'EXCERPT';
            $section = undef;
            @buf     = ();
        };
        while ($i < @lines) {
            my $line = $lines[$i];
            if ($line eq '-----') {
                $flush->();
                $i++;
                next;
            }
            if (!defined $section && $line =~ /^(BODY|EXTENDED BODY|EXCERPT|KEYWORDS):\s*\z/) {
                $section = $1;
                $i++;
                next;
            }
            push @buf, $line if $section;
            $i++;
        }
        $flush->();
        $item{categories} = \@categories if @categories;
        push @entries, \%item;
    }
    return @entries;
}

sub _parse_import_date {
    my ($s) = @_;
    return unless defined $s && $s ne '';
    if ($s =~ m{\A(\d{2})/(\d{2})/(\d{4}) (\d{2}):(\d{2}):(\d{2}) (AM|PM)\z}) {
        my ($mo, $d, $y, $h, $mi, $se, $ap) = ($1, $2, $3, $4, $5, $6, $7);
        $h = 0 if $ap eq 'AM' && $h == 12;
        $h += 12 if $ap eq 'PM' && $h != 12;
        return sprintf('%04d%02d%02d%02d%02d%02d', $y, $mo, $d, $h, $mi, $se);
    }
    return $s if $s =~ /\A\d{14}\z/;
    return;
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
