package MT::ContentData;
use strict;
use warnings;

our %STORE;
our $NEXT_ID = 1;
our @SAVED;
our @REMOVED;
our $LAST_LOAD_TERMS;
our $LAST_LOAD_ARGS;

sub reset {
    %STORE           = ();
    $NEXT_ID         = 1;
    @SAVED           = ();
    @REMOVED         = ();
    $LAST_LOAD_TERMS = undef;
    $LAST_LOAD_ARGS  = undef;
}

sub new {
    my $class = shift;
    bless {
        id              => undef,
        content_type_id => undef,
        blog_id         => undef,
        status          => 1,
        authored_on     => undef,
        author_id       => undef,
        label           => undef,
        data            => {},
    }, $class;
}

sub load {
    my ($class, $terms, $args) = @_;
    $LAST_LOAD_TERMS = $terms;
    $LAST_LOAD_ARGS  = $args;
    my @objs = values %STORE;

    if (!defined $terms) {
    }
    elsif (!ref $terms) {
        @objs = grep { defined $_->id && $_->id == $terms } @objs;
    }
    elsif (ref $terms eq 'ARRAY') {
        my ($base) = grep { ref $_ eq 'HASH' } @$terms;
        if ($base) {
            if (exists $base->{id}) {
                @objs = grep { defined $_->id && $_->id == $base->{id} } @objs;
            }
            if (exists $base->{content_type_id}) {
                @objs = grep {
                    defined $_->content_type_id
                        && $_->content_type_id == $base->{content_type_id}
                } @objs;
            }
            if (exists $base->{blog_id}) {
                @objs = grep { defined $_->blog_id && $_->blog_id == $base->{blog_id} } @objs;
            }
            if (exists $base->{status}) {
                @objs = grep { defined $_->status && $_->status == $base->{status} } @objs;
            }
        }
    }
    elsif (ref $terms eq 'HASH') {
        if (exists $terms->{id}) {
            @objs = grep { defined $_->id && $_->id == $terms->{id} } @objs;
        }
        if (exists $terms->{content_type_id}) {
            @objs = grep {
                defined $_->content_type_id
                    && $_->content_type_id == $terms->{content_type_id}
            } @objs;
        }
        if (exists $terms->{blog_id}) {
            @objs = grep { defined $_->blog_id && $_->blog_id == $terms->{blog_id} } @objs;
        }
        if (exists $terms->{status}) {
            @objs = grep { defined $_->status && $_->status == $terms->{status} } @objs;
        }
    }

    if ($args && $args->{sort}) {
        my $field = $args->{sort};
        @objs = sort { ($a->$field // '') cmp ($b->$field // '') } @objs;
        @objs = reverse @objs if ($args->{direction} // '') eq 'descend';
    }
    if ($args && $args->{offset}) {
        my $off = $args->{offset};
        @objs = $off < @objs ? @objs[ $off .. $#objs ] : ();
    }
    if ($args && $args->{limit} && @objs > $args->{limit}) {
        @objs = @objs[ 0 .. $args->{limit} - 1 ];
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

sub remove {
    my $self = shift;
    delete $STORE{ $self->{id} } if defined $self->{id};
    push @REMOVED, $self;
    return 1;
}

sub errstr { 'stub error' }

for my $field (
    qw(id content_type_id blog_id status authored_on author_id label data)
    )
{
    no strict 'refs';
    *$field = sub {
        my $self = shift;
        $self->{$field} = shift if @_;
        return $self->{$field};
    };
}

1;
