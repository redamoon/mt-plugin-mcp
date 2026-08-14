package MT::ContentField;
use strict;
use warnings;

our %STORE;
our $NEXT_ID = 1;

sub reset {
    %STORE   = ();
    $NEXT_ID = 1;
}

sub new {
    my $class = shift;
    bless {
        id                 => undef,
        blog_id            => undef,
        content_type_id    => undef,
        type               => undef,
        name               => undef,
        required           => 0,
        unique_id          => undef,
        related_cat_set_id => undef,
        options            => {},
    }, $class;
}

sub load {
    my ($class, $terms, $args) = @_;
    my @objs = values %STORE;
    if (!defined $terms) {
        # fall through
    }
    elsif (!ref $terms) {
        @objs = grep { defined $_->id && $_->id == $terms } @objs;
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
    }
    if ($args && $args->{sort} && $args->{sort} eq 'id') {
        @objs = sort { ($a->id || 0) <=> ($b->id || 0) } @objs;
        @objs = reverse @objs if ($args->{direction} // '') eq 'descend';
    }
    return @objs if wantarray;
    return $objs[0];
}

sub save {
    my $self = shift;
    $self->{id} = $NEXT_ID++ unless defined $self->{id};
    $self->{unique_id} ||= 'uid-' . $self->{id};
    $STORE{ $self->{id} } = $self;
    return 1;
}

sub errstr { 'stub error' }

for my $field (
    qw(id blog_id content_type_id type name required unique_id related_cat_set_id options)
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
