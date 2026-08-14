package MTMCP::Tools::Category;
use strict;
use warnings;
use utf8;
use MT::Category;
use MTMCP::Perm;

use constant LABEL_MAX_CHARS => 100;

# mt_category は Category と Folder で共有される。スカラー load / { id => $id }
# は class フィルタを通さないため、フォルダ ID でもオブジェクトが返る。
sub _load_category {
    my ($category_id) = @_;
    return MT::Category->load({ id => $category_id, class => 'category' });
}

sub _require_article_category {
    my ($category_id) = @_;
    my $cat = _load_category($category_id)
        or die "Category not found: $category_id\n";
    die "記事カテゴリではありません\n" if $cat->category_set_id;
    return $cat;
}

sub _reject_category_set_id {
    my ($args) = @_;
    return unless exists $args->{category_set_id};
    die "カテゴリセットのカテゴリはこのツールでは扱えません\n"
        if $args->{category_set_id};
}

sub list {
    my ($app, $args) = @_;
    my $blog_id = $args->{blog_id} or die "blog_id is required\n";
    MTMCP::Perm::require_blog_access($app, $blog_id);

    my %terms = (
        blog_id         => $blog_id,
        class           => 'category',
        category_set_id => 0,
    );
    $terms{parent} = $args->{parent_id} || 0 if defined $args->{parent_id};

    my @cats = MT::Category->load(\%terms, { sort => 'label', direction => 'ascend' });
    return [ map { _to_hash($_) } @cats ];
}

sub get {
    my ($app, $args) = @_;
    my $category_id = $args->{category_id} or die "category_id is required\n";
    my $cat = _require_article_category($category_id);
    MTMCP::Perm::require_blog_access($app, $cat->blog_id);
    my $hash = _to_hash($cat);
    $hash->{blog_id} = $cat->blog_id;
    return $hash;
}

sub create {
    my ($app, $args) = @_;
    my $blog_id = $args->{blog_id} or die "blog_id is required\n";
    my $label   = $args->{label}   or die "label is required\n";
    _assert_label($label);
    _reject_category_set_id($args);
    MTMCP::Perm::require_blog_permission($app, $blog_id, 'save_category', 'カテゴリの管理');

    my $cat = MT::Category->new;
    $cat->blog_id($blog_id);
    $cat->label($label);
    $cat->description($args->{description}) if defined $args->{description};
    $cat->class('category');
    $cat->category_set_id(0);

    if ($args->{parent_id}) {
        $cat->parent(_resolve_parent($args->{parent_id}, $blog_id, undef));
    }
    else {
        $cat->parent(0);
    }

    if (defined $args->{basename} && $args->{basename} ne '') {
        $cat->basename($args->{basename});
    }
    else {
        require MT::Util;
        $cat->basename(MT::Util::make_unique_category_basename($cat));
    }

    _assert_unique_label($cat);
    $cat->save or die $cat->errstr . "\n";
    return {
        category_id     => $cat->id,
        status          => 'created',
        label           => $cat->label,
        parent_id       => $cat->parent || undef,
        basename        => $cat->basename,
        category_set_id => $cat->category_set_id || 0,
    };
}

sub update {
    my ($app, $args) = @_;
    my $category_id = $args->{category_id} or die "category_id is required\n";
    my $cat = _require_article_category($category_id);
    _reject_category_set_id($args);
    MTMCP::Perm::require_blog_permission($app, $cat->blog_id, 'save_category', 'カテゴリの管理');

    my @updatable = qw(label basename parent_id description);
    die "更新する項目がありません（" . join(', ', @updatable) . " のいずれかを指定してください）\n"
        unless grep { exists $args->{$_} } @updatable;

    if (defined $args->{label}) {
        die "label is required\n" if $args->{label} eq '';
        _assert_label($args->{label});
        $cat->label($args->{label});
    }
    $cat->basename($args->{basename})       if defined $args->{basename};
    $cat->description($args->{description}) if defined $args->{description};

    if (exists $args->{parent_id}) {
        if ($args->{parent_id}) {
            $cat->parent(_resolve_parent($args->{parent_id}, $cat->blog_id, $cat));
        }
        else {
            $cat->parent(0);
        }
    }

    _assert_unique_label($cat);
    $cat->save or die $cat->errstr . "\n";
    return {
        category_id     => $cat->id,
        status          => 'updated',
        label           => $cat->label,
        parent_id       => $cat->parent || undef,
        basename        => $cat->basename,
        category_set_id => $cat->category_set_id || 0,
    };
}

