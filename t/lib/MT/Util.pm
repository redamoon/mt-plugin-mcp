package MT::Util;
use strict;
use warnings;

sub make_unique_basename {
    my ($obj) = @_;
    my $base = $obj->basename;
    return $base if defined $base && $base ne '';
    my $title = eval { $obj->title } // eval { $obj->label } // 'page';
    $title =~ s/\s+/-/g;
    return $title;
}

sub make_unique_category_basename {
    my ($obj) = @_;
    my $base = $obj->basename;
    return $base if defined $base && $base ne '';
    my $label = $obj->label // 'folder';
    $label =~ s/\s+/-/g;
    $label = lc $label;
    $label =~ s/[^a-z0-9_-]+/-/g;
    $label = 'folder' if $label eq '';
    return $label;
}

1;
