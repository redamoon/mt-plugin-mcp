package MTMCP::Tools::ContentData;
use strict;
use warnings;

use constant RELEASE => 2;
use constant HOLD    => 1;

sub list {
    my ($app, $args) = @_;
    my $ct_id   = $args->{content_type_id} or die "content_type_id is required\n";
    my $limit   = $args->{limit}   // 20;
    my $offset  = $args->{offset}  // 0;
    my $status  = $args->{status}  // 'publish';
    my $keyword = $args->{keyword};

    require MT::ContentData;
    require MTMCP::Perm;
    require MTMCP::Search;
    my $check_blog_id = $args->{blog_id};
    unless ($check_blog_id) {
        require MT::ContentType;
        my $ct = MT::ContentType->load($ct_id) or die "ContentType not found: $ct_id\n";
        $check_blog_id = $ct->blog_id;
    }
    MTMCP::Perm::require_blog_access($app, $check_blog_id);

    my %terms = (content_type_id => $ct_id);
    $terms{blog_id} = $args->{blog_id} if $args->{blog_id};
    $terms{status}  = RELEASE() if $status eq 'publish';
    $terms{status}  = HOLD()    if $status eq 'draft';

    my %load_opts = (
        sort      => 'authored_on',
        direction => 'descend',
        limit     => $limit,
        offset    => $offset,
    );
    my $load_terms = \%terms;
    if (defined $keyword && $keyword =~ /\S/) {
        my ($t, $extra) = MTMCP::Search::content_data_like_args(\%terms, $keyword);
        $load_terms = $t;
        %load_opts  = (%load_opts, %$extra) if $extra;
    }

    my @cds = MT::ContentData->load($load_terms, \%load_opts);

    return [ map { _to_hash($_) } @cds ];
}

sub remove {
    my ($app, $args) = @_;
    my $cd_id = $args->{content_data_id} or die "content_data_id is required\n";
    require MTMCP::Args;
    MTMCP::Args::require_confirm($args, "コンテンツデータを削除する取り消せない操作です");
    require MT::ContentData;
    require MTMCP::Perm;
    my $cd = MT::ContentData->load($cd_id) or die "ContentData not found: $cd_id\n";
    MTMCP::Perm::require_blog_access($app, $cd->blog_id);
    $cd->remove or die $cd->errstr . "\n";
    return { content_data_id => $cd_id, status => 'deleted' };
}

sub get {
    my ($app, $args) = @_;
    my $cd_id = $args->{content_data_id} or die "content_data_id is required\n";
    require MT::ContentData;
    require MTMCP::Perm;
    my $cd = MT::ContentData->load($cd_id) or die "ContentData not found: $cd_id\n";
    MTMCP::Perm::require_blog_access($app, $cd->blog_id);
    return _to_hash($cd, 1);
}

sub create {
    my ($app, $args) = @_;
    my $ct_id   = $args->{content_type_id} or die "content_type_id is required\n";
    my $blog_id = $args->{blog_id}         or die "blog_id is required\n";
    require MTMCP::Perm;
    MTMCP::Perm::require_blog_access($app, $blog_id);

    require MT::ContentData;
    require MT::ContentType;
    MT::ContentType->load($ct_id) or die "ContentType not found: $ct_id\n";

    my $cd = MT::ContentData->new;
    $cd->content_type_id($ct_id);
    $cd->blog_id($blog_id);
    $cd->status(($args->{status} // 'draft') eq 'publish' ? RELEASE() : HOLD());

    my $author_id = $args->{author_id};
    unless ($author_id) {
        my $user = eval { $app->user };
        $author_id = ($user && $user->id && !$user->is_anonymous) ? $user->id : 1;
    }
    $cd->author_id($author_id);
    $cd->data($args->{fields} // {});

    $cd->save or die $cd->errstr . "\n";
    return { content_data_id => $cd->id, status => 'created' };
}

sub update {
    my ($app, $args) = @_;
    my $cd_id = $args->{content_data_id} or die "content_data_id is required\n";

    require MT::ContentData;
    require MTMCP::Perm;
    my $cd = MT::ContentData->load($cd_id) or die "ContentData not found: $cd_id\n";
    MTMCP::Perm::require_blog_access($app, $cd->blog_id);

    if (defined $args->{status}) {
        $cd->status($args->{status} eq 'publish' ? RELEASE() : HOLD());
    }
    if ($args->{fields}) {
        my $merged = { %{ $cd->data // {} }, %{ $args->{fields} } };
        $cd->data($merged);
    }

    $cd->save or die $cd->errstr . "\n";
    return { content_data_id => $cd->id, status => 'updated' };
}

sub _to_hash {
    my ($cd, $full) = @_;
    my $hash = {
        id              => $cd->id,
        content_type_id => $cd->content_type_id,
        blog_id         => $cd->blog_id,
        status          => $cd->status == RELEASE() ? 'publish' : 'draft',
        authored_on     => $cd->authored_on,
    };
    if ($full) {
        $hash->{fields} = $cd->data // {};
        require MT::ContentField;
        my @cf_list = MT::ContentField->load({ content_type_id => $cd->content_type_id });
        $hash->{field_labels} = {
            map { $_->id => _field_label($_) } @cf_list
        };
    }
    return $hash;
}

sub _field_label {
    my ($cf) = @_;
    my $opts = eval { $cf->options } // {};
    return $opts->{label} // $cf->name // 'field_' . $cf->id;
}

1;
