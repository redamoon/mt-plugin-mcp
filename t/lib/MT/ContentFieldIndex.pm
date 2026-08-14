package MT::ContentFieldIndex;
use strict;
use warnings;

# MT::Object::join_on と同じ形: [ $class, $col, $terms, $args ]
sub join_on {
    my $class = shift;
    return [ $class, @_ ];
}

1;
