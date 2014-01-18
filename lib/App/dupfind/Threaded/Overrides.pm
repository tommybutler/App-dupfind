# ABSTRACT: Methods and attributes that have to be overridden when threading

# Overriding from:
#  - App::dupfind::Common
#  - App::dupfind::Guts

use strict;
use warnings;

package App::dupfind::Threaded::Overrides;

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

__END__

=pod

=head1 NAME

App::dupfind::Threaded::Overrides - Methods and attributes that have to be overridden when threading

=head1 DESCRIPTION

Some of the methods in App::dupfind::Common and App::dupfind::Guts need to
be overridden here in order to make thread-safe versions of them, and/or
versions of the methods that implement support for shared variables that
will be passed around between threads during the map-reduce operations
implemented by App::dupfind::Threaded::MapReduce

Please don't use this module by itself.  It is for internal use only.

=cut

