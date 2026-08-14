package MTMCP::Tools::TemplateMap;
use strict;
use warnings;
use utf8;
use MT::Template;
use MT::TemplateMap;
use MTMCP::Perm;

# アーカイブテンプレート（テンプレートマップを持てる type）
my %ARCHIVE_TEMPLATE_TYPES = map { $_ => 1 } qw(
    individual page category archive author ct ct_archive
);

sub list {
    my ($app, $args) = @_;
    my $tmpl_id = $args->{template_id} or die "template_id is required\n";
    my $tmpl    = MT::Template->load($tmpl_id) or die "Template not found: $tmpl_id\n";
    MTMCP::Perm::require_blog_access($app, $tmpl->blog_id);
    _assert_is_archive_template($tmpl);

    my %terms = (template_id => $tmpl->id, blog_id => $tmpl->blog_id);
    $terms{archive_type} = $args->{archive_type} if $args->{archive_type};

    my %opts;
    $opts{limit}  = $args->{limit}  if defined $args->{limit};
    $opts{offset} = $args->{offset} if defined $args->{offset};

    my @maps = MT::TemplateMap->load(\%terms, keys %opts ? \%opts : undef);
    return [ map { _to_hash($_) } @maps ];
}

sub get {
    my ($app, $args) = @_;
    my $map_id = $args->{templatemap_id} or die "templatemap_id is required\n";
    my $map    = _load_map($map_id);
    my $tmpl   = _assert_map_belongs_to_template($map);
    MTMCP::Perm::require_blog_access($app, $tmpl->blog_id);
    return _to_hash($map);
}

sub create {
    my ($app, $args) = @_;
    my $tmpl_id      = $args->{template_id}  or die "template_id is required\n";
    my $archive_type = $args->{archive_type} or die "archive_type is required\n";
    my $tmpl         = MT::Template->load($tmpl_id) or die "Template not found: $tmpl_id\n";
    MTMCP::Perm::require_blog_permission($app, $tmpl->blog_id, 'edit_templates', 'テンプレートの編集');

    _assert_is_archive_template($tmpl);
    _assert_archive_type($app, $tmpl, $archive_type);
    _assert_ct_fields($tmpl, $archive_type, $args);

    my $build_type = defined $args->{build_type} ? $args->{build_type} : 1;
    _assert_build_type($build_type);

    my $file_template = $args->{file_template};
    if (!defined $file_template || $file_template eq '') {
        $file_template = _default_file_template($app, $tmpl, $archive_type);
    }

    my $map = MT::TemplateMap->new;
    $map->blog_id($tmpl->blog_id);
    $map->template_id($tmpl->id);
    $map->archive_type($archive_type);
    $map->file_template($file_template);
    $map->build_type($build_type);
    $map->cat_field_id($args->{cat_field_id}) if defined $args->{cat_field_id};
    $map->dt_field_id($args->{dt_field_id})   if defined $args->{dt_field_id};

    my $want_preferred = _is_true($args->{is_preferred});
    my $existing_pref  = MT::TemplateMap->load({
        blog_id      => $tmpl->blog_id,
        archive_type => $archive_type,
        is_preferred => 1,
    });
    $want_preferred = 1 unless $existing_pref;

    if ($want_preferred) {
        $map->prefer(1) or die $map->errstr . "\n";
    }
    else {
        $map->is_preferred(0);
        $map->save or die $map->errstr . "\n";
    }

    _flush_archive_cache($tmpl->blog_id);

    return {
        templatemap_id => $map->id,
        status         => 'created',
        template_id    => $tmpl->id,
        archive_type   => $map->archive_type,
        file_template  => $map->file_template,
        is_preferred   => $map->is_preferred ? 1 : 0,
        build_type     => $map->build_type,
    };
}

