package MTMCP::Tools::Template;
use strict;
use warnings;
use MT::Template;
use MTMCP::Perm;

sub list {
    my ($app, $args) = @_;
    my $blog_id = $args->{blog_id} or die "blog_id is required\n";
    MTMCP::Perm::require_blog_access($app, $blog_id);
    my $keyword = $args->{keyword};
    my %terms = (blog_id => $blog_id);
    $terms{type} = $args->{type} if $args->{type};
    my @tmpls = MT::Template->load(\%terms, { sort => 'name', direction => 'ascend' });

    if ($keyword) {
        my $kw = lc $keyword;
        @tmpls = grep { index(lc($_->name // ''), $kw) >= 0 } @tmpls;
    }
    if (defined(my $offset = $args->{offset})) {
        @tmpls = splice(@tmpls, $offset);
    }
    if (defined(my $limit = $args->{limit})) {
        @tmpls = splice(@tmpls, 0, $limit);
    }

    return [ map { _to_hash($_) } @tmpls ];
}

sub create {
    my ($app, $args) = @_;
    my $blog_id = $args->{blog_id} or die "blog_id is required\n";
    my $name    = $args->{name}    or die "name is required\n";
    my $type    = $args->{type}    or die "type is required\n";
    MTMCP::Perm::require_blog_access($app, $blog_id);

    my $tmpl = MT::Template->new;
    $tmpl->blog_id($blog_id);
    $tmpl->name($name);
    $tmpl->type($type);
    $tmpl->text($args->{body} // '');
    $tmpl->outfile($args->{outfile}) if defined $args->{outfile};
    $tmpl->save or die $tmpl->errstr . "\n";

    return { template_id => $tmpl->id, status => 'created', name => $tmpl->name, type => $tmpl->type };
}

sub remove {
    my ($app, $args) = @_;
    my $tmpl_id = $args->{template_id} or die "template_id is required\n";
    my $tmpl = MT::Template->load($tmpl_id) or die "Template not found: $tmpl_id\n";
    MTMCP::Perm::require_blog_access($app, $tmpl->blog_id);
    my $name = $tmpl->name;
    $tmpl->remove or die $tmpl->errstr . "\n";
    return { template_id => $tmpl_id, status => 'deleted', name => $name };
}

sub get {
    my ($app, $args) = @_;
    my $tmpl_id = $args->{template_id} or die "template_id is required\n";
    my $tmpl = MT::Template->load($tmpl_id) or die "Template not found: $tmpl_id\n";
    MTMCP::Perm::require_blog_access($app, $tmpl->blog_id);
    return _to_hash($tmpl, 1);
}

sub update {
    my ($app, $args) = @_;
    my $tmpl_id = $args->{template_id} or die "template_id is required\n";
    die "body is required\n" unless defined $args->{body};
    my $tmpl = MT::Template->load($tmpl_id) or die "Template not found: $tmpl_id\n";
    MTMCP::Perm::require_blog_access($app, $tmpl->blog_id);
    $tmpl->text($args->{body});
    $tmpl->save or die $tmpl->errstr . "\n";
    return { template_id => $tmpl->id, status => 'updated', name => $tmpl->name };
}

sub _to_hash {
    my ($tmpl, $full) = @_;
    my $hash = { id => $tmpl->id, name => $tmpl->name, type => $tmpl->type };
    $hash->{body} = $tmpl->text // '' if $full;
    return $hash;
}

1;
