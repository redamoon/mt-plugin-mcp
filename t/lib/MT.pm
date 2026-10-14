package MT;
use strict;
use warnings;
use File::Basename qw(dirname);
use File::Spec;

sub registry {
    my ($class, $key) = @_;
    return {};
}

# MT->component('MTMCP')->version のスタブ。バージョンは実物の
# plugins/MTMCP/config.yaml から読む。直書きすると config.yaml と
# 食い違ったときにテストが気づけないため。
# $VERSION_OVERRIDE を設定すると、そちらを返す。
our $VERSION_OVERRIDE;

sub component {
    my ($class, $id) = @_;
    return undef unless defined $id && $id eq 'MTMCP';
    return bless {}, 'MT::Component';
}

sub _config_yaml_version {
    my $path = File::Spec->catfile(
        dirname(dirname(dirname(__FILE__))), 'plugins', 'MTMCP', 'config.yaml');
    open my $fh, '<', $path or return undef;
    while (my $line = <$fh>) {
        next unless $line =~ /^version:\s*(\S+)/;
        close $fh;
        return $1;
    }
    close $fh;
    return undef;
}

package MT::Component;

sub version {
    return $MT::VERSION_OVERRIDE if defined $MT::VERSION_OVERRIDE;
    return MT::_config_yaml_version();
}

1;
