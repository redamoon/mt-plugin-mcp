package MTMCP::Tools::Category;
use strict;
use warnings;
use MT::Category;
use MT::Tag;
use MT::ObjectTag;
use MTMCP::Perm;

sub list {
    my ($app, $args) = @_;
    my $blog_id = $args->{blog_id} or die "blog_id is required\n";
    MTMCP::Perm::require_blog_access($app, $blog_id);
    my @cats = MT::Category->load({ blog_id => $blog_id },
        { sort => 'label', direction => 'ascend' });
    return [ map { { id => $_->id, label => $_->label, parent_id => $_->parent || undef } } @cats ];
}

sub list_tags {
    my ($app, $args) = @_;
    my $blog_id = $args->{blog_id} or die "blog_id is required\n";
    MTMCP::Perm::require_blog_access($app, $blog_id);
    my @obj_tags = MT::ObjectTag->load({ blog_id => $blog_id, object_datasource => 'entry' });
    my %tag_ids = map { $_->tag_id => 1 } @obj_tags;
    my @tags;
    if (%tag_ids) {
        @tags = MT::Tag->load({ id => [keys %tag_ids] }, { sort => 'name', direction => 'ascend' });
    }
    return [ map { { id => $_->id, name => $_->name } } @tags ];
}

1;
