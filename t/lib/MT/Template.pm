package MT::Template;
use strict;
use warnings;

# MTMCP::Tools::Template の単体テスト用スタブ。
# 実 MT コアは本リポジトリに含まれないため、create/update の分岐だけを検証する。

our %STORE;
our $NEXT_ID = 1;
our @SAVED;

sub reset {
    %STORE   = ();
    $NEXT_ID = 1;
    @SAVED   = ();
}

sub new {
    my $class = shift;
    bless {
        id          => undef,
        blog_id     => undef,
        name        => undef,
        type        => undef,
        text        => undef,
        outfile     => undef,
        identifier  => undef,
        build_type  => undef,
        rebuild_me  => undef,
    }, $class;
}

sub load {
    my ($class, $id) = @_;
    return unless defined $id && !ref $id;
    return $STORE{$id};
}

sub save {
    my $self = shift;
    $self->{id} = $NEXT_ID++ unless defined $self->{id};
    $STORE{ $self->{id} } = $self;
    push @SAVED, $self;
    return 1;
}

sub errstr { 'stub error' }

sub compile { 1 }
sub errors  { [] }

sub context {
    return MT::Template::_Context->new;
}

sub build {
    my ($self, $ctx) = @_;
    my $entry = $ctx && $ctx->stash('entry');
    my $title = $entry ? ($entry->title // '') : '';
    return ($self->text // '') . $title;
}

for my $field (qw(id blog_id name type text outfile identifier build_type rebuild_me)) {
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
