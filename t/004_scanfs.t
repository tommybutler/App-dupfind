
use strict;
use warnings;

use Test::More tests => 2;
use Test::NoWarnings;

use File::Util;

use lib 'lib';

my $solution = eval File::Util->new->load_file( 't/solutions/004_scanfs.pl' );

BEGIN { @ARGV = qw( --quiet --dir t/data ) }

use App::dupfind::App;

my $app = App::dupfind::App->new;

my $size_dups = $app->scanfs;

$size_dups = $app->deduper->sort_dups( $size_dups );

is_deeply $size_dups, $solution, 'scanfs returns correct datastructure';

exit;
