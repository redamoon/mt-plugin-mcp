package MT::Page;
use strict;
use warnings;
use MT::Entry;

our @ISA = qw(MT::Entry);

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new;
    $self->{class} = 'page';
    return $self;
}

sub load {
    my ($class, $terms, $args) = @_;
    if (ref $terms eq 'HASH' && !exists $terms->{id} && !exists $terms->{class}) {
        $terms = { %$terms, class => 'page' };
    }
    return $class->SUPER::load($terms, $args);
}

sub save {
    my $self = shift;
    $self->{class} = 'page';
    return $self->SUPER::save;
}

sub folder {
    my $self = shift;
    require MT::Placement;
    my ($p) = MT::Placement->load({ entry_id => $self->id, is_primary => 1 });
    $p ||= (MT::Placement->load({ entry_id => $self->id }))[0];
    return unless $p;
    require MT::Folder;
    return MT::Folder->load({ id => $p->category_id, class => 'folder' });
}

1;
