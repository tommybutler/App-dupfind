
use strict;
use warnings;

use Test::More tests => 2;
use Test::NoWarnings;

use File::Util;

use lib 'lib';

my $solution = eval File::Util->new->load_file( 't/solutions/006_weed.pl' );

BEGIN { @ARGV = qw( --quiet --dir t/data ) }

use App::dupfind::App;

my $app = App::dupfind::App->new;

my $size_dups  = $app->scanfs;
my $prune_dups = $app->prune( $size_dups );
my $weed_dups  = $app->weed( $prune_dups );

$size_dups = $app->deduper->sort_dups( $weed_dups );

is_deeply $size_dups, $solution, 'weed returns correct datastructure';

exit;
