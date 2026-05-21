package MTMCP::Tools::Template;
use strict;
use warnings;
use MT::Template;

sub list {
    my ($app, $args) = @_;
    my $blog_id = $args->{blog_id} or die "blog_id is required\n";
    my %terms = (blog_id => $blog_id);
    $terms{type} = $args->{type} if $args->{type};
    my @tmpls = MT::Template->load(\%terms, { sort => 'name', direction => 'ascend' });
    return [ map { _to_hash($_) } @tmpls ];
}

sub get {
    my ($app, $args) = @_;
    my $tmpl_id = $args->{template_id} or die "template_id is required\n";
    my $tmpl = MT::Template->load($tmpl_id) or die "Template not found: $tmpl_id\n";
    return _to_hash($tmpl, 1);
}

sub update {
    my ($app, $args) = @_;
    my $tmpl_id = $args->{template_id} or die "template_id is required\n";
    die "body is required\n" unless defined $args->{body};
    my $tmpl = MT::Template->load($tmpl_id) or die "Template not found: $tmpl_id\n";
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
