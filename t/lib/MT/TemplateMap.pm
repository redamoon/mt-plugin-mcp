package MT::TemplateMap;
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
        id            => undef,
        blog_id       => undef,
        template_id   => undef,
        archive_type  => undef,
        file_template => undef,
        is_preferred  => 0,
        build_type    => 1,
        cat_field_id  => undef,
        dt_field_id   => undef,
    }, $class;
}

sub load {
    my ($class, $terms, $args) = @_;
    $LAST_LOAD_TERMS = $terms;
    my @objs = values %STORE;

    if (!defined $terms) {
    }
    elsif (!ref $terms) {
        @objs = grep { defined $_->id && $_->id == $terms } @objs;
    }
    elsif (ref $terms eq 'HASH') {
        for my $k (qw(id template_id blog_id archive_type is_preferred build_type)) {
            next unless exists $terms->{$k};
            my $want = $terms->{$k};
            @objs = grep { defined $_->{$k} && $_->{$k} eq $want } @objs;
        }
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
    $STORE{ $self->{id} } = $self;
    push @SAVED, $self;

    if (my $blog_id = $self->blog_id) {
        require MT::Blog;
        my $blog = MT::Blog->load($blog_id);
        if ($blog && $self->archive_type) {
            my @types = grep { $_ ne '' } split /,/, ($blog->archive_type // '');
            unless (grep { $_ eq $self->archive_type } @types) {
                push @types, $self->archive_type;
                $blog->archive_type(join ',', @types);
            }
        }
    }
    return 1;
}

sub prefer {
    my ($self, $on) = @_;
    $on = 1 unless defined $on;
    if ($on) {
        my @others = grep {
            defined $_->id
                && (!defined $self->id || $_->id != $self->id)
                && $_->blog_id == $self->blog_id
                && ($_->archive_type // '') eq ($self->archive_type // '')
        } values %STORE;
        $_->is_preferred(0) for @others;
        $self->is_preferred(1);
    }
    else {
        $self->is_preferred(0);
    }
    return $self->save;
}

sub remove {
    my $self = shift;
    my $id   = $self->id;
    my $blog_id = $self->blog_id;
    my $at   = $self->archive_type;
    delete $STORE{$id} if defined $id;
    push @REMOVED, $self;

    my @rest = grep {
        $_->blog_id == $blog_id && ($_->archive_type // '') eq ($at // '')
    } values %STORE;
    if (@rest && !grep { $_->is_preferred } @rest) {
        $rest[0]->is_preferred(1);
        $rest[0]->save;
    }
    if (!@rest && $blog_id) {
        require MT::Blog;
        my $blog = MT::Blog->load($blog_id);
        if ($blog && $at) {
            my @types = grep { $_ ne $at && $_ ne '' } split /,/, ($blog->archive_type // '');
            $blog->archive_type(join ',', @types);
        }
    }
    return 1;
}

sub errstr { 'stub error' }

for my $field (
    qw(id blog_id template_id archive_type file_template is_preferred build_type cat_field_id dt_field_id)
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
