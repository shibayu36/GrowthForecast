#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/extlib/lib/perl5";
use lib "$FindBin::Bin/lib";
use File::Basename;
use Getopt::Long;
use File::Temp qw/tempdir/;
use Parallel::Prefork;
use Parallel::Scoreboard;
use Plack::Loader;
use Plack::Builder;
use Plack::Builder::Conditionals;
use Log::Minimal;
use GrowthForecast::Web;
use GrowthForecast::Worker;

my $port = 5125;
my $host = 0;
my @front_proxy;
my @allow_from;
Getopt::Long::Configure ("no_ignore_case");
GetOptions(
    'port=s' => \$port,
    'host=s' => \$host,
    'front-proxy=s' => \@front_proxy,
    'allow-from=s' => \@allow_from,
    'disable-1min-metrics' => \my $disable_short,
    "h|help" => \my $help,
    "c|config=s" => \my $config_file,
);

if ( $help || !$config_file) {
    print "usage: $0 --port 5005 --host 127.0.0.1 --front-proxy 127.0.0.1 --allow-from 127.0.0.1 --config config.pl --disable-1min-metrics\n";
    exit(1);
}

my $config;
{
    $config = do $config_file;
    croakf "%s: %s", $config_file, $@ if $@;
    croakf "%s: %s", $config_file, $! if $!;
    croakf "%s does not return hashref", $config_file if ref($config) ne 'HASH';
}

local $GrowthForecast::CONFIG = $config;
debugf('dump config:%s',$config);

my $enable_short = $disable_short ? 0 : 1;
my $root_dir = File::Basename::dirname(__FILE__);
my $sc_board_dir = tempdir( CLEANUP => 1 );
my $scoreboard = Parallel::Scoreboard->new( base_dir => $sc_board_dir );

my $pm = Parallel::Prefork->new({
    max_workers => $enable_short ? 3 : 2,
    spawn_interval  => 1,
    trap_signals    => {
        map { ($_ => 'TERM') } qw(TERM HUP)
    }
});

while ($pm->signal_received ne 'TERM' ) {
    $pm->start(sub{
        my $stats = $scoreboard->read_all;
        my %running;
        for my $pid ( keys %{$stats} ) {
            my $val = $stats->{$pid};
            $running{$val}++;
        }
        if ( $running{worker} && ($enable_short ? $running{short_worker} : 1)) {
            local $0 = "$0 (GrowthForecast::Web)";
            $scoreboard->update('web');
            my $web = GrowthForecast::Web->new($root_dir);
            $web->short($enable_short);
            my $app = builder {
                enable 'Lint';
                enable 'StackTrace';
                if ( @front_proxy ) {
                    enable match_if addr(\@front_proxy), 'ReverseProxy';
                }
                if ( @allow_from ) {
                    enable match_if addr('!',\@allow_from), sub {
                        sub { [403,['Content-Type','text/plain'], ['Forbidden']] }
                    };
                }
                enable 'Static',
                    path => qr!^/(?:(?:css|js|images)/|favicon\.ico$)!,
                    root => $root_dir . '/public';
                $web->psgi;
            };
             my $loader = Plack::Loader->load(
                 'Starlet',
                 port => $port,
                 host => $host || 0,
                 max_workers => 4,
             );
             $loader->run($app);
        }
        elsif ( $enable_short && !$running{short_worker} ) {
            local $0 = "$0 (GrowthForecast::Worker 1min)";
            $scoreboard->update('short_worker');
            my $worker = GrowthForecast::Worker->new($root_dir);
            $worker->run('short');
        }
        else {
            local $0 = "$0 (GrowthForecast::Worker)";
            $scoreboard->update('worker');
            my $worker = GrowthForecast::Worker->new($root_dir);
            $worker->run;
        }
    });
}


