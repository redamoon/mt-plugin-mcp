package MT::CMS::Tools;
use strict;
use warnings;

our @RESET_CALLS;

sub reset {
    @RESET_CALLS = ();
}

sub reset_password {
    my ($app, $user) = @_;
    push @RESET_CALLS, $user;
    return (1, 'sent');
}

1;
