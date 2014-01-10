use strict;
use warnings;

package File::DupFind::Threaded::MapReduce;

use 5.010;

use threads;
use threads::shared;

use Moose;
use MooseX::XSAccessor;
use Time::HiRes 'usleep';

use lib 'lib';

extends 'File::DupFind::Threaded';

sub map_reduce
{
   my $self = shift;

   $self->reset_all;

   $self->mapper( @_ );

   return $self->reducer;
}

sub mapper
{
   my ( $self, $size_dups, $map ) = @_;
   my $dup_count = 0;
   my $queued    = 0;

   $dup_count += @$_ for map { $size_dups->{ $_ } } keys %$size_dups;

   # creates thread pool, passing in as an argument the number of files
   # that the pool needs to digest.  this is NOT equivalent to the number
   # of threads to be created; that is determined in the options ($opts)

   $self->create_thread_pool( $map => $dup_count );

   for my $size ( keys %$size_dups )
   {
      my $group = $size_dups->{ $size };

      $self->work_queue->enqueue( $group ) if !$self->term_flag;
   }

   # wait for threads to finish; depends on the coderef in $map
   # doing its job of updating the counter for ever item processed!

   while ( $self->counter < $dup_count )
   {
      usleep 1000; # sleep for 1 millisecond
   }

   # ...tell the threads to exit
   $self->end_wait_thread_pool;

   return;
}

sub reducer
{
   my $self = shift @_;

   # get rid of non-dupes
   $self->delete_mapped( $_ )
      for grep { @{ $self->mapped->{ $_ } } == 1 }
      keys %{ $self->mapped };

   return $self->mapped;
}

__PACKAGE__->meta->make_immutable;

1;
