package MT::Template;
use strict;
use warnings;

# MTMCP::Tools::Template / Widget / TemplateMap の単体テスト用スタブ。

our %STORE;
our $NEXT_ID = 1;
our @SAVED;
our @REMOVED;
our $LAST_LOAD_TERMS;
our $LAST_LOAD_ARGS;
our $BUILD_COUNT = 0;
our $LAST_BUILD_CTX;
our $WRITE_COUNT = 0;
our $PUT_DATA_COUNT = 0;

sub reset {
    %STORE           = ();
    $NEXT_ID         = 1;
    @SAVED           = ();
    @REMOVED         = ();
    $LAST_LOAD_TERMS  = undef;
    $LAST_LOAD_ARGS   = undef;
    $BUILD_COUNT      = 0;
    $LAST_BUILD_CTX   = undef;
    $WRITE_COUNT      = 0;
    $PUT_DATA_COUNT   = 0;
}

sub new {
    my $class = shift;
    bless {
        id              => undef,
        blog_id         => undef,
        name            => undef,
        type            => undef,
        text            => undef,
        outfile         => undef,
        identifier      => undef,
        build_type      => undef,
        rebuild_me      => undef,
        modulesets      => undef,
        content_type_id => undef,
    }, $class;
}

sub load {
    my ($class, $terms, $args) = @_;
    $LAST_LOAD_TERMS = $terms;
    $LAST_LOAD_ARGS  = $args;
    my @objs = values %STORE;

    if (!defined $terms) {
    }
    elsif (!ref $terms) {
        @objs = grep { defined $_->id && $_->id == $terms } @objs;
    }
    elsif (ref $terms eq 'ARRAY') {
        my ($base) = grep { ref $_ eq 'HASH' } @$terms;
        if ($base) {
            if (exists $base->{id}) {
                @objs = grep { defined $_->id && $_->id == $base->{id} } @objs;
            }
            if (exists $base->{blog_id}) {
                @objs = grep { defined $_->blog_id && $_->blog_id == $base->{blog_id} } @objs;
            }
            if (exists $base->{type}) {
                @objs = grep { ($_->type // '') eq $base->{type} } @objs;
            }
            if (exists $base->{name} && !ref $base->{name}) {
                @objs = grep { ($_->name // '') eq $base->{name} } @objs;
            }
        }
    }
    elsif (ref $terms eq 'HASH') {
        if (exists $terms->{id}) {
            @objs = grep { defined $_->id && $_->id == $terms->{id} } @objs;
        }
        if (exists $terms->{blog_id}) {
            @objs = grep { defined $_->blog_id && $_->blog_id == $terms->{blog_id} } @objs;
        }
        if (exists $terms->{type}) {
            @objs = grep { ($_->type // '') eq $terms->{type} } @objs;
        }
        if (exists $terms->{name}) {
            @objs = grep { ($_->name // '') eq $terms->{name} } @objs;
        }
    }

    if ($args && $args->{sort} && $args->{sort} eq 'name') {
        @objs = sort { ($a->name // '') cmp ($b->name // '') } @objs;
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
    if (($self->type // '') eq 'widgetset') {
        return $self->save_widgetset;
    }
    $self->{id} = $NEXT_ID++ unless defined $self->{id};
    $STORE{ $self->{id} } = $self;
    push @SAVED, $self;
    return 1;
}

sub save_widgetset {
    my $self = shift;
    $self->{id} = $NEXT_ID++ unless defined $self->{id};
    my $ids = $self->modulesets // '';
    my @parts;
    for my $wid (grep { $_ ne '' } split /,/, $ids) {
        my $w = MT::Template->load($wid);
        my $name = $w ? ($w->name // $wid) : $wid;
        push @parts, qq{<mt:include widget="$name">};
    }
    $self->text(join "\n", @parts);
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

sub context {
    return MT::Template::_Context->new;
}

sub build {
    my ($self, $ctx) = @_;
    $BUILD_COUNT++;
    $LAST_BUILD_CTX = $ctx;
    my $entry = $ctx && $ctx->stash('entry');
    my $title = $entry ? ($entry->title // '') : '';
    return ($self->text // '') . $title;
}

sub write {
    $WRITE_COUNT++;
    die "MT::Template::write must not be called during preview\n";
}

sub put_data {
    $PUT_DATA_COUNT++;
    die "put_data must not be called during preview\n";
}

sub errstr { 'stub error' }

sub compile { 1 }
sub errors  { [] }

for my $field (
    qw(id blog_id name type text outfile identifier build_type rebuild_me modulesets content_type_id)
    )
{
    no strict 'refs';
    *$field = sub {
        my $self = shift;
        $self->{$field} = shift if @_;
        return $self->{$field};
    };
}

package MT::Template::_Context;
sub new { bless { stash => {}, vars => {} }, shift }
sub stash {
    my ($self, $key, $val) = @_;
    $self->{stash}{$key} = $val if @_ > 2;
    return $self->{stash}{$key};
}
sub var {
    my ($self, $key, $val) = @_;
    $self->{vars}{$key} = $val if @_ > 2;
    return $self->{vars}{$key};
}

1;
