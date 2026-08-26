package MTMCP::Tools::Tag;
use strict;
use warnings;
use utf8;
use MT::Tag;
use MT::ObjectTag;
use MTMCP::Perm;
use MTMCP::Args;

sub list {
    my ($app, $args) = @_;
    my $blog_id = $args->{blog_id} or die "blog_id is required\n";
    MTMCP::Perm::require_blog_access($app, $blog_id);

    my @obj_tags = MT::ObjectTag->load({ blog_id => $blog_id });
    my %tag_ids = map { $_->tag_id => 1 } @obj_tags;
    return [] unless %tag_ids;

    my @tags = MT::Tag->load(
        { id => [ keys %tag_ids ] },
        { sort => 'name', direction => 'ascend' },
    );
    my %n8d_only;
    for my $ref (MT::Tag->load({ n8d_id => [ map { $_->id } @tags ] })) {
        my $nid = $ref->n8d_id or next;
        $n8d_only{$nid} = 1;
    }
    @tags = grep { !$n8d_only{ $_->id } } @tags;
    return [ map { { id => $_->id, name => $_->name } } @tags ];
}

sub rename {
    my ($app, $args) = @_;
    my $blog_id = $args->{blog_id} or die "blog_id is required\n";
    my $tag_id  = $args->{tag_id}  or die "tag_id is required\n";
    die "name is required\n" unless defined $args->{name};
    my $name = $args->{name};

    MTMCP::Perm::require_blog_permission($app, $blog_id, 'rename_tag', 'タグの名前変更');
    MTMCP::Perm::require_blog_permission($app, $blog_id, 'edit_tags',  'タグの編集');

    my $tag = _load_site_tag($blog_id, $tag_id);
    my $old_name = $tag->name;

    my $n8d = MT::Tag->normalize($name);
    die "Invalid tag name: $name\n" unless defined($n8d) && length($n8d);

    if ($old_name eq $name) {
        return {
            tag_id              => $tag->id,
            old_name            => $old_name,
            name                => $name,
            blog_id             => $blog_id + 0,
            status              => 'unchanged',
            reassigned_count    => 0,
            remaining_elsewhere => _count_elsewhere($tag->id, $blog_id),
        };
    }

    my $new_tag = MT::Tag->load({ name => $name });
    my $used_elsewhere = MT::ObjectTag->exist({
        tag_id  => $tag->id,
        blog_id => { not => $blog_id },
    });

    if (!$new_tag && !$used_elsewhere) {
        $tag->name($name);
        $tag->save or die $tag->errstr . "\n";
        _clear_tag_cache();
        return {
            tag_id              => $tag->id,
            old_name            => $old_name,
            name                => $tag->name,
            blog_id             => $blog_id + 0,
            status              => 'renamed',
            reassigned_count    => 0,
            remaining_elsewhere => 0,
        };
    }

    my $status;
    if (!$new_tag) {
        if ($tag->can('clone')) {
            $new_tag = $tag->clone;
        }
        else {
            $new_tag = MT::Tag->new;
        }
        $new_tag->id(undef);
        $new_tag->name($name);
        $new_tag->n8d_id(0) if $new_tag->can('n8d_id');
        $new_tag->save or die $new_tag->errstr . "\n";
        $status = 'renamed';
    }
    else {
        die "Tag not found\n" if _is_n8d_only($new_tag);
        $status = 'merged';
    }

    my %already_tagged;
    for my $ot (MT::ObjectTag->load({ blog_id => $blog_id, tag_id => $new_tag->id })) {
        $already_tagged{ _ot_sign($ot) } = 1;
    }

    my $reassigned = 0;
    my @ots = MT::ObjectTag->load({ blog_id => $blog_id, tag_id => $tag->id });
    for my $ot (@ots) {
        if ($already_tagged{ _ot_sign($ot) }) {
            _replace_cd_tag_id($ot, $tag->id, $new_tag->id);
            $ot->remove or die $ot->errstr . "\n";
        }
        else {
            _replace_cd_tag_id($ot, $tag->id, $new_tag->id);
            $ot->tag_id($new_tag->id);
            $ot->save or die $ot->errstr . "\n";
            $reassigned++;
        }
    }

    my $remaining = _count_elsewhere($tag->id, $blog_id);
    unless (MT::ObjectTag->exist({ tag_id => $tag->id })) {
        $tag->remove or die $tag->errstr . "\n";
        $remaining = 0;
    }

    _clear_tag_cache();
    return {
        tag_id              => $new_tag->id,
        old_name            => $old_name,
        name                => $new_tag->name,
        blog_id             => $blog_id + 0,
        status              => $status,
        reassigned_count    => $reassigned,
        remaining_elsewhere => $remaining,
    };
}

