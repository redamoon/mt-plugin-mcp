package MT::Lockout;
use strict;
use warnings;

our @UNLOCKED;

sub reset { @UNLOCKED = () }

sub unlock {
    my ($class, $user) = @_;
    push @UNLOCKED, $user;
    return unless $user;
    $user->lockout_recover_salt(undef) if $user->can('lockout_recover_salt');
    $user->locked_out_time(0);
    return 1;
}

1;
