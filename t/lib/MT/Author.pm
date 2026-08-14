package MT::Author;
use strict;
use warnings;

# MTMCP::Tools::User の単体テスト用スタブ。
# スカラー load は type を見ない（COMMENTER も返る）。{ id, type } は type で絞る。

sub AUTHOR ()    { 1 }
sub COMMENTER () { 2 }
sub ACTIVE ()    { 1 }
sub INACTIVE ()  { 2 }
sub PENDING ()   { 3 }

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
        id                   => undef,
        name                 => undef,
        nickname             => undef,
        email                => undef,
        url                  => undef,
        type                 => AUTHOR(),
        status               => ACTIVE(),
        password             => undef,
        auth_type            => undef,
        text_format          => undef,
        is_superuser         => 0,
        locked_out_time      => 0,
        lockout_recover_salt => undef,
        created_on           => undef,
    }, $class;
}

sub exist {
    my $class = shift;
    return $class->load(@_) ? 1 : 0;
}

sub load {
    my ($class, $terms, $args) = @_;
    $LAST_LOAD_TERMS = $terms;
    $LAST_LOAD_ARGS  = $args;

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
        if (exists $terms->{type}) {
            my $want = $terms->{type};
            @objs = grep { defined $_->type && $_->type == $want } @objs;
        }
        if (exists $terms->{status}) {
            my $want = $terms->{status};
            @objs = grep { defined $_->status && $_->status == $want } @objs;
        }
        if (exists $terms->{name}) {
            my $want = $terms->{name};
            @objs = grep { ($_->name // '') eq ($want // '') } @objs;
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
    $self->{type} = AUTHOR() unless defined $self->{type};
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

sub set_password {
    my ($self, $pass) = @_;
    $self->{password} = 'hashed:' . length($pass);
    return 1;
}

sub get_status_text {
    my $self = shift;
    return 'Active'   if ($self->{status} // 0) == ACTIVE();
    return 'Pending'  if ($self->{status} // 0) == PENDING();
    return 'Disabled';
}

sub set_status_by_text {
    my $self   = shift;
    my $status = lc($_[0] // '');
    if ($status eq 'active') {
        $self->{status} = ACTIVE();
    }
    elsif ($status eq 'pending') {
        $self->{status} = PENDING();
    }
    else {
        $self->{status} = INACTIVE();
    }
}

sub locked_out {
    my $self = shift;
    return ($self->{locked_out_time} && $self->{locked_out_time} > 0) ? 1 : 0;
}

sub is_superuser {
    my $self = shift;
    $self->{is_superuser} = shift if @_;
    return $self->{is_superuser} ? 1 : 0;
}

sub can_manage_users_groups {
    my $self = shift;
    return 1 if $self->is_superuser;
    return $self->{can_manage_users_groups} ? 1 : 0;
}

sub errstr { 'stub error' }

for my $field (
    qw(id name nickname email url type status password auth_type text_format
       locked_out_time lockout_recover_salt created_on)
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
