package MTMCP::Search;
use strict;
use warnings;

# ObjectDriver の { like => } 向けヘルパー。
# SQL は組み立てず、プレースホルダ経由の部分一致だけを返す。
# base terms（blog_id / status / class / type / content_type_id）は
# 常に外側の AND に残し、LIKE の OR には入れない。

sub escape_like {
    my ($s) = @_;
    $s = '' unless defined $s;
    $s =~ s/([%_\\])/\\$1/g;
    return $s;
}

sub like_pattern {
    my ($s) = @_;
    return '%' . escape_like(defined $s ? $s : '') . '%';
}

sub _keyword_specified {
    my ($s) = @_;
    return defined $s && $s =~ /\S/;
}

sub and_like_or {
    my ($base_terms, $keyword, @columns) = @_;
    $base_terms ||= {};
    unless (_keyword_specified($keyword)) {
        return { %$base_terms };
    }
    die "and_like_or requires at least one column\n" unless @columns;

    my $pat = like_pattern($keyword);
    my @or;
    for my $i (0 .. $#columns) {
        push @or, '-or' if $i;
        push @or, { $columns[$i] => { like => $pat } };
    }
    return [
        { %$base_terms },
        '-and',
        \@or,
    ];
}

# ContentData は data blob に LIKE しない。
# ラベル列 OR ContentFieldIndex(value_varchar / value_text) の JOIN。
# 戻り値: ($terms, $load_args_hash)
sub content_data_like_args {
    my ($base_terms, $keyword) = @_;
    $base_terms ||= {};
    unless (_keyword_specified($keyword)) {
        return ({ %$base_terms }, {});
    }

    my $pat = like_pattern($keyword);
    my $cf_or = [
        { value_varchar => { like => $pat } },
        '-or',
        { value_text    => { like => $pat } },
    ];
    my $terms = [
        { %$base_terms },
        '-and',
        [
            { label => { like => $pat } },
            '-or',
            $cf_or,
        ],
    ];

    require MT::ContentFieldIndex;
    my $load_args = {
        join => MT::ContentFieldIndex->join_on(
            'content_data_id',
            $cf_or,
            { unique => 1 },
        ),
    };
    return ($terms, $load_args);
}

1;
