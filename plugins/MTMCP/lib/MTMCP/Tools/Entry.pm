package MTMCP::Tools::Entry;
use strict;
use warnings;
use MT::Entry;
use MT::Placement;

sub list {
    my ($app, $args) = @_;
    my $blog_id = $args->{blog_id} or die "blog_id is required\n";
    my $limit   = $args->{limit}   // 20;
    my $status  = $args->{status}  // 'publish';
    my %terms = (blog_id => $blog_id);
    $terms{status} = MT::Entry::RELEASE() if $status eq 'publish';
    $terms{status} = MT::Entry::HOLD()    if $status eq 'draft';
    my @entries = MT::Entry->load(\%terms,
        { limit => $limit, sort => 'authored_on', direction => 'descend' });
    return [ map { _to_hash($_) } @entries ];
}

sub get {
    my ($app, $args) = @_;
    my $entry_id = $args->{entry_id} or die "entry_id is required\n";
    my $entry = MT::Entry->load($entry_id) or die "Entry not found: $entry_id\n";
    return _to_hash($entry, 1);
}

sub create {
    my ($app, $args) = @_;
    my $blog_id = $args->{blog_id} or die "blog_id is required\n";
    my $title   = $args->{title}   or die "title is required\n";
    my $entry = MT::Entry->new;
    $entry->blog_id($blog_id);
    $entry->title($title);
    $entry->text($args->{body} // '');
    $entry->status(($args->{status}//'draft') eq 'publish' ? MT::Entry::RELEASE() : MT::Entry::HOLD());
    $entry->author_id($app ? $app->user->id : 1);
    $entry->save or die $entry->errstr . "\n";
    _set_categories($entry, $args->{category_ids}) if $args->{category_ids};
    return { entry_id => $entry->id, status => 'created', title => $entry->title };
}

sub update {
    my ($app, $args) = @_;
    my $entry_id = $args->{entry_id} or die "entry_id is required\n";
    my $entry = MT::Entry->load($entry_id) or die "Entry not found: $entry_id\n";
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