sub update {
    my ($app, $args) = @_;
    my $map_id = $args->{templatemap_id} or die "templatemap_id is required\n";
    my $map    = _load_map($map_id);
    my $tmpl   = _assert_map_belongs_to_template($map);
    MTMCP::Perm::require_blog_permission($app, $tmpl->blog_id, 'edit_templates', 'テンプレートの編集');

    my @updatable = qw(archive_type file_template is_preferred build_type cat_field_id dt_field_id);
    die "更新する項目がありません（" . join(', ', @updatable) . " のいずれかを指定してください）\n"
        unless grep { defined $args->{$_} } @updatable;

    if (defined $args->{archive_type}) {
        _assert_archive_type($app, $tmpl, $args->{archive_type});
        $map->archive_type($args->{archive_type});
    }
    if (defined $args->{file_template}) {
        $map->file_template($args->{file_template});
    }
    if (defined $args->{build_type}) {
        _assert_build_type($args->{build_type});
        $map->build_type($args->{build_type});
    }
    if (defined $args->{cat_field_id}) {
        $map->cat_field_id($args->{cat_field_id});
    }
    if (defined $args->{dt_field_id}) {
        $map->dt_field_id($args->{dt_field_id});
    }

    _assert_ct_fields($tmpl, $map->archive_type, {
        cat_field_id => defined $args->{cat_field_id} ? $args->{cat_field_id} : $map->cat_field_id,
        dt_field_id  => defined $args->{dt_field_id}  ? $args->{dt_field_id}  : $map->dt_field_id,
    });

    if (defined $args->{is_preferred}) {
        if (_is_true($args->{is_preferred})) {
            $map->prefer(1) or die $map->errstr . "\n";
        }
        else {
            $map->prefer(0) or die $map->errstr . "\n";
        }
    }
    else {
        $map->save or die $map->errstr . "\n";
    }

    _flush_archive_cache($tmpl->blog_id);

    return {
        templatemap_id => $map->id,
        status         => 'updated',
        template_id    => $tmpl->id,
        archive_type   => $map->archive_type,
        file_template  => $map->file_template,
        is_preferred   => $map->is_preferred ? 1 : 0,
        build_type     => $map->build_type,
    };
}

sub remove {
    my ($app, $args) = @_;
    my $map_id = $args->{templatemap_id} or die "templatemap_id is required\n";
    my $map    = _load_map($map_id);
    my $tmpl   = _assert_map_belongs_to_template($map);
    MTMCP::Perm::require_blog_permission($app, $tmpl->blog_id, 'edit_templates', 'テンプレートの編集');

    my $blog_id = $tmpl->blog_id;
    $map->remove or die $map->errstr . "\n";
    _flush_archive_cache($blog_id);

    return { templatemap_id => $map_id, status => 'deleted' };
}

# template_get から呼ぶ。権限チェックは呼び出し側。
sub list_for_template {
    my ($tmpl) = @_;
    my @maps = MT::TemplateMap->load({ template_id => $tmpl->id });
    return [ map { _to_hash($_) } @maps ];
}

# ------------------------------------------------------------------
# 内部ヘルパー
# ------------------------------------------------------------------

sub _load_map {
    my ($map_id) = @_;
    my $map = MT::TemplateMap->load($map_id) or die "TemplateMap not found: $map_id\n";
    return $map;
}

