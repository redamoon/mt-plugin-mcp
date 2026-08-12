package MTMCP::Tools::Asset;
use strict;
use warnings;
use MT::Asset;
use MTMCP::Perm;

my %IMAGE_EXT = map { $_ => 1 } qw(jpg jpeg png gif bmp webp);

# アップロードを許可する拡張子（許可リスト方式）。site_path 配下に保存され
# site_url から配信される可能性があるため、サーバー上で実行され得る拡張子
# （.php, .cgi, .pl, .phtml, .htaccess 等）は含めない。SVGはスクリプトを
# 埋め込める（保存型XSSのリスク）ため意図的に除外している。
my %ALLOWED_UPLOAD_EXT = map { $_ => 1 } (
    %IMAGE_EXT,
    qw(ico tif tiff pdf txt csv md
       doc docx xls xlsx ppt pptx
       zip
       mp3 mp4 mov avi wav ogg webm),
);

# キーワード検索時にPerl側でスキャンする最大件数。DB側でのLIKE検索ではなく
# 直近のレコードをこの件数までロードしてから絞り込むため、これを超えて
# 古いレコードにしかマッチしないキーワードは検出できない（既知の制約）。
use constant KEYWORD_SCAN_LIMIT => 2000;

# Base64デコード後のアップロードサイズ上限（20MB）。上限を設けないと
# 大きなペイロードでメモリ・ディスクを消費させられる。
use constant MAX_UPLOAD_BYTES => 20 * 1024 * 1024;

