package MTMCP::Tools::CategorySet;
use strict;
use warnings;
use utf8;
use MT::CategorySet;
use MT::Category;
use MTMCP::Perm;

sub _load_set {
    my ($category_set_id) = @_;
    return MT::CategorySet->load({ id => $category_set_id });
}

sub _require_set {
    my ($category_set_id) = @_;
    my $set = _load_set($category_set_id)
        or die "CategorySet not found: $category_set_id\n";
    return $set;
}

sub _require_manage {
    my ($app, $blog_id) = @_;
    MTMCP::Perm::require_blog_permission(
        $app, $blog_id, 'manage_category_set', 'カテゴリセットの管理'
    );
}

sub list {
    my ($app, $args) = @_;
    my $blog_id = $args->{blog_id} or die "blog_id is required\n";
    _require_manage($app, $blog_id);

    my @sets = MT::CategorySet->load({ blog_id => $blog_id });
    return [ map { _to_hash($_) } @sets ];
}

sub get {
    my ($app, $args) = @_;
    my $category_set_id = $args->{category_set_id}
        or die "category_set_id is required\n";
    my $set = _require_set($category_set_id);
    _require_manage($app, $set->blog_id);

    my $hash = _to_hash($set);
    my @cats;
    if ($set->can('categories')) {
        @cats = $set->categories;
    }
    else {
        @cats = MT::Category->load({
            blog_id         => $set->blog_id,
            class           => 'category',
            category_set_id => $set->id,
        });
    }
    $hash->{categories} = [
        map {
            {
                id        => $_->id,
                label     => $_->label,
                parent_id => $_->parent || undef,
                basename  => $_->basename,
            }
        } @cats
    ];
    return $hash;
}

sub create {
    my ($app, $args) = @_;
    my $blog_id = $args->{blog_id} or die "blog_id is required\n";
    my $name    = $args->{name}    or die "name is required\n";
    _require_manage($app, $blog_id);

    my $set = MT::CategorySet->new;
    $set->blog_id($blog_id);
    $set->name($name);
    _assert_unique_name($set);

    $set->save or die $set->errstr . "\n";
    return {
        category_set_id => $set->id,
        status          => 'created',
        name            => $set->name,
    };
}

sub update {
    my ($app, $args) = @_;
    my $category_set_id = $args->{category_set_id}
        or die "category_set_id is required\n";
    my $name = $args->{name} or die "name is required\n";
    die "カテゴリセットの更新は name のみです。カテゴリ配列は渡せません。セット内カテゴリは category_create / category_update を使ってください\n"
        if exists $args->{categories};

    my $set = _require_set($category_set_id);
    _require_manage($app, $set->blog_id);
    $set->name($name);
    _assert_unique_name($set);
    $set->save or die $set->errstr . "\n";
    return {
        category_set_id => $set->id,
        status          => 'updated',
        name            => $set->name,
    };
}

sub remove {
    my ($app, $args) = @_;
    my $category_set_id = $args->{category_set_id}
        or die "category_set_id is required\n";
    my $set = _require_set($category_set_id);
    _require_manage($app, $set->blog_id);
    my $name = $set->name;
    $set->remove or die $set->errstr . "\n";
    return {
        category_set_id => $category_set_id,
        status          => 'deleted',
        name            => $name,
    };
}

sub _assert_unique_name {
    my ($set) = @_;
    my $name = $set->name // '';
    return if $name eq '';
    if ($set->can('exist_same_name_in_site')) {
        die "同じサイトに名前 '$name' のカテゴリセットが既に存在します\n"
            if $set->exist_same_name_in_site;
        return;
    }
    my $existing = MT::CategorySet->load({
        name    => $name,
        blog_id => $set->blog_id,
    });
    return unless $existing;
    return if defined $set->id && defined $existing->id && $existing->id == $set->id;
    die "同じサイトに名前 '$name' のカテゴリセットが既に存在します\n";
}

sub _to_hash {
    my ($set) = @_;
    my $count;
    if ($set->can('category_count')) {
        $count = $set->category_count;
    }
    else {
        my @cats = MT::Category->load({
            blog_id         => $set->blog_id,
            class           => 'category',
            category_set_id => $set->id,
        });
        $count = scalar @cats;
    }
    return {
        id             => $set->id,
        name           => $set->name,
        blog_id        => $set->blog_id,
        category_count => $count || 0,
    };
}

1;