sub remove {
    my ($app, $args) = @_;
    my $category_id = $args->{category_id} or die "category_id is required\n";
    my $cat = _require_article_category($category_id);
    MTMCP::Perm::require_blog_permission($app, $cat->blog_id, 'delete_category', 'カテゴリの管理');
    my $label = $cat->label;
    eval {
        require MT::CMS::Category;
        MT::CMS::Category::pre_delete($app, $cat);
    };
    $cat->remove or die $cat->errstr . "\n";
    return { category_id => $category_id, status => 'deleted', label => $label };
}

sub permutate {
    my ($app, $args) = @_;
    my $blog_id = $args->{blog_id} or die "blog_id is required\n";
    my $ids     = $args->{category_ids};
    die "category_ids is required\n" unless defined $ids && ref $ids eq 'ARRAY';
    MTMCP::Perm::require_blog_permission($app, $blog_id, 'edit_categories', 'カテゴリの管理');

    my @cats = MT::Category->load({
        blog_id         => $blog_id,
        class           => 'category',
        category_set_id => 0,
    });
    my %scope = map { $_->id => 1 } @cats;
    my %given;
    for my $id (@$ids) {
        die "category_ids は当該ブログの記事カテゴリ全件と一致する必要があります。先に category_list で全 ID を取得してください\n"
            unless $scope{$id};
        $given{$id} = 1;
    }
    die "category_ids は当該ブログの記事カテゴリ全件と一致する必要があります。先に category_list で全 ID を取得してください\n"
        unless keys(%given) == keys(%scope) && @$ids == keys(%scope);

    require MT::Blog;
    my $blog = MT::Blog->load($blog_id) or die "Blog not found: $blog_id\n";
    $blog->category_order(join ',', @$ids);
    $blog->save or die $blog->errstr . "\n";
    return {
        blog_id        => $blog_id,
        status         => 'permutated',
        category_ids   => [ @$ids ],
        category_order => $blog->category_order,
    };
}

sub _assert_label {
    my ($label) = @_;
    die "label は100文字以内である必要があります\n"
        if length($label) > LABEL_MAX_CHARS;
}

sub _resolve_parent {
    my ($parent_id, $blog_id, $cat) = @_;
    my $parent = _require_article_category($parent_id);
    die "親カテゴリは同じブログの記事カテゴリである必要があります\n"
        unless $parent->blog_id == $blog_id;
    if ($cat && defined $cat->id) {
        die "カテゴリ自身を親に指定することはできません\n"
            if $parent->id == $cat->id;
        die "カテゴリの子孫を親に指定することはできません\n"
            if $cat->is_ancestor($parent);
    }
    return $parent->id;
}

sub _assert_unique_label {
    my ($cat) = @_;
    my $label = $cat->label // '';
    return if $label eq '';
    my @others = MT::Category->load({
        blog_id         => $cat->blog_id,
        parent          => $cat->parent || 0,
        label           => $label,
        class           => 'category',
        category_set_id => 0,
    });
    for my $other (@others) {
        next if defined $cat->id && defined $other->id && $other->id == $cat->id;
        die "同じ親カテゴリ配下にラベル '$label' のカテゴリが既に存在します\n";
    }
}

sub _to_hash {
    my ($cat) = @_;
    return {
        id              => $cat->id,
        label           => $cat->label,
        parent_id       => $cat->parent || undef,
        basename        => $cat->basename,
        description     => $cat->description,
        category_set_id => $cat->category_set_id || 0,
    };
}

1;
