package MTMCP::Tools::Folder;
use strict;
use warnings;
use utf8;
use MT::Folder;
use MTMCP::Perm;
use MTMCP::Args;

use constant LABEL_MAX_CHARS => 100;

# mt_category は Category と Folder で共有される。スカラー load / { id => $id }
# は class フィルタを通さないため、カテゴリ ID でもオブジェクトが返る。
sub _load_folder {
    my ($folder_id) = @_;
    return MT::Folder->load({ id => $folder_id, class => 'folder' });
}

sub list {
    my ($app, $args) = @_;
    my $blog_id = $args->{blog_id} or die "blog_id is required\n";
    MTMCP::Perm::require_blog_access($app, $blog_id);

    my %terms = (blog_id => $blog_id);
    $terms{parent} = $args->{parent_id} || 0 if defined $args->{parent_id};

    my $keyword = $args->{keyword};
    my %load_opts = ( sort => 'label', direction => 'ascend' );
    unless ($keyword) {
        $load_opts{limit}  = $args->{limit}  if defined $args->{limit};
        $load_opts{offset} = $args->{offset} if defined $args->{offset};
    }

    my @folders = MT::Folder->load(\%terms, \%load_opts);

    if ($keyword) {
        my $kw = lc $keyword;
        @folders = grep {
            index(lc($_->label // ''), $kw) >= 0
                || index(lc($_->basename // ''), $kw) >= 0
        } @folders;
        my $offset = $args->{offset} // 0;
        my $limit  = $args->{limit};
        @folders = splice(@folders, $offset, defined $limit ? $limit : scalar @folders);
    }

    return [ map { _to_hash($_) } @folders ];
}

sub get {
    my ($app, $args) = @_;
    my $folder_id = $args->{folder_id} or die "folder_id is required\n";
    my $folder = _load_folder($folder_id) or die "Folder not found: $folder_id\n";
    MTMCP::Perm::require_blog_access($app, $folder->blog_id);
    my $hash = _to_hash($folder);
    $hash->{blog_id} = $folder->blog_id;
    $hash->{class}   = 'folder';
    return $hash;
}

sub create {
    my ($app, $args) = @_;
    my $blog_id = $args->{blog_id} or die "blog_id is required\n";
    my $label   = $args->{label}   or die "label is required\n";
    _assert_label($label);
    MTMCP::Perm::require_blog_permission($app, $blog_id, 'save_folder', 'フォルダの管理');

    my $folder = MT::Folder->new;
    $folder->blog_id($blog_id);
    $folder->label($label);
    $folder->description($args->{description}) if defined $args->{description};
    $folder->class('folder');

    if ($args->{parent_id}) {
        $folder->parent(_resolve_parent($args->{parent_id}, $blog_id, undef));
    }
    else {
        $folder->parent(0);
    }

    if (defined $args->{basename} && $args->{basename} ne '') {
        $folder->basename($args->{basename});
    }
    else {
        require MT::Util;
        $folder->basename(MT::Util::make_unique_category_basename($folder));
    }
    _assert_unique_basename($folder);

    $folder->save or die $folder->errstr . "\n";
    return {
        folder_id => $folder->id,
        status    => 'created',
        label     => $folder->label,
        basename  => $folder->basename,
    };
}

sub update {
    my ($app, $args) = @_;
    my $folder_id = $args->{folder_id} or die "folder_id is required\n";
    my $folder = _load_folder($folder_id) or die "Folder not found: $folder_id\n";
    MTMCP::Perm::require_blog_permission($app, $folder->blog_id, 'save_folder', 'フォルダの管理');

    my @updatable = qw(label basename parent_id description);
    die "更新する項目がありません（" . join(', ', @updatable) . " のいずれかを指定してください）\n"
        unless grep { exists $args->{$_} } @updatable;

    if (defined $args->{label}) {
        die "label is required\n" if $args->{label} eq '';
        _assert_label($args->{label});
        $folder->label($args->{label});
    }
    $folder->basename($args->{basename})       if defined $args->{basename};
    $folder->description($args->{description}) if defined $args->{description};

    if (exists $args->{parent_id}) {
        if ($args->{parent_id}) {
            $folder->parent(_resolve_parent($args->{parent_id}, $folder->blog_id, $folder));
        }
        else {
            $folder->parent(0);
        }
    }

    _assert_unique_basename($folder);
    $folder->save or die $folder->errstr . "\n";
    return {
        folder_id => $folder->id,
        status    => 'updated',
        label     => $folder->label,
        basename  => $folder->basename,
    };
}

sub remove {
    my ($app, $args) = @_;
    my $folder_id = $args->{folder_id} or die "folder_id is required\n";
    MTMCP::Args::require_confirm($args, "フォルダを削除する取り消せない操作です");
    my $folder = _load_folder($folder_id) or die "Folder not found: $folder_id\n";
    MTMCP::Perm::require_blog_permission($app, $folder->blog_id, 'delete_folder', 'フォルダの管理');
    my $label = $folder->label;
    $folder->remove or die $folder->errstr . "\n";
    return { folder_id => $folder_id, status => 'deleted', label => $label };
}

sub _assert_label {
    my ($label) = @_;
    die "label は100文字以内である必要があります\n"
        if length($label) > LABEL_MAX_CHARS;
}

sub _resolve_parent {
    my ($parent_id, $blog_id, $folder) = @_;
    my $parent = _load_folder($parent_id)
        or die "Folder not found: $parent_id\n";
    die "親フォルダは同じブログのフォルダである必要があります\n"
        unless $parent->blog_id == $blog_id;
    if ($folder && defined $folder->id) {
        die "フォルダ自身を親に指定することはできません\n"
            if $parent->id == $folder->id;
        die "フォルダの子孫を親に指定することはできません\n"
            if $folder->is_ancestor($parent);
    }
    return $parent->id;
}

sub _assert_unique_basename {
    my ($folder) = @_;
    my $basename = $folder->basename // '';
    return if $basename eq '';
    my @others = MT::Folder->load({
        blog_id  => $folder->blog_id,
        parent   => $folder->parent || 0,
        basename => $basename,
        class    => 'folder',
    });
    for my $other (@others) {
        next if defined $folder->id && defined $other->id && $other->id == $folder->id;
        die "同じ親フォルダ配下に basename '$basename' のフォルダが既に存在します\n";
    }
}

sub _to_hash {
    my ($folder) = @_;
    return {
        id          => $folder->id,
        label       => $folder->label,
        basename    => $folder->basename,
        parent_id   => $folder->parent || undef,
        description => $folder->description,
    };
}

1;
