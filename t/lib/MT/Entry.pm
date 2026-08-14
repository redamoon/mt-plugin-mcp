package MT::Entry;
use strict;
use warnings;

# MTMCP::Tools::Entry の単体テスト用スタブ。
# 実 MT コアは本リポジトリに含まれないため、class フィルタの有無だけを再現する。
# スカラー load / { id => $id } は class を見ない（MT::Object::lookup と同じ）。

use constant HOLD    => 1;
use constant RELEASE => 2;

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
        id          => undef,
        blog_id     => undef,
        title       => undef,
        text        => undef,
        text_more   => undef,
        excerpt     => undef,
        status      => HOLD(),
        author_id   => undef,
        authored_on => undef,
        modified_on => undef,
        basename    => undef,
        class       => 'entry',
    }, $class;
}

sub exist {
    my $class = shift;
    return $class->load(@_) ? 1 : 0;
}

sub load {
    my ($class, $terms, $args) = @_;
    $LAST_LOAD_TERMS = $terms;

    my @objs = values %STORE;

    if (!defined $terms) {
        # fall through
    }
    elsif (!ref $terms) {
        # スカラー引数 = lookup。class フィルタなし。
        @objs = grep { defined $_->id && $_->id == $terms } @objs;
    }
    elsif (ref $terms eq 'HASH') {
        if (exists $terms->{id}) {
            @objs = grep { defined $_->id && $_->id == $terms->{id} } @objs;
        }
        if (exists $terms->{class}) {
            my $want = $terms->{class};
            @objs = grep { ($_->class // '') eq $want } @objs;
        }
        if (exists $terms->{blog_id}) {
            @objs = grep { defined $_->blog_id && $_->blog_id == $terms->{blog_id} } @objs;
        }
        if (exists $terms->{status}) {
            @objs = grep { defined $_->status && $_->status == $terms->{status} } @objs;
        }
        if (exists $terms->{basename}) {
            @objs = grep { ($_->basename // '') eq ($terms->{basename} // '') } @objs;
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
    $self->{class} = 'entry' unless defined $self->{class};
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

sub errstr    { 'stub error' }
sub permalink { '' }

for my $field (
    qw(id blog_id title text text_more excerpt status author_id authored_on modified_on basename class)
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