sub list {
    my ($app, $args) = @_;
    my $blog_id = $args->{blog_id} or die "blog_id is required\n";
    MTMCP::Perm::require_blog_access($app, $blog_id);
    my $limit   = $args->{limit}   // 20;
    my $offset  = $args->{offset}  // 0;
    my $keyword = $args->{keyword};
    my %terms = (blog_id => $blog_id);
    $terms{class} = $args->{class} if $args->{class};

    my %load_opts = ( sort => 'created_on', direction => 'descend' );
    if ($keyword) {
        $load_opts{limit} = KEYWORD_SCAN_LIMIT;
    } else {
        $load_opts{limit}  = $limit;
        $load_opts{offset} = $offset;
    }

    my @assets = MT::Asset->load(\%terms, \%load_opts);

    if ($keyword) {
        my $kw = lc $keyword;
        @assets = grep {
            index(lc($_->label // ''), $kw) >= 0
                || index(lc($_->file_name // ''), $kw) >= 0
        } @assets;
        @assets = splice(@assets, $offset, $limit);
    }

    return [ map { _to_hash($_) } @assets ];
}

sub get {
    my ($app, $args) = @_;
    my $asset_id = $args->{asset_id} or die "asset_id is required\n";
    my $asset = MT::Asset->load($asset_id) or die "Asset not found: $asset_id\n";
    MTMCP::Perm::require_blog_access($app, $asset->blog_id);
    return _to_hash($asset, 1);
}

sub remove {
    my ($app, $args) = @_;
    my $asset_id = $args->{asset_id} or die "asset_id is required\n";
    my $asset = MT::Asset->load($asset_id) or die "Asset not found: $asset_id\n";
    MTMCP::Perm::require_blog_access($app, $asset->blog_id);
    my $label = $asset->label // $asset->file_name;
    $asset->remove or die $asset->errstr . "\n";
    return { asset_id => $asset_id, status => 'deleted', label => $label };
}

sub upload {
    my ($app, $args) = @_;
    my $blog_id   = $args->{blog_id}   or die "blog_id is required\n";
    my $file_name = $args->{file_name} or die "file_name is required\n";
    my $data_b64  = $args->{data}      or die "data (base64) is required\n";
    MTMCP::Perm::require_blog_access($app, $blog_id);

    require MT::Blog;
    my $blog = MT::Blog->load($blog_id) or die "Blog not found: $blog_id\n";
    my $site_path = $blog->site_path or die "Blog site_path is not configured\n";
    my $site_url  = $blog->site_url  or die "Blog site_url is not configured\n";
    $site_url =~ s{/+$}{};

    # Base64は元データよりおよそ4/3に膨らむため、デコード前に概算でも上限を
    # 超えていないか確認してから decode_base64 を呼ぶ（メモリ消費対策）。
    if (length($data_b64) > MAX_UPLOAD_BYTES * 4 / 3 + 1024) {
        die "Uploaded file exceeds the maximum allowed size (" . MAX_UPLOAD_BYTES . " bytes)\n";
    }

    require MIME::Base64;
    my $bytes = eval { MIME::Base64::decode_base64($data_b64) };
    die "Invalid base64 data\n" if $@ || !defined $bytes || !length $bytes;
    die "Uploaded file exceeds the maximum allowed size (" . MAX_UPLOAD_BYTES . " bytes)\n"
        if length($bytes) > MAX_UPLOAD_BYTES;

    (my $safe_name = $file_name) =~ s{[/\\]}{_}g;
    $safe_name =~ s{\.\.}{_}g;
    die "file_name must have an extension\n" unless $safe_name =~ /\.(\w+)$/;
    my $ext = lc $1;
    die "File extension not allowed: .$ext\n" unless $ALLOWED_UPLOAD_EXT{$ext};

    my $sub_dir = $args->{directory} // 'mcp-uploads';
    $sub_dir =~ s{^/+|/+$}{}g;
    $sub_dir =~ s{\.\.}{}g;

    require File::Spec;
    my @dir_parts = grep { length } split m{/}, $sub_dir;
    my $dest_dir  = File::Spec->catdir($site_path, @dir_parts);
    my $rel_path  = @dir_parts ? join('/', @dir_parts) . "/$safe_name" : $safe_name;

    require MT::FileMgr;
    my $fmgr = MT::FileMgr->new('Local') or die "Could not initialize file manager\n";
    unless (-d $dest_dir) {
        $fmgr->mkpath($dest_dir) or die "Could not create directory: $dest_dir\n";
    }

    if ($fmgr->exists(File::Spec->catfile($dest_dir, $safe_name)) && !$args->{overwrite}) {
        my ($base) = $safe_name =~ /^(.*)\.\w+$/;
        my $i = 1;
        my $candidate;
        do {
            $candidate = "${base}_${i}.${ext}";
            $i++;
        } while ($fmgr->exists(File::Spec->catfile($dest_dir, $candidate)));
        $safe_name = $candidate;
        $rel_path  = @dir_parts ? join('/', @dir_parts) . "/$safe_name" : $safe_name;
    }

    my $dest_file = File::Spec->catfile($dest_dir, $safe_name);
    $fmgr->put_data($bytes, $dest_file, 'upload')
        or die "Could not write file: " . ($fmgr->errstr // 'unknown error') . "\n";

    my $class = $IMAGE_EXT{$ext} ? 'MT::Asset::Image' : 'MT::Asset';
    eval "require $class; 1" or die "Could not load $class: $@\n";

    my $author_id = $args->{author_id};
    unless ($author_id) {
        my $user = eval { $app->user };
        $author_id = ($user && $user->id && !$user->is_anonymous) ? $user->id : 1;
    }

    my $asset = $class->new;
    $asset->blog_id($blog_id);
    $asset->file_path($dest_dir);
    $asset->file_name($safe_name);
    $asset->file_ext($ext);
    $asset->file_size(length $bytes);
    $asset->url("$site_url/$rel_path");
    $asset->label($args->{label} // $safe_name);
    $asset->created_by($author_id);

    if ($asset->isa('MT::Asset::Image')) {
        my ($w, $h) = eval {
            require MT::Image;
            my $img = MT::Image->new(Filename => $dest_file);
            $img ? $img->get_dimensions : ();
        };
        $asset->image_width($w)  if $w;
        $asset->image_height($h) if $h;
    }

    $asset->save or die $asset->errstr . "\n";

    return { asset_id => $asset->id, status => 'created', url => $asset->url, file_name => $safe_name };
}

sub thumbnail {
    my ($app, $args) = @_;
    my $asset_id = $args->{asset_id} or die "asset_id is required\n";
    my $asset = MT::Asset->load($asset_id) or die "Asset not found: $asset_id\n";
    MTMCP::Perm::require_blog_access($app, $asset->blog_id);
    die "Asset $asset_id does not support thumbnails\n" unless $asset->can('thumbnail_url');

    my %opts;
    $opts{Width}  = $args->{width}  if $args->{width};
    $opts{Height} = $args->{height} if $args->{height};
    $opts{Square} = 1 if $args->{square};

    my ($url, $w, $h) = $asset->thumbnail_url(%opts);
    die "Could not generate thumbnail for asset $asset_id\n" unless $url;

    return { asset_id => $asset->id, thumbnail_url => $url, width => $w, height => $h };
}

sub _to_hash {
    my ($asset, $full) = @_;
    my $hash = {
        id         => $asset->id,
        label      => $asset->label // '',
        file_name  => $asset->file_name,
        class      => $asset->class,
        url        => eval { $asset->url } // '',
        created_on => $asset->created_on,
    };
    if ($full) {
        $hash->{file_path}    = $asset->file_path    // '';
        $hash->{mime_type}    = $asset->mime_type    // '';
        $hash->{file_size}    = $asset->file_size    // 0;
        $hash->{image_width}  = $asset->image_width  // 0 if $asset->class eq 'image';
        $hash->{image_height} = $asset->image_height // 0 if $asset->class eq 'image';
    }
    return $hash;
}

1;
