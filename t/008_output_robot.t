
use strict;
use warnings;

use Test::More tests => 2;
use Test::NoWarnings;

use File::Temp qw( tmpnam );
use File::Util;

use lib 'lib';

my $f  = File::Util->new();
my $fn = tmpnam(); # get absolute filename

my $solution = 't/solutions/008_output_robot.txt';
   $solution = $f->load_file( $solution );

BEGIN { @ARGV = qw( --quiet --format robot --dir t/data ) }

use App::dupfind::App;

my $app = App::dupfind::App->new;

my $size_dups   = $app->scanfs;
my $prune_dups  = $app->prune( $size_dups );
my $weed_dups   = $app->weed( $prune_dups );
my $digest_dups = $app->digest( $weed_dups );

my $fh = $f->open_handle( $fn => 'write' );

my $stdout = \*STDOUT;

select $fh;

$app->deduper->show_dups( $digest_dups );

close $fh;

select $stdout;

my $output = $f->load_file( $fn );

unlink $fn;

is $output, $solution, 'robot format output gives correct solution';

exit;
