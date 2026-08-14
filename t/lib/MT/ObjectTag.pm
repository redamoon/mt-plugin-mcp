package MT::ObjectTag;
use strict;
use warnings;

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
        id                => undef,
        blog_id           => undef,
        object_id         => undef,
        object_datasource => undef,
        tag_id            => undef,
        cf_id             => 0,
    }, $class;
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
            @objs = grep { defined $_->id && $_->id == $terms->{id} } @objs;
        }
        if (exists $terms->{blog_id}) {
            @objs = _filter_blog($terms->{blog_id}, @objs);
        }
        if (exists $terms->{tag_id}) {
            @objs = grep { defined $_->tag_id && $_->tag_id == $terms->{tag_id} } @objs;
        }
        if (exists $terms->{object_id}) {
            @objs = grep { defined $_->object_id && $_->object_id == $terms->{object_id} } @objs;
        }
        if (exists $terms->{object_datasource}) {
            @objs = grep {
                ($_->object_datasource // '') eq ($terms->{object_datasource} // '')
            } @objs;
        }
        if (exists $terms->{cf_id}) {
            @objs = grep { ($_->cf_id || 0) == ($terms->{cf_id} || 0) } @objs;
        }
    }

    return @objs if wantarray;
    return $objs[0];
}

sub _filter_blog {
    my ($want, @objs) = @_;
    if (ref $want eq 'HASH' && exists $want->{not}) {
        my $not = $want->{not};
        return grep { defined $_->blog_id && $_->blog_id != $not } @objs;
    }
    return grep { defined $_->blog_id && $_->blog_id == $want } @objs;
}

sub save {
    my $self = shift;
    $self->{id} = $NEXT_ID++ unless defined $self->{id};
    $self->{cf_id} = 0 unless defined $self->{cf_id};
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

for my $field (qw(id blog_id object_id object_datasource tag_id cf_id)) {
    no strict 'refs';
    *$field = sub {
        my $self = shift;
        $self->{$field} = shift if @_;
        return $self->{$field};
    };
}

1;
