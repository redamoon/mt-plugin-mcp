use strict;
use warnings;
use utf8;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../plugins/MTMCP/lib";

use MT::Author;
use MTMCP::Author;

sub _seed_author {
    my (%args) = @_;
    my $u = MT::Author->new;
    $u->id($args{id});
    $u->name($args{name})         if exists $args{name};
    $u->nickname($args{nickname}) if exists $args{nickname};
    $u->save;
    return $u;
}

# --- author_id が偽なら load しない ---
{
    MT::Author::reset();
    is(MTMCP::Author::load_cached(0),     undef, 'author_id=0 は undef');
    is(MTMCP::Author::load_cached(undef), undef, 'author_id=undef は undef');
    is(MTMCP::Author::load_cached(''),    undef, 'author_id=空文字は undef');
    is($MT::Author::LOAD_COUNT, 0, '偽の author_id では load を呼ばない');
}

# --- 見つかれば著者オブジェクトを返す ---
{
    MT::Author::reset();
    _seed_author(id => 3, name => 'taro', nickname => 'タロー');
    my $author = MTMCP::Author::load_cached(3);
    ok($author, '存在する author_id で著者が返る');
    is($author->id,       3,        'id が一致する');
    is($author->name,     'taro',   'name が読める');
    is($author->nickname, 'タロー', 'nickname が読める');
    is($MT::Author::LOAD_COUNT, 1, 'load は1回');
}

# --- 見つからない ID ---
{
    MT::Author::reset();
    _seed_author(id => 3, name => 'taro');
    is(MTMCP::Author::load_cached(999), undef, '存在しない author_id は undef');
    is($MT::Author::LOAD_COUNT, 1, '存在しなくても load 自体は1回走る');
}

# --- load が die しても握りつぶして undef ---
{
    MT::Author::reset();
    _seed_author(id => 3, name => 'taro');
    my $author = do {
        no warnings 'redefine';
        local *MT::Author::load = sub { die "boom\n" };
        MTMCP::Author::load_cached(3);
    };
    is($author, undef, 'load が die したら undef を返す');
    ok(MTMCP::Author::load_cached(3), 'die を握りつぶすだけで以降の load は通常どおり');
}

# --- cache: 2回目は load しない ---
{
    MT::Author::reset();
    _seed_author(id => 3, name => 'taro');
    my %cache;
    my $first  = MTMCP::Author::load_cached(3, \%cache);
    my $second = MTMCP::Author::load_cached(3, \%cache);
    is($MT::Author::LOAD_COUNT, 1, '同じ author_id ではキャッシュが効いて load は1回');
    is($second, $first, 'キャッシュから同じオブジェクトが返る');
    ok(exists $cache{3}, 'キャッシュに author_id のキーが入る');
}

# --- cache: 著者ごとに1回ずつ ---
{
    MT::Author::reset();
    _seed_author(id => 3, name => 'taro');
    _seed_author(id => 4, name => 'hanako');
    my %cache;
    MTMCP::Author::load_cached($_, \%cache) for (3, 4, 3, 4, 3);
    is($MT::Author::LOAD_COUNT, 2, '著者2人なら load は2回だけ');
    is($cache{4}->name, 'hanako', 'キャッシュは author_id ごとに分かれている');
}

# --- cache: 見つからなかった undef も覚える ---
{
    MT::Author::reset();
    is(MTMCP::Author::load_cached(999, \my %cache), undef, '不在の著者は undef');
    is(MTMCP::Author::load_cached(999, \%cache),    undef, '2回目も undef');
    is($MT::Author::LOAD_COUNT, 1, '不在の著者でも load を繰り返さない');
    ok(exists $cache{999}, 'undef もキャッシュに記録される');
}

# --- cache を渡さなければ毎回 load する（entry_export の呼び方） ---
{
    MT::Author::reset();
    _seed_author(id => 3, name => 'taro');
    MTMCP::Author::load_cached(3);
    MTMCP::Author::load_cached(3);
    is($MT::Author::LOAD_COUNT, 2, 'cache 無しなら毎回 load する');
}

# --- 呼び出し側のフィールド選択（現行の挙動を固定する） ---
# entry_export は name のみ・既定値 'author'、log_* は nickname 優先・既定値 ''。
{
    MT::Author::reset();
    _seed_author(id => 3, name => 'taro', nickname => 'タロー');
    my $author = MTMCP::Author::load_cached(3);
    my $entry_name = 'author';
    $entry_name = $author->name if $author && defined $author->name && $author->name ne '';
    is($entry_name, 'taro', 'entry_export 側は nickname ではなく name を使う');

    my $log_name = $author ? ($author->nickname || $author->name || '') : '';
    is($log_name, 'タロー', 'log_* 側は nickname を優先する');
}

done_testing();
