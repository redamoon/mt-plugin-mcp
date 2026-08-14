package MT::CategorySet;
use strict;
use warnings;

our %STORE;
our $NEXT_ID = 1;
our @SAVED;
our @REMOVED;
our $LAST_LOAD_TERMS;

sub reset {
    %STORE           = ();
    $NEXT_ID         = 1;
    @SAVED           = ();
    @REMOVED         = ();
    $LAST_LOAD_TERMS = undef;
}

sub new {
    my $class = shift;
    bless {
        id      => undef,
        blog_id => undef,
        name    => undef,
        order   => '',
    }, $class;
}

sub load {
    my ($class, $terms, $args) = @_;
    $LAST_LOAD_TERMS = $terms;

    my @objs = values %STORE;

    if (!defined $terms) {
        # fall through
    }
    elsif (!ref $terms) {
        @objs = grep { defined $_->id && $_->id == $terms } @objs;
    }
    elsif (ref $terms eq 'HASH') {
        my %t = %$terms;
        if (exists $t{id}) {
            @objs = grep { defined $_->id && $_->id == $t{id} } @objs;
        }
        if (exists $t{blog_id}) {
            @objs = grep { defined $_->blog_id && $_->blog_id == $t{blog_id} } @objs;
        }
        if (exists $t{name}) {
            @objs = grep { ($_->name // '') eq $t{name} } @objs;
        }
    }

    return @objs if wantarray;
    return $objs[0];
}

sub exist_same_name_in_site {
    my $self = shift;
    my $name = $self->name // '';
    return 0 if $name eq '';
    for my $other (values %STORE) {
        next unless defined $other->blog_id && defined $self->blog_id;
        next unless $other->blog_id == $self->blog_id;
        next unless ($other->name // '') eq $name;
        next if defined $self->id && defined $other->id && $other->id == $self->id;
        return 1;
    }
    return 0;
}

sub categories {
    my $self = shift;
    return () unless defined $self->id;
    require MT::Category;
    return MT::Category->load({
        blog_id         => $self->blog_id,
        class           => 'category',
        category_set_id => $self->id,
    });
}

sub category_count {
    my $self = shift;
    my @cats = $self->categories;
    return scalar @cats;
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
    my $id   = $self->{id};
    if (defined $id) {
        require MT::Category;
        my @child_ids = grep {
            my $c = $MT::Category::STORE{$_};
            $c && ( $c->category_set_id || 0 ) == $id
        } keys %MT::Category::STORE;
        for my $cid (@child_ids) {
            my $child = $MT::Category::STORE{$cid} or next;
            $child->remove;
        }
        delete $STORE{$id};
    }
    push @REMOVED, $self;
    return 1;
}

sub errstr { 'stub error' }

for my $field (qw(id blog_id name order)) {
    no strict 'refs';
    *$field = sub {
        my $self = shift;
        $self->{$field} = shift if @_;
        return $self->{$field};
    };
}

1;
