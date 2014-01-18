# ABSTRACT: Basic, abstracted implementation of map-reduce for threaded tasks

use strict;
use warnings;

package App::dupfind::Threaded::MapReduce;

use 5.010;

use threads;
use threads::shared;

use Moo;
use Time::HiRes 'usleep';

use lib 'lib';

extends 'App::dupfind::Threaded::ThreadManagement';

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

__END__

=pod

=head1 NAME

App::dupfind::Threaded::MapReduce - Basic, abstracted implementation of map-reduce for threaded tasks

=head1 DESCRIPTION

App::dupfind implements a simple map-reduce feature when threading is used
and takes same-size file groups and processes them in parallel, each grouping
forming a task mapping that is then reduced upon completion to only the files
that are truly duplicates.

Please don't use this module by itself.  It is for internal use only.

=head1 METHODS

=over

=item map_reduce

yada yada

=item mapper

yada yada

=item reducer

yada yada

=back

=cut

