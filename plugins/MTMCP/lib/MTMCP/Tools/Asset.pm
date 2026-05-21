package MTMCP::Tools::Asset;
use strict;
use warnings;
use MT::Asset;

sub list {
    my ($app, $args) = @_;
    my $blog_id = $args->{blog_id} or die "blog_id is required\n";
    my $limit   = $args->{limit}   // 20;
    my %terms = (blog_id => $blog_id);
    $terms{class} = $args->{class} if $args->{class};
    my @assets = MT::Asset->load(\%terms,
        { limit => $limit, sort => 'created_on', direction => 'descend' });
    return [ map { _to_hash($_) } @assets ];
}

sub get {
    my ($app, $args) = @_;
    my $asset_id = $args->{asset_id} or die "asset_id is required\n";
    my $asset = MT::Asset->load($asset_id) or die "Asset not found: $asset_id\n";
    return _to_hash($asset, 1);
}

sub _to_hash {
    my ($asset, $full) = @_;
    my $hash = {
        id         => $asset->id,
        label      => $asset->label // '',
        file_name  => $asset->file_name,
        class      => $asset->class,
        url        => eval { $asset->url } // '',
        created_on => $asset->created_on,
    };
    if ($full) {
        $hash->{file_path}    = $asset->file_path    // '';
        $hash->{mime_type}    = $asset->mime_type    // '';
        $hash->{file_size}    = $asset->file_size    // 0;
        $hash->{image_width}  = $asset->image_width  // 0 if $asset->class eq 'image';
        $hash->{image_height} = $asset->image_height // 0 if $asset->class eq 'image';
    }
    return $hash;
}

1;
