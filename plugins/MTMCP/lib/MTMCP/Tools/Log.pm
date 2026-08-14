package MTMCP::Tools::Log;
use strict;
use warnings;
use utf8;
use MT::Log;
use MTMCP::Perm;

use constant MESSAGE_LIST_LIMIT => 500;
use constant MAX_LIMIT          => 200;

my %LEVEL_TO_IDS = (
    debug                         => [ MT::Log::DEBUG() ],
    info                          => [ MT::Log::INFO() ],
    notice                        => [ MT::Log::NOTICE() ],
    warning                       => [ MT::Log::WARNING() ],
    error                         => [ MT::Log::ERROR() ],
    security                      => [ MT::Log::SECURITY() ],
    security_or_error             => [ MT::Log::SECURITY(), MT::Log::ERROR() ],
    security_or_error_or_warning  => [ MT::Log::SECURITY(), MT::Log::ERROR(), MT::Log::WARNING() ],
    not_debug                     => [
        MT::Log::SECURITY(), MT::Log::ERROR(), MT::Log::WARNING(),
        MT::Log::NOTICE(),   MT::Log::INFO(),
    ],
    debug_or_error                => [ MT::Log::DEBUG(), MT::Log::ERROR() ],
);

my %ID_TO_LEVEL = (
    MT::Log::DEBUG()    => 'debug',
    MT::Log::INFO()     => 'info',
    MT::Log::NOTICE()   => 'notice',
    MT::Log::WARNING()  => 'warning',
    MT::Log::ERROR()    => 'error',
    MT::Log::SECURITY() => 'security',
);

sub list {
    my ($app, $args) = @_;
    my $blog_id = $args->{blog_id};
    my $allowed = MTMCP::Perm::require_log_view($app, $blog_id);

    my $limit  = $args->{limit}  // 20;
    my $offset = $args->{offset} // 0;
    $limit  = 20 if !$limit || $limit < 1;
    $limit  = MAX_LIMIT if $limit > MAX_LIMIT;
    $offset = 0 if !defined $offset || $offset < 0;

    my %terms = ( class => '*' );
    if ($blog_id) {
        $terms{blog_id} = $blog_id;
    }
    elsif ($allowed && ref $allowed eq 'ARRAY') {
        $terms{blog_id} = $allowed;
    }

    if (defined $args->{class} && $args->{class} ne '') {
        $terms{class} = $args->{class};
    }
    if (defined $args->{category} && $args->{category} ne '') {
        $terms{category} = $args->{category};
    }

    if (defined $args->{level} && $args->{level} ne '') {
        my $ids = _level_terms($args->{level});
        $terms{level} = @$ids == 1 ? $ids->[0] : $ids;
    }

    _apply_date_range(\%terms, $args);

    if (defined $args->{keyword} && $args->{keyword} ne '') {
        my $like = '%' . _escape_like($args->{keyword}) . '%';
        $terms{'-or'} = [
            { message => { like => $like } },
            { ip      => { like => $like } },
        ];
    }

    my %range_opts;
    $range_opts{range_incl} = { created_on => 1 } if ref($terms{created_on}) eq 'ARRAY';
    my $total = MT::Log->count(\%terms, \%range_opts);

    my %opts = (
        %range_opts,
        sort      => 'created_on',
        direction => 'descend',
        limit     => $limit,
        offset    => $offset,
    );
    my @logs  = MT::Log->load(\%terms, \%opts);
    my $cache = {};
    return {
        total => $total,
        items => [ map { _to_hash($_, 0, $cache) } @logs ],
    };
}

sub get {
    my ($app, $args) = @_;
    my $log_id = $args->{log_id} or die "log_id is required\n";
    my $log = MT::Log->load({ id => $log_id, class => '*' })
        or die "Log not found: $log_id\n";

    my $allowed = MTMCP::Perm::require_log_view($app, $log->blog_id);
    if ($allowed && ref $allowed eq 'ARRAY') {
        my $bid = $log->blog_id // 0;
        unless (grep { $_ == $bid } @$allowed) {
            die "この操作を行う権限がありません（blog_id: $bid）\n";
        }
    }
    return _to_hash($log, 1);
}

sub _level_terms {
    my ($level) = @_;
    my $ids = $LEVEL_TO_IDS{$level};
    die "Unknown log level: $level\n" unless $ids;
    return $ids;
}

sub _apply_date_range {
    my ($terms, $args) = @_;
    my $from = $args->{date_from};
    my $to   = $args->{date_to};
    return unless (defined $from && $from ne '') || (defined $to && $to ne '');

    my $from_ts = (defined $from && $from ne '')
        ? _ymd_to_ts($from, 'date_from', 0)
        : '00000101000000';
    my $to_ts = (defined $to && $to ne '')
        ? _ymd_to_ts($to, 'date_to', 1)
        : '99991231235959';
    $terms->{created_on} = [ $from_ts, $to_ts ];
}

sub _ymd_to_ts {
    my ($ymd, $field, $end) = @_;
    die "$field must be YYYY-MM-DD\n" unless $ymd =~ /^(\d{4})-(\d{2})-(\d{2})$/;
    return $end ? "$1$2${3}235959" : "$1$2${3}000000";
}

sub _escape_like {
    my ($s) = @_;
    $s =~ s/([%_\\])/\\$1/g;
    return $s;
}

sub _level_to_name {
    my ($id) = @_;
    return $ID_TO_LEVEL{ $id // -1 } // 'info';
}

sub _author_name {
    my ($author_id, $cache) = @_;
    return '' unless $author_id;
    return $cache->{$author_id} if $cache && exists $cache->{$author_id};
    my $author = eval {
        require MT::Author;
        MT::Author->load($author_id);
    };
    my $name = $author ? ($author->nickname || $author->name || '') : '';
    $cache->{$author_id} = $name if $cache;
    return $name;
}

sub _to_hash {
    my ($log, $full, $cache) = @_;
    my $message = $log->message // '';
    my $truncated = 0;
    if (!$full && length($message) > MESSAGE_LIST_LIMIT) {
        $message   = substr($message, 0, MESSAGE_LIST_LIMIT);
        $truncated = 1;
    }
    my $hash = {
        id          => $log->id,
        blog_id     => $log->blog_id // 0,
        level       => _level_to_name($log->level),
        class       => $log->class,
        category    => $log->category,
        message     => $message,
        truncated   => $truncated ? 1 : 0,
        ip          => $log->ip,
        author_id   => $log->author_id,
        author_name => _author_name($log->author_id, $cache),
        created_on  => $log->created_on,
    };
    if ($full) {
        delete $hash->{truncated};
        $hash->{metadata} = $log->metadata;
    }
    return $hash;
}

1;
