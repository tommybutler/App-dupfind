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

   $dup_count = $self->count_dups( $size_dups );

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

Wrapper/Conveniece method.

Resets all flags, queues, work mappings, and counters.  Then it calls
$self->mapper on its own @_.  Then it returns the result of $self->reducer;

=item mapper

Takes two arguments:

1) a datastructure which it expects to be a hashref whose keys are file sizes
and whose values are listrefs forming groupings of files that correspond to the
indicated file size.

2) a coderef to execute, which actually is spawned as N threads of the coderef
where N is the number of threads that the user has requested.

After spawning the thread pool, mapper() then iterates through the datastructure
and places each grouping as a work item into the work queue for all threads.

This is a possibly-too-fine-grained mapping of work to the threads, and so it
may change in the future so that work is divided up in a different way, but for
now, this is what we've got and it runs pretty darn fast.

After spawning the threads and stuffing their work queue full of things to do,
mapper waits until the threads report back that they are done working.  The
counter mechanism from App::dupfind::Threaded::ThreadManagement is used to
accomplish this.  When the counter of items processed is equal to the number
of items that mapper put into the queue, mapper calls end_wait_thread_pool()
which is inherited from the same class as the counter mechanism.

That action cleans up the thread pool and the the application then becomes
single-threaded again and is ready for $self->reducer to be called.

This constitutes the "map" part of the map-reduce engine.

=item reducer

Scans through the result of an execution of $self->mapper, and "reduces" it
to only the members of the result set that are duplicates (the entire point
of this framework).

This constitutes the "reduce" part of the map-reduce engine.

=back

=cut

