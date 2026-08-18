package MTMCP::Args;
use strict;
use warnings;
use utf8;

# ツール引数の共通判定。
# MCP クライアントは同じ真偽値を JSON boolean・数値・文字列のいずれでも送ってくるため、
# ツールごとに判定を書かず、ここに1本化する。

# 真: 1 / "1" / "yes" / JSON::true など真値のスカラーとリファレンス
# 偽: undef / 0 / "0" / "" / "false"（大文字小文字は問わない）
sub is_true {
    my ($v) = @_;
    return 0 unless defined $v;
    return 0 if !$v;
    return 0 if !ref($v) && lc($v) eq 'false';
    return 1;
}

# 破壊的操作の confirm 必須チェック。
# 真なら無言で通し、偽なら $label を差し込んだメッセージで die する。
sub require_confirm {
    my ($args, $label) = @_;
    $args ||= {};
    return 1 if is_true($args->{confirm});
    die "confirm: true が必要です（$label）\n";
}

1;
