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

sub create {
    my ($app, $args) = @_;
    my $blog_id = $args->{blog_id} or die "blog_id is required\n";
    my $name    = $args->{name}    or die "name is required\n";

    require MT::ContentType;
    require MT::ContentField;

    my @fields_def = @{ $args->{fields} // [
        { type => 'single_line_text', label => 'タイトル', order => 1, label_field => 1 },
        { type => 'multi_line_text',  label => '本文',     order => 2 },
    ] };

    my $exists = MT::ContentType->count({ name => $name, blog_id => $blog_id });
    die "ContentType already exists: $name\n" if $exists;

    my $registry = MT->registry('content_field_types');
    my @field_objects;
    my $data_label_uid;

    for my $f (@fields_def) {
        my $cf = MT::ContentField->new;
        $cf->blog_id($blog_id);
        $cf->type($f->{type});
        $cf->name($f->{label});
        $cf->required($f->{required} ? 1 : 0);
        $cf->save or die $cf->errstr . "\n";

        my $type_label = $registry->{ $f->{type} }{label};
        $type_label = $type_label->() if ref($type_label) eq 'CODE';

        push @field_objects, {
            object => $cf,
            store  => {
                id         => $cf->id,
                unique_id  => $cf->unique_id,
                order      => $f->{order} // scalar(@field_objects),
                type       => $f->{type},
                type_label => $type_label,
                options    => { label => $f->{label} },
            },
        };
        $data_label_uid = $cf->unique_id if $f->{label_field};
    }

    my $ct = MT::ContentType->new;
    $ct->blog_id($blog_id);
    $ct->name($name);
    $ct->description($args->{description} // '');
    $ct->user_disp_option(1);
    $ct->data_label($data_label_uid) if $data_label_uid;
    $ct->fields([ map { $_->{store} } @field_objects ]);
    $ct->save or die $ct->errstr . "\n";

    for my $fo (@field_objects) {
        my $cf = $fo->{object};
        $cf->content_type_id($ct->id);
        $cf->save or die $cf->errstr . "\n";
    }

    return {
        content_type_id => $ct->id,
        status          => 'created',
        name            => $ct->name,
        fields          => [ map { +{ id => $_->{store}{id}, label => $_->{store}{options}{label}, type => $_->{store}{type} } } @field_objects ],
    };
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
            { sort => 'id', direction => 'ascend' },
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
