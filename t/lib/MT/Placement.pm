package MT::Placement;
use strict;
use warnings;

# Entry / Page の Placement テスト用スタブ。
our %STORE;
our $NEXT_ID = 1;
our @SAVED;
our @REMOVED;

sub reset {
    %STORE   = ();
    $NEXT_ID = 1;
    @SAVED   = ();
    @REMOVED = ();
}

sub new {
    my $class = shift;
    bless {
        id          => undef,
        entry_id    => undef,
        blog_id     => undef,
        category_id => undef,
        is_primary  => 0,
    }, $class;
}

sub load {
    my ($class, $terms) = @_;
    my @objs = values %STORE;
    if (ref $terms eq 'HASH') {
        if (exists $terms->{entry_id}) {
            @objs = grep { defined $_->entry_id && $_->entry_id == $terms->{entry_id} } @objs;
        }
        if (exists $terms->{category_id}) {
            @objs = grep { defined $_->category_id && $_->category_id == $terms->{category_id} } @objs;
        }
        if (exists $terms->{blog_id}) {
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

sub remove {
    my ($self, $terms) = @_;
    if (ref $self) {
        delete $STORE{ $self->{id} } if defined $self->{id};
        push @REMOVED, $self;
        return 1;
    }
    $terms ||= {};
    my @objs = $self->load($terms);
    for my $obj (@objs) {
        $obj->remove;
    }
    return 1;
}

sub errstr { 'stub error' }

for my $field (qw(id entry_id blog_id category_id is_primary)) {
    no strict 'refs';
    *$field = sub {
        my $self = shift;
        $self->{$field} = shift if @_;
        return $self->{$field};
    };
}

1;
