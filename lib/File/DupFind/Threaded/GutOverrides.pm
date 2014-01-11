use strict;
use warnings;

# methods and attributes that have to be overridden from File::DupFind::Guts
# due to threading

package File::DupFind::Threaded::GutOverrides;

use 5.010;

use threads;
use threads::shared;

use Moo::Role;

use lib 'lib';

requires 'opts';

{
   my $stats = {}; &share( $stats );

   sub stats
   {
      my ( $self, $key, $val ) = @_;

      return $stats unless $key;

      lock $stats;

      $stats->{ $key } = $val;
   }

   sub add_stats
   {
      my ( $self, $key, $val ) = @_;

      return $stats unless $key;

      lock $stats;

      $stats->{ $key } += $val;
   }
}


sub sort_dups
{
   my ( $self, $dups ) = @_;

   # sort dup groupings
   for my $identifier ( keys %$dups )
   {
      my @group = @{ $dups->{ $identifier } };

      $dups->{ $identifier } = &shared_clone( [ sort { $a cmp $b } @group ] );
   }

   return $dups;
}

1;
