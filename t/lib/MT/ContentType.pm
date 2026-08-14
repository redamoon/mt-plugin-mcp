package MT::ContentType;
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
        id               => undef,
        blog_id          => undef,
        name             => undef,
        description      => '',
        user_disp_option => 0,
        data_label       => undef,
        fields           => [],
    }, $class;
}

sub load {
    my ($class, $terms) = @_;
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
        if (exists $terms->{blog_id}) {
            @objs = grep { defined $_->blog_id && $_->blog_id == $terms->{blog_id} } @objs;
        }
        if (exists $terms->{name}) {
            @objs = grep { ($_->name // '') eq $terms->{name} } @objs;
        }
    }
    return @objs if wantarray;
    return $objs[0];
}

sub count {
    my $class = shift;
    my @objs  = $class->load(@_);
    return scalar @objs;
}

sub save {
    my $self = shift;
    $self->{id} = $NEXT_ID++ unless defined $self->{id};
    $STORE{ $self->{id} } = $self;
    return 1;
}

sub errstr { 'stub error' }

for my $field (qw(id blog_id name description user_disp_option data_label fields)) {
    no strict 'refs';
    *$field = sub {
        my $self = shift;
        $self->{$field} = shift if @_;
        return $self->{$field};
    };
}

1;
