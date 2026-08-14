package MT::Tag;
use strict;
use warnings;

# MTMCP::Tools::Tag の単体テスト用スタブ。
# スカラー load は n8d 専用レコードも返す。操作対象は { id => $id } で載せる。

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
        id         => undef,
        name       => undef,
        n8d_id     => 0,
        is_private => 0,
    }, $class;
}

sub clone {
    my $self = shift;
    return bless { %$self }, ref($self);
}

sub normalize {
    my $tag = shift;
    my ($str) = @_;
    if (!@_ && !(ref $tag)) {
        $str = $tag;
    }
    elsif (!$str && (ref $tag)) {
        $str = $tag->name;
    }
    return '' unless defined $str;
    my $private = $str =~ m/^@/;
    $str =~ s/[@!`\\<>\*&#\/~\?'"\.\,=\(\)\${}\[\];:\ \+\-\r\n]+//gs;
    $str = lc $str;
    $str = '@' . $str if $private;
    return $str;
}

sub exist {
    my $class = shift;
    return $class->load(@_) ? 1 : 0;
}

sub load {
    my ($class, $terms, $args) = @_;
    my @objs = values %STORE;

    if (!defined $terms) {
    }
    elsif (!ref $terms) {
        @objs = grep { defined $_->id && $_->id == $terms } @objs;
    }
    elsif (ref $terms eq 'HASH') {
        if (exists $terms->{id}) {
            @objs = _filter_id($terms->{id}, @objs);
        }
        if (exists $terms->{name}) {
            my $want = $terms->{name};
            @objs = grep { ($_->name // '') eq ($want // '') } @objs;
        }
        if (exists $terms->{n8d_id}) {
            @objs = _filter_n8d($terms->{n8d_id}, @objs);
        }
    }

    if ($args && $args->{sort}) {
        my $field = $args->{sort};
        @objs = sort { ($a->$field // '') cmp ($b->$field // '') } @objs;
        @objs = reverse @objs if ($args->{direction} // '') eq 'descend';
    }

    return @objs if wantarray;
    return $objs[0];
}

sub _filter_id {
    my ($want, @objs) = @_;
    if (ref $want eq 'ARRAY') {
        my %ok = map { $_ => 1 } @$want;
        return grep { defined $_->id && $ok{ $_->id } } @objs;
    }
    return grep { defined $_->id && $_->id == $want } @objs;
}

sub _filter_n8d {
    my ($want, @objs) = @_;
    if (ref $want eq 'ARRAY') {
        my %ok = map { $_ => 1 } grep { $_ } @$want;
        return grep {
            my $nid = $_->n8d_id;
            $nid && $ok{$nid}
        } @objs;
    }
    return grep {
        my $nid = $_->n8d_id;
        $nid && $nid == $want
    } @objs;
}

sub save {
    my $self = shift;
    $self->{id} = $NEXT_ID++ unless defined $self->{id};
    $self->{n8d_id} = 0 unless defined $self->{n8d_id};
    $self->{is_private} = ($self->{name} // '') =~ /^@/ ? 1 : 0;
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

sub clear_cache { 1 }

for my $field (qw(id name n8d_id is_private)) {
    no strict 'refs';
    *$field = sub {
        my $self = shift;
        $self->{$field} = shift if @_;
        return $self->{$field};
    };
}

1;
