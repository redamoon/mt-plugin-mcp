package MTMCP::Tools::Widget;
use strict;
use warnings;
use utf8;
use MT::Template;
use MTMCP::Perm;

# ウィジェットセット（type=widgetset）の CRUD と、ウィジェット一覧。
# 個別ウィジェット本文の CRUD は template_*（type: widget）に任せる。
# 割当は modulesets（ウィジェットIDのカンマ区切り）で持ち、save() が text を再生成する。

sub list {
    my ($app, $args) = @_;
    my $blog_id = $args->{blog_id} or die "blog_id is required\n";
    MTMCP::Perm::require_blog_access($app, $blog_id);

    my @sets = MT::Template->load(
        { blog_id => $blog_id, type => 'widgetset' },
        { sort => 'name', direction => 'ascend' },
    );
    _apply_keyword_paging(\@sets, $args, sub { $_[0]->name });

    return [ map { _to_widgetset_hash($_) } @sets ];
}

sub get {
    my ($app, $args) = @_;
    my $ws_id = $args->{widgetset_id} or die "widgetset_id is required\n";
    my $tmpl  = _load_widgetset($ws_id);
    MTMCP::Perm::require_blog_access($app, $tmpl->blog_id);
    return _to_widgetset_hash($tmpl, 1);
}

sub create {
    my ($app, $args) = @_;
    my $blog_id = $args->{blog_id} or die "blog_id is required\n";
    my $name    = $args->{name}    or die "name is required\n";
    MTMCP::Perm::require_blog_permission($app, $blog_id, 'edit_templates', 'テンプレートの編集');

    _assert_no_body($args);

    my $modulesets = '';
    if (defined $args->{widget_ids}) {
        $modulesets = _assert_widget_ids($blog_id, $args->{widget_ids});
    }

    my $tmpl = MT::Template->new;
    $tmpl->blog_id($blog_id);
    $tmpl->name($name);
    $tmpl->type('widgetset');
    $tmpl->modulesets($modulesets);
    $tmpl->save or die $tmpl->errstr . "\n";

    return {
        widgetset_id => $tmpl->id,
        status       => 'created',
        name         => $tmpl->name,
        widgets      => _widgets_from_modulesets($tmpl->modulesets),
    };
}

sub update {
    my ($app, $args) = @_;
    my $ws_id = $args->{widgetset_id} or die "widgetset_id is required\n";
    my $tmpl  = _load_widgetset($ws_id);
    MTMCP::Perm::require_blog_permission($app, $tmpl->blog_id, 'edit_templates', 'テンプレートの編集');

    die "更新する項目がありません（name, widget_ids のいずれかを指定してください）\n"
        unless defined $args->{name} || defined $args->{widget_ids};

    _assert_no_body($args);

    $tmpl->name($args->{name}) if defined $args->{name};
    if (defined $args->{widget_ids}) {
        $tmpl->modulesets(_assert_widget_ids($tmpl->blog_id, $args->{widget_ids}));
    }
    $tmpl->save or die $tmpl->errstr . "\n";

    return {
        widgetset_id => $tmpl->id,
        status       => 'updated',
        name         => $tmpl->name,
        widgets      => _widgets_from_modulesets($tmpl->modulesets),
    };
}

sub remove {
    my ($app, $args) = @_;
    my $ws_id = $args->{widgetset_id} or die "widgetset_id is required\n";
    my $tmpl  = _load_widgetset($ws_id);
    MTMCP::Perm::require_blog_permission($app, $tmpl->blog_id, 'edit_templates', 'テンプレートの編集');
    my $name = $tmpl->name;
    $tmpl->remove or die $tmpl->errstr . "\n";
    return { widgetset_id => $ws_id, status => 'deleted', name => $name };
}

