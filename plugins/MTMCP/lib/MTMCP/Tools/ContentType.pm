package MTMCP::Tools::ContentType;
use strict;
use warnings;

sub list {
    my ($app, $args) = @_;
    my $blog_id = $args->{blog_id} or die "blog_id is required\n";
    require MT::ContentType;
    my @cts = MT::ContentType->load({ blog_id => $blog_id });
    return [ map { _to_hash($_) } @cts ];
}

sub get {
    my ($app, $args) = @_;
    my $ct_id = $args->{content_type_id} or die "content_type_id is required\n";
    require MT::ContentType;
    my $ct = MT::ContentType->load($ct_id) or die "ContentType not found: $ct_id\n";
    return _to_hash($ct, 1);
}

sub _to_hash {
    my ($ct, $full) = @_;
    my $hash = {
        id      => $ct->id,
        name    => $ct->name,
        blog_id => $ct->blog_id,
    };
    if ($full) {
        require MT::ContentField;
        my @fields = MT::ContentField->load(
            { content_type_id => $ct->id },
            { sort => 'order', direction => 'ascend' },
        );
        $hash->{fields} = [
            map {
                {
                    id    => $_->id,
                    type  => $_->type,
                    label => _field_label($_),
                }
            } @fields
        ];
    }
    return $hash;
}

sub _field_label {
    my ($cf) = @_;
    my $opts = eval { $cf->options } // {};
    return $opts->{label} // $cf->name // 'field_' . $cf->id;
}

1;
