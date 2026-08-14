package MT::Auth;
use strict;
use warnings;

our $CAN_RECOVER = 1;

sub reset { $CAN_RECOVER = 1 }

sub can_recover_password { $CAN_RECOVER }

1;
