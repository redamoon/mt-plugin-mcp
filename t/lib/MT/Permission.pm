package MT::Permission;
use strict;
use warnings;

our @STORE;

sub reset { @STORE = () }

sub new {
    my $class = shift;
    my %args  = @_;
    bless {
        author_id   => $args{author_id},
        blog_id     => $args{blog_id} // 0,
        permissions => $args{permissions} // {},
    }, $class;
}

sub add {
    my $class = shift;
    my $obj   = $class->new(@_);
    push @STORE, $obj;
    return $obj;
}

sub load {
    my ($class, $terms) = @_;
    $terms ||= {};
    my @objs = @STORE;
    if (exists $terms->{author_id}) {
        @objs = grep { defined $_->author_id && $_->author_id == $terms->{author_id} } @objs;
    }
    if (exists $terms->{blog_id} && !ref $terms->{blog_id}) {
        @objs = grep { ($_->{blog_id} // 0) == $terms->{blog_id} } @objs;
    }
    return @objs if wantarray;
    return $objs[0];
}

sub can_do {
    my ($self, $action) = @_;
    return $self->{permissions}{$action} ? 1 : 0;
}

sub author_id {
    my $self = shift;
    $self->{author_id} = shift if @_;
    return $self->{author_id};
}

sub blog_id {
    my $self = shift;
    $self->{blog_id} = shift if @_;
    return $self->{blog_id};
}

1;