# widgetset_id なし: そのサイトの widget + システム（blog_id=0）。
# widgetset_id あり: そのセットの modulesets 順を自分で復元する。
sub list_widgets {
    my ($app, $args) = @_;
    my $blog_id = $args->{blog_id} or die "blog_id is required\n";
    MTMCP::Perm::require_blog_access($app, $blog_id);

    my @widgets;
    if (my $ws_id = $args->{widgetset_id}) {
        my $set = _load_widgetset($ws_id);
        die "widgetset_id (blog_id: " . $set->blog_id . ") と blog_id ($blog_id) が一致しません\n"
            unless $set->blog_id == $blog_id;
        my $assigned = _widgets_from_modulesets($set->modulesets);
        @widgets = map {
            my $w = MT::Template->load($_->{id});
            $w;
        } @$assigned;
        @widgets = grep { $_ } @widgets;
    }
    else {
        @widgets = MT::Template->load(
            { blog_id => $blog_id, type => 'widget' },
            { sort => 'name', direction => 'ascend' },
        );
        if ($blog_id != 0) {
            push @widgets, MT::Template->load(
                { blog_id => 0, type => 'widget' },
                { sort => 'name', direction => 'ascend' },
            );
            @widgets = sort { ($a->name // '') cmp ($b->name // '') } @widgets;
        }
    }

    _apply_keyword_paging(\@widgets, $args, sub { $_[0]->name });

    return [
        map {
            { id => $_->id, name => $_->name, blog_id => $_->blog_id }
        } @widgets
    ];
}

# ------------------------------------------------------------------
# 内部ヘルパー
# ------------------------------------------------------------------

sub _load_widgetset {
    my ($id) = @_;
    my $tmpl = MT::Template->load($id) or die "WidgetSet not found: $id\n";
    die "指定されたテンプレートはウィジェットセットではありません（id: $id, type: " . ($tmpl->type // '') . "）\n"
        unless ($tmpl->type // '') eq 'widgetset';
    return $tmpl;
}

sub _assert_no_body {
    my ($args) = @_;
    return unless defined $args->{body};
    die "type が widgetset のときは body を指定できません。"
        . "ウィジェットセットの割当は widgetset_create / widgetset_update の widget_ids で指定してください。"
        . "本文は modulesets から自動生成されるため、指定した body は保存されません\n";
}

# 不正 ID は黙って落とさない。順序は引数どおりに modulesets へ書く。
sub _assert_widget_ids {
    my ($blog_id, $ids) = @_;
    die "widget_ids は整数の配列で指定してください\n"
        unless ref $ids eq 'ARRAY';

    my %seen;
    for my $id (@$ids) {
        die "widget_ids の値が不正です: " . (defined $id ? $id : '(undef)') . "\n"
            unless defined $id && $id =~ /^\d+$/;
        die "widget_ids に重複があります: $id\n" if $seen{$id}++;

        my $w = MT::Template->load($id)
            or die "ウィジェットが見つかりません: $id\n";
        die "ID $id はウィジェットではありません（type: " . ($w->type // '') . "）\n"
            unless ($w->type // '') eq 'widget';
        my $w_blog = $w->blog_id // 0;
        die "ウィジェット ID $id はこのサイトに属していません（blog_id: $w_blog）\n"
            unless $w_blog == $blog_id || $w_blog == 0;
    }
    return join ',', @$ids;
}

sub _widgets_from_modulesets {
    my ($modulesets) = @_;
    my @widgets;
    for my $wid (grep { $_ ne '' } split /,/, $modulesets // '') {
        $wid =~ s/\s+//g;
        $wid =~ s/=.*//;    # レガシー id=col.order;
        next unless $wid =~ /^\d+$/;
        my $w = MT::Template->load($wid);
        push @widgets, { id => 0 + $wid, name => $w ? ($w->name // '') : undef };
    }
    return \@widgets;
}

sub _to_widgetset_hash {
    my ($tmpl, $full) = @_;
    my $hash = {
        id      => $tmpl->id,
        name    => $tmpl->name,
        widgets => _widgets_from_modulesets($tmpl->modulesets),
    };
    if ($full) {
        $hash->{blog_id}    = $tmpl->blog_id;
        $hash->{type}       = $tmpl->type;
        $hash->{modulesets} = $tmpl->modulesets // '';
    }
    return $hash;
}

sub _apply_keyword_paging {
    my ($items, $args, $name_of) = @_;
    if (my $keyword = $args->{keyword}) {
        my $kw = lc $keyword;
        @$items = grep { index(lc($name_of->($_) // ''), $kw) >= 0 } @$items;
    }
    if (defined(my $offset = $args->{offset})) {
        $offset = 0 if $offset < 0;
        @$items = $offset < @$items ? splice(@$items, $offset) : ();
    }
    if (defined(my $limit = $args->{limit})) {
        $limit = 0 if $limit < 0;
        @$items = splice(@$items, 0, $limit);
    }
    return;
}

1;