# マップの親テンプレートを読み、blog_id / template_id の所属を検証する。
sub _assert_map_belongs_to_template {
    my ($map) = @_;
    my $tmpl = MT::Template->load($map->template_id)
        or die "Template not found: " . ($map->template_id // '') . "\n";
    die "テンプレートマップがテンプレートに属していません（templatemap_id: " . $map->id . "）\n"
        unless defined $map->blog_id
        && defined $tmpl->blog_id
        && $map->blog_id == $tmpl->blog_id
        && defined $map->template_id
        && defined $tmpl->id
        && $map->template_id == $tmpl->id;
    return $tmpl;
}

sub _is_archive_template {
    my ($tmpl) = @_;
    my $type = ref($tmpl) ? ($tmpl->type // '') : ($tmpl // '');
    return $ARCHIVE_TEMPLATE_TYPES{$type} ? 1 : 0;
}

sub _assert_is_archive_template {
    my ($tmpl) = @_;
    return if _is_archive_template($tmpl);
    my $type = $tmpl->type // '';
    die "アーカイブテンプレートではないため、テンプレートマップを設定できません（type: $type）\n";
}

# テンプレート type とアーカイブタイプの組み合わせが妥当か、archiver で検証する。
sub _assert_archive_type {
    my ($app, $tmpl, $archive_type) = @_;
    die "archive_type is required\n" unless defined $archive_type && $archive_type ne '';

    my $tmpl_type = $tmpl->type // '';
    _assert_is_archive_template($tmpl);

    my $publisher = _publisher($app, $tmpl);
    my $archiver  = eval { $publisher->archiver($archive_type) };
    die "無効なアーカイブタイプです: $archive_type\n" unless $archiver;

    my $ok;
    if ($tmpl_type eq 'individual') {
        # Individual のみ（entry_based かつ page ではない）
        $ok = $archiver->entry_based && (($archiver->entry_class // '') ne 'page');
    }
    elsif ($tmpl_type eq 'page') {
        $ok = $archiver->entry_based && (($archiver->entry_class // '') eq 'page');
    }
    elsif ($tmpl_type eq 'ct') {
        $ok = $archiver->contenttype_based && !$archiver->contenttype_group_based;
    }
    elsif ($tmpl_type eq 'ct_archive') {
        $ok = $archiver->contenttype_group_based || ($archive_type =~ /^ContentType-/);
    }
    elsif ($tmpl_type eq 'archive' || $tmpl_type eq 'category' || $tmpl_type eq 'author') {
        # Monthly / Weekly / Daily / Yearly / Category / Category-* / Author / Author-*
        # Individual / Page（entry_based）と ContentType 系は不可
        $ok = !$archiver->entry_based
            && !$archiver->contenttype_based
            && !$archiver->contenttype_group_based
            && ($archive_type =~ /^(?:Monthly|Weekly|Daily|Yearly|Category(?:-.*)?|Author(?:-.*)?)$/);
    }

    die "無効なアーカイブタイプです（template type: $tmpl_type, archive_type: $archive_type）\n"
        unless $ok;
    return;
}

sub _assert_ct_fields {
    my ($tmpl, $archive_type, $args) = @_;
    my $tmpl_type = $tmpl->type // '';
    if ($tmpl_type eq 'ct' || $tmpl_type eq 'ct_archive') {
        die "type が ct / ct_archive のときは content_type_id が必要です\n"
            unless $tmpl->content_type_id;
    }
    if (($archive_type // '') eq 'ContentType-Category') {
        die "ContentType-Category アーカイブには cat_field_id が必要です\n"
            unless defined $args->{cat_field_id} && $args->{cat_field_id} ne '';
    }
    return;
}

sub _assert_build_type {
    my ($build_type) = @_;
    die "build_type は 0〜5 の整数で指定してください\n"
        unless defined $build_type && $build_type =~ /^[0-5]$/;
    return;
}

sub _publisher {
    my ($app, $tmpl) = @_;
    if ($app && $app->can('publisher')) {
        my $pub = $app->publisher;
        return $pub if $pub;
    }
    require MT::Blog;
    my $blog = MT::Blog->load($tmpl->blog_id)
        or die "Blog not found: " . $tmpl->blog_id . "\n";
    return $blog->publisher;
}

sub _default_file_template {
    my ($app, $tmpl, $archive_type) = @_;
    my $publisher = _publisher($app, $tmpl);
    my $archiver  = $publisher->archiver($archive_type);
    my @defaults  = $archiver ? $archiver->default_archive_templates : ();
    my ($pick)    = grep { $_->{default} } @defaults;
    $pick ||= $defaults[0];
    return $pick ? ($pick->{template} // '') : '';
}

sub _flush_archive_cache {
    my ($blog_id) = @_;
    require MT::Blog;
    my $blog = MT::Blog->load($blog_id) or return;
    $blog->flush_has_archive_type_cache if $blog->can('flush_has_archive_type_cache');
    return;
}

sub _is_true {
    my ($v) = @_;
    return 0 unless defined $v;
    return 1 if $v;
    return 0;
}

sub _to_hash {
    my ($map) = @_;
    return {
        id            => $map->id,
        template_id   => $map->template_id,
        blog_id       => $map->blog_id,
        archive_type  => $map->archive_type,
        file_template => $map->file_template,
        is_preferred  => $map->is_preferred ? 1 : 0,
        build_type    => $map->build_type,
        cat_field_id  => $map->cat_field_id,
        dt_field_id   => $map->dt_field_id,
    };
}

1;
