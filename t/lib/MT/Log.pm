package MT::Log;
use strict;
use warnings;

# MTMCP::Tools::Log の単体テスト用スタブ。
# class_column があるため、terms に class が無いと class_type 相当の system のみ返す。
# class => '*' はクラス制約なし。スカラー load は class を見ない。

sub DEBUG    () { 0 }
sub INFO     () { 1 }
sub NOTICE   () { 2 }
sub WARNING  () { 3 }
sub ERROR    () { 4 }
sub SECURITY () { 5 }

our %STORE;
our $NEXT_ID = 1;
our $LAST_LOAD_TERMS;
our $LAST_LOAD_ARGS;
our $LAST_COUNT_TERMS;
our $LAST_COUNT_ARGS;

sub reset {
    %STORE            = ();
    $NEXT_ID          = 1;
    $LAST_LOAD_TERMS  = undef;
    $LAST_LOAD_ARGS   = undef;
    $LAST_COUNT_TERMS = undef;
    $LAST_COUNT_ARGS  = undef;
}

sub new {
    my $class = shift;
    bless {
        id         => undef,
        blog_id    => 0,
        level      => INFO(),
        class      => 'system',
        category   => undef,
        message    => undef,
        ip         => undef,
        author_id  => undef,
        created_on => undef,
        metadata   => undef,
    }, $class;
}

sub count {
    my ($class, $terms, $args) = @_;
    $LAST_COUNT_TERMS = $terms;
    $LAST_COUNT_ARGS  = $args;
    my @objs = $class->_filter($terms, $args);
    return scalar @objs;
}

sub load {
    my ($class, $terms, $args) = @_;
    $LAST_LOAD_TERMS = $terms;
    $LAST_LOAD_ARGS  = $args;

    my @objs = $class->_filter($terms, $args);

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

sub _filter {
    my ($class, $terms, $args) = @_;
    my @objs = values %STORE;

    if (!defined $terms) {
        @objs = grep { ($_->class // '') eq 'system' } @objs;
        return @objs;
    }
    if (!ref $terms) {
        @objs = grep { defined $_->id && $_->id == $terms } @objs;
        return @objs;
    }
    if (ref $terms ne 'HASH') {
        return @objs;
    }

    if (exists $terms->{id}) {
        @objs = grep { defined $_->id && $_->id == $terms->{id} } @objs;
    }

    if (exists $terms->{class}) {
        my $want = $terms->{class};
        if (!defined $want || $want eq '*') {
            # unconstrained
        }
        else {
            @objs = grep { ($_->class // '') eq $want } @objs;
        }
    }
    else {
        @objs = grep { ($_->class // '') eq 'system' } @objs;
    }

    if (exists $terms->{blog_id}) {
        my $want = $terms->{blog_id};
        if (ref $want eq 'ARRAY') {
            my %ok = map { $_ => 1 } @$want;
            @objs = grep { $ok{ $_->blog_id // 0 } } @objs;
        }
        else {
            @objs = grep { ($_->{blog_id} // 0) == $want } @objs;
        }
    }

    if (exists $terms->{level}) {
        my $want = $terms->{level};
        if (ref $want eq 'ARRAY') {
            my %ok = map { $_ => 1 } @$want;
            @objs = grep { $ok{ $_->level // 0 } } @objs;
        }
        else {
            @objs = grep { defined $_->level && $_->level == $want } @objs;
        }
    }

    if (exists $terms->{category}) {
        my $want = $terms->{category};
        @objs = grep { ($_->category // '') eq ($want // '') } @objs;
    }

    if (exists $terms->{created_on} && ref $terms->{created_on} eq 'ARRAY') {
        my ($from, $to) = @{ $terms->{created_on} };
        if ($args && $args->{range_incl} && $args->{range_incl}{created_on}) {
            @objs = grep {
                my $ts = $_->created_on // '';
                $ts ge $from && $ts le $to
            } @objs;
        }
    }

    if (exists $terms->{'-or'} && ref $terms->{'-or'} eq 'ARRAY') {
        @objs = grep { _match_or($_, $terms->{'-or'}) } @objs;
    }

    return @objs;
}

sub _match_or {
    my ($obj, $clauses) = @_;
    for my $clause (@$clauses) {
        next unless ref $clause eq 'HASH';
        if (exists $clause->{message} && ref $clause->{message} eq 'HASH' && exists $clause->{message}{like}) {
            return 1 if _like($obj->message, $clause->{message}{like});
        }
        if (exists $clause->{ip} && ref $clause->{ip} eq 'HASH' && exists $clause->{ip}{like}) {
            return 1 if _like($obj->ip, $clause->{ip}{like});
        }
    }
    return 0;
}

sub _like {
    my ($value, $pattern) = @_;
    $value = '' unless defined $value;
    return 0 unless defined $pattern;
    my $re = '';
    my @chars = split //, $pattern;
    for (my $i = 0; $i < @chars; $i++) {
        my $c = $chars[$i];
        if ($c eq '\\' && $i + 1 < @chars) {
            $re .= quotemeta($chars[++$i]);
        }
        elsif ($c eq '%') {
            $re .= '.*';
        }
        elsif ($c eq '_') {
            $re .= '.';
        }
        else {
            $re .= quotemeta($c);
        }
    }
    return $value =~ /$re/i ? 1 : 0;
}

sub save {
    my $self = shift;
    $self->{id} = $NEXT_ID++ unless defined $self->{id};
    $self->{class} = 'system' unless defined $self->{class};
    $STORE{ $self->{id} } = $self;
    return 1;
}

sub errstr { 'stub error' }

for my $field (
    qw(id blog_id level class category message ip author_id created_on metadata)
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
