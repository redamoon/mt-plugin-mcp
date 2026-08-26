package MTMCP::Author;
use strict;
use warnings;
use utf8;

# author_id から MT::Author を引く共通ヘルパー。
# ツール側にコピーされていた「require + eval 付き load + メモ化」だけをここに集める。
#
# 表示名にどのフィールドを使うか（name のみ / nickname 優先）と、
# 見つからないときの既定値は呼び出し側ごとに違うため、ここでは決めない。
# entry_export の AUTHOR: 行は name のみ、log_* の author_name は nickname 優先で、
# 空とみなす条件（ne '' か 真偽か）まで違う。

# $author_id が偽なら load せずに undef。
# load が die しても undef（MT::Author が読めない環境でツール全体を落とさない）。
# $cache（ハッシュリファレンス）を渡すと author_id ごとに結果を覚える。
# 見つからなかった場合の undef も覚えるので、同じ ID で二度 load しない。
sub load_cached {
    my ($author_id, $cache) = @_;
    return undef unless $author_id;
    return $cache->{$author_id} if $cache && exists $cache->{$author_id};
    my $author = eval {
        require MT::Author;
        MT::Author->load($author_id);
    };
    $cache->{$author_id} = $author if $cache;
    return $author;
}

1;
