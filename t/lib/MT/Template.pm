package MT::Template;
use strict;
use warnings;

# MTMCP::Tools::Template / Widget / TemplateMap の単体テスト用スタブ。

our %STORE;
our $NEXT_ID = 1;
our @SAVED;
our @REMOVED;

sub reset {
    %STORE    = ();
    $NEXT_ID  = 1;
    @SAVED    = ();
    @REMOVED  = ();
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
    my $entry = $ctx && $ctx->stash('entry');
    my $title = $entry ? ($entry->title // '') : '';
    return ($self->text // '') . $title;
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
sub new { bless { stash => {} }, shift }
sub stash {
    my ($self, $key, $val) = @_;
    $self->{stash}{$key} = $val if @_ > 2;
    return $self->{stash}{$key};
}

1;
