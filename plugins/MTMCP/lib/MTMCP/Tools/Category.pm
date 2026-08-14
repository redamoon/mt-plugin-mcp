package MTMCP::Tools::Category;
use strict;
use warnings;
use MT::Category;
use MTMCP::Perm;

sub list {
    my ($app, $args) = @_;
    my $blog_id = $args->{blog_id} or die "blog_id is required\n";
    MTMCP::Perm::require_blog_access($app, $blog_id);
    my @cats = MT::Category->load({ blog_id => $blog_id },
        { sort => 'label', direction => 'ascend' });
    return [ map { { id => $_->id, label => $_->label, parent_id => $_->parent || undef } } @cats ];
}

1;
