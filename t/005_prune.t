
use strict;
use warnings;

use Test::More tests => 2;
use Test::NoWarnings;

use File::Util;
use Try::Tiny;

use lib 'lib';

my $solution = eval File::Util->new->load_file( 't/solutions/005_prune.pl' );
my $hardlink = 't/data/ZZ_hardlink';

BEGIN { @ARGV = qw( --quiet --dir t/data ) }

use App::dupfind::App;

my $app = App::dupfind::App->new;

my $size_dups = $app->scanfs;

try { link $size_dups->{0}->[0], $hardlink };

SKIP:
{
   if ( ! -e $hardlink )
   {
      skip "Can't make or test hardlinks on your system" => 1;
   }

   my $pruned_dups = $app->prune( $size_dups );

   $pruned_dups = $app->deduper->sort_dups( $pruned_dups );

   is_deeply $pruned_dups, $size_dups, 'prune returns correct datastructure';
}

try { unlink $hardlink };

exit;
