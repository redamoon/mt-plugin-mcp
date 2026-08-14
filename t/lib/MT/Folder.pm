package MT::Folder;
use strict;
use warnings;

# mt_category は Category と Folder で共有される。
# スカラー load / { id => $id } は class を見ない（MT::Object::lookup と同じ）。

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
        id              => undef,
        blog_id         => undef,
        label           => undef,
        basename        => undef,
        parent          => 0,
        description     => undef,
        class           => 'folder',
        category_set_id => 0,
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
        if (!exists $t{id} && !exists $t{class}) {
            $t{class} = 'folder';
        }
        if (exists $t{id}) {
            @objs = grep { defined $_->id && $_->id == $t{id} } @objs;
        }
        if (exists $t{class}) {
            @objs = grep { ($_->class // '') eq $t{class} } @objs;
        }
        if (exists $t{blog_id}) {
            @objs = grep { defined $_->blog_id && $_->blog_id == $t{blog_id} } @objs;
        }
        if (exists $t{parent}) {
            my $want = $t{parent} || 0;
            @objs = grep { ($_->parent || 0) == $want } @objs;
        }
        if (exists $t{basename}) {
            @objs = grep { ($_->basename // '') eq $t{basename} } @objs;
        }
    }

    if ($args && $args->{sort} && $args->{sort} eq 'label') {
        @objs = sort { ($a->label // '') cmp ($b->label // '') } @objs;
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

sub exist {
    my $class = shift;
    return $class->load(@_) ? 1 : 0;
}

sub save {
    my $self = shift;
    $self->{id}              = $NEXT_ID++ unless defined $self->{id};
    $self->{class}           = 'folder';
    $self->{category_set_id} = 0;
    $STORE{ $self->{id} }    = $self;
    push @SAVED, $self;
    return 1;
}

sub remove {
    my $self = shift;
    delete $STORE{ $self->{id} } if defined $self->{id};
    push @REMOVED, $self;
    return 1;
}

# $self が $other の祖先なら真（親変更時のループ検出用）。
sub is_ancestor {
    my ($self, $other) = @_;
    return 0 unless $self && $other && defined $self->id;
    my $pid = $other->parent || 0;
    my %seen;
    while ($pid) {
        return 1 if $pid == $self->id;
        last if $seen{$pid}++;
        my $p = MT::Folder->load({ id => $pid, class => 'folder' }) or last;
        $pid = $p->parent || 0;
    }
    return 0;
}

sub errstr { 'stub error' }

for my $field (qw(id blog_id label basename parent description class category_set_id)) {
    no strict 'refs';
    *$field = sub {
        my $self = shift;
        $self->{$field} = shift if @_;
        return $self->{$field};
    };
}

1;
