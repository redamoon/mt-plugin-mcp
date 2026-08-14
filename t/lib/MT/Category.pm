package MT::Category;
use strict;
use warnings;

our %STORE;
our $NEXT_ID = 1;
our @SAVED;

sub reset {
    %STORE   = ();
    $NEXT_ID = 1;
    @SAVED   = ();
}

sub new {
    my $class = shift;
    bless {
        id       => undef,
        blog_id  => undef,
        label    => undef,
        basename => undef,
        parent   => 0,
        class    => 'category',
    }, $class;
}

sub load {
    my ( $class, $terms, $args ) = @_;
    my @objs = values %STORE;
    if ( !defined $terms ) {
    }
    elsif ( !ref $terms ) {
        @objs = grep { defined $_->id && $_->id == $terms } @objs;
    }
    elsif ( ref $terms eq 'HASH' ) {
        if ( exists $terms->{id} ) {
            @objs = grep { defined $_->id && $_->id == $terms->{id} } @objs;
        }
        if ( exists $terms->{class} ) {
            my $want = $terms->{class};
            @objs = grep { ( $_->class // '' ) eq $want } @objs;
        }
        if ( exists $terms->{blog_id} ) {
            @objs = grep { defined $_->blog_id && $_->blog_id == $terms->{blog_id} } @objs;
        }
    }
    return @objs if wantarray;
    return $objs[0];
}

sub save {
    my $self = shift;
    $self->{id} = $NEXT_ID++ unless defined $self->{id};
    $STORE{ $self->{id} } = $self;
    push @SAVED, $self;
    return 1;
}

sub errstr { 'stub error' }

for my $field (qw(id blog_id label basename parent class)) {
    no strict 'refs';
    *$field = sub {
        my $self = shift;
        $self->{$field} = shift if @_;
        return $self->{$field};
    };
}

1;
