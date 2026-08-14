package MT::Blog;
use strict;
use warnings;

our %STORE;
our @FLUSHED;
our @SAVED;

sub reset {
    %STORE   = ();
    @FLUSHED = ();
    @SAVED   = ();
}

sub new {
    my $class = shift;
    bless {
        id             => undef,
        name           => 'Test Blog',
        site_path      => '/tmp/mt-site',
        archive_type   => '',
        category_order => '',
    }, $class;
}

sub load {
    my ($class, $id) = @_;
    return unless defined $id && !ref $id;
    return $STORE{$id} if $STORE{$id};
    my $blog = $class->new;
    $blog->{id} = $id;
    $STORE{$id} = $blog;
    return $blog;
}

sub save {
    my $self = shift;
    $STORE{ $self->{id} } = $self if defined $self->{id};
    push @SAVED, $self;
    return 1;
}

sub errstr { 'stub error' }

sub flush_has_archive_type_cache {
    my $self = shift;
    push @FLUSHED, $self->id;
    return 1;
}

sub publisher {
    return MT::Blog::_Publisher->new;
}

for my $field (qw(id name site_path archive_type category_order)) {
    no strict 'refs';
    *$field = sub {
        my $self = shift;
        $self->{$field} = shift if @_;
        return $self->{$field};
    };
}

package MT::Blog::_Publisher;
sub new { bless {}, shift }

sub archive_types {
    return qw(
        Individual Page Monthly Weekly Daily Yearly
        Category Author
        ContentType ContentType-Daily ContentType-Weekly
        ContentType-Monthly ContentType-Yearly
        ContentType-Author ContentType-Category
    );
}

sub archiver {
    my ($self, $at) = @_;
    return MT::Blog::_Archiver->new($at);
}

package MT::Blog::_Archiver;
sub new {
    my ($class, $at) = @_;
    bless { at => $at }, $class;
}
sub entry_based {
    my $at = $_[0]{at} // '';
    return $at eq 'Individual' || $at eq 'Page' ? 1 : 0;
}
sub entry_class {
    my $at = $_[0]{at} // '';
    return $at eq 'Page' ? 'page' : 'entry';
}
sub contenttype_based {
    my $at = $_[0]{at} // '';
    return $at eq 'ContentType' ? 1 : 0;
}
sub contenttype_group_based {
    my $at = $_[0]{at} // '';
    return $at =~ /^ContentType-/ ? 1 : 0;
}
sub contenttype_category_based {
    my $at = $_[0]{at} // '';
    return $at eq 'ContentType-Category' ? 1 : 0;
}
sub default_archive_templates {
    my $at = $_[0]{at} // '';
    if ($at eq 'Individual') {
        return (
            { default => 1, template => '%y/%m/%-f' },
            { template => '%-c/%-f' },
        );
    }
    if ($at eq 'Page') {
        return ( { default => 1, template => '%-c/%-f' } );
    }
    return ( { default => 1, template => '%y/%m/index.html' } );
}

1;
