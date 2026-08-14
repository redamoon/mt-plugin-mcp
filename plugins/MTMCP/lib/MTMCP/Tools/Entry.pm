package MTMCP::Tools::Entry;
use strict;
use warnings;
use MT::Entry;
use MT::Placement;
use MTMCP::Perm;

# キーワード検索時にPerl側でスキャンする最大件数。DB側でのLIKE検索ではなく
# 直近のレコードをこの件数までロードしてから絞り込むため、これを超えて
# 古いレコードにしかマッチしないキーワードは検出できない（既知の制約）。
use constant KEYWORD_SCAN_LIMIT => 2000;

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

    my %load_opts = ( sort => 'authored_on', direction => 'descend' );
    if ($keyword) {
        $load_opts{limit} = KEYWORD_SCAN_LIMIT;
    } else {
        $load_opts{limit}  = $limit;
        $load_opts{offset} = $offset;
    }

    my @entries = MT::Entry->load(\%terms, \%load_opts);

    if ($keyword) {
        my $kw = lc $keyword;
        @entries = grep {
            index(lc($_->title // ''), $kw) >= 0
                || index(lc($_->text // ''), $kw) >= 0
        } @entries;
        @entries = splice(@entries, $offset, $limit);
    }

    return [ map { _to_hash($_) } @entries ];
}

# mt_entry は Entry と Page で共有される。スカラー load / { id => $id } は
# class フィルタを通さないため、Page ID でもオブジェクトが返る。
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