sub remove {
    my ($app, $args) = @_;
    my $blog_id = $args->{blog_id} or die "blog_id is required\n";
    my $tag_id  = $args->{tag_id}  or die "tag_id is required\n";
    MTMCP::Args::require_confirm($args, "サイトからタグを外す取り消せない操作です");

    MTMCP::Perm::require_blog_permission($app, $blog_id, 'remove_tag', 'タグの削除');

    my $tag  = _load_site_tag($blog_id, $tag_id);
    my $name = $tag->name;

    my @ots = MT::ObjectTag->load({ blog_id => $blog_id, tag_id => $tag->id });
    my $removed_count = scalar @ots;
    for my $ot (@ots) {
        _remove_cd_tag_id($ot);
        $ot->remove or die $ot->errstr . "\n";
    }

    my $remaining = () = MT::ObjectTag->load({ tag_id => $tag->id });
    my $status;
    if ($remaining) {
        $status = 'unlinked';
    }
    else {
        $tag->remove or die $tag->errstr . "\n";
        $status    = 'deleted';
        $remaining = 0;
    }

    _clear_tag_cache();
    return {
        tag_id              => $tag_id + 0,
        name                => $name,
        blog_id             => $blog_id + 0,
        status              => $status,
        removed_count       => $removed_count,
        remaining_elsewhere => $remaining + 0,
    };
}

sub _load_site_tag {
    my ($blog_id, $tag_id) = @_;
    my $tag = MT::Tag->load({ id => $tag_id }) or die "Tag not found\n";
    die "Tag not found\n" if _is_n8d_only($tag);
    MT::ObjectTag->exist({ blog_id => $blog_id, tag_id => $tag->id })
        or die "Tag not found\n";
    return $tag;
}

sub _is_n8d_only {
    my ($tag) = @_;
    return 1 if MT::Tag->load({ n8d_id => $tag->id });
    return 0;
}

sub _ot_sign {
    my ($ot) = @_;
    return join '|', $ot->object_id, $ot->object_datasource, ($ot->cf_id || 0);
}

sub _count_elsewhere {
    my ($tag_id, $blog_id) = @_;
    my @ots = MT::ObjectTag->load({ tag_id => $tag_id });
    return scalar grep { defined $_->blog_id && $_->blog_id != $blog_id } @ots;
}

sub _replace_cd_tag_id {
    my ($ot, $old_id, $new_id) = @_;
    return unless ($ot->object_datasource // '') eq 'content_data';
    return unless $ot->cf_id;
    eval { require MT::ContentData; 1 } or return;
    my $cd = eval {
        MT::ContentData->load({ id => $ot->object_id })
            || MT::ContentData->load($ot->object_id);
    } or return;
    return unless $cd->can('data');
    my $data = $cd->data || {};
    my $cf   = $ot->cf_id;
    my $vals = $data->{$cf};
    return unless ref $vals eq 'ARRAY';
    my @out;
    my %seen;
    for my $id (@$vals) {
        $id = $new_id if defined $id && $id == $old_id;
        next if $seen{$id}++;
        push @out, $id;
    }
    $data->{$cf} = \@out;
    $cd->data($data);
    $cd->save if $cd->can('save');
}

sub _remove_cd_tag_id {
    my ($ot) = @_;
    eval { require MT::ContentData; 1 } or return;
    if (MT::ContentData->can('remove_tag_from_tags_field')) {
        eval { MT::ContentData->remove_tag_from_tags_field($ot) };
        return;
    }
    return unless ($ot->object_datasource // '') eq 'content_data';
    return unless $ot->cf_id;
    my $cd = eval {
        MT::ContentData->load({ id => $ot->object_id })
            || MT::ContentData->load($ot->object_id);
    } or return;
    return unless $cd->can('data');
    my $data = $cd->data || {};
    my $cf   = $ot->cf_id;
    my $vals = $data->{$cf};
    return unless ref $vals eq 'ARRAY';
    my $old = $ot->tag_id;
    $data->{$cf} = [ grep { $_ != $old } @$vals ];
    $cd->data($data);
    $cd->save if $cd->can('save');
}

sub _clear_tag_cache {
    eval { MT::Tag->clear_cache };
}

1;
