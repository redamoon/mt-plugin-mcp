package MT::Category;
use strict;
use warnings;

# mt_category は Category と Folder で共有される。
# スカラー load / { id => $id } は class を見ない（MT::Object::lookup と同じ）。

our %STORE;
our $NEXT_ID = 1;
our @SAVED;
our @REMOVED;
our $LAST_LOAD_TERMS;

# load の呼び出し回数。N+1 が起きていないかをテストから検証するために数える。
our $LOAD_COUNT = 0;

sub reset {
    %STORE           = ();
    $NEXT_ID         = 1;
    @SAVED           = ();
    @REMOVED         = ();
    $LAST_LOAD_TERMS = undef;
    $LOAD_COUNT      = 0;
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
        class           => 'category',
        category_set_id => 0,
    }, $class;
}

sub load {
    my ($class, $terms, $args) = @_;
    $LAST_LOAD_TERMS = $terms;
    $LOAD_COUNT++;

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
            $t{class} = 'category';
        }
        if (exists $t{id}) {
            # 本番の Data::ObjectDriver は arrayref を IN として扱うので、それに合わせる。
            my @want = ref $t{id} eq 'ARRAY' ? @{ $t{id} } : ($t{id});
            my %want = map { $_ => 1 } grep { defined } @want;
            @objs = grep { defined $_->id && $want{ $_->id } } @objs;
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
        if (exists $t{label}) {
            @objs = grep { ($_->label // '') eq $t{label} } @objs;
        }
        if (exists $t{category_set_id}) {
            my $want = $t{category_set_id} || 0;
            @objs = grep { ($_->category_set_id || 0) == $want } @objs;
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
    $self->{class}           = 'category' unless defined $self->{class};
    $self->{category_set_id} = 0 unless defined $self->{category_set_id};
    $STORE{ $self->{id} }    = $self;
    push @SAVED, $self;
    return 1;
}

sub remove {
    my $self = shift;
    my $id   = $self->{id};
    my $new_parent = $self->{parent} || 0;
    if (defined $id) {
        for my $child (values %STORE) {
            next unless ($child->parent || 0) == $id;
            $child->parent($new_parent);
        }
        delete $STORE{$id};
    }
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
        my $p = MT::Category->load({ id => $pid, class => 'category' }) or last;
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
