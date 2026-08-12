package MTMCP::Tools::Blog;
use strict;
use warnings;
use MT::Blog;
use MT::Website;

sub list {
    my ($app, $args) = @_;
    my @blogs = MT::Blog->load(
        { class => '*' },
        { sort => 'name', direction => 'ascend' }
    );

    my $user = eval { $app->user };
    if ($user && !$user->is_superuser) {
        require MT::Permission;
        @blogs = grep { MT::Permission->load({ author_id => $user->id, blog_id => $_->id }) } @blogs;
    }

    return [ map {
        {
            id   => $_->id,
            name => $_->name,
            type => $_->class,
            url  => $_->site_url // '',
        }
    } @blogs ];
}

1;
