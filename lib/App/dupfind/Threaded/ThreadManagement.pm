# ABSTRACT: Thread management logic, abstracted safely away in its own namespace

use strict;
use warnings;

package App::dupfind::Threaded::ThreadManagement;

use 5.010;

BEGIN
{
   $SIG{TERM} = $SIG{INT} = sub { $_->kill( 'KILL' ) for threads->list };
}

use threads;
use threads::shared;

our $counter   :shared = 0;
our $term_flag :shared = 0;
our $init_flag :shared = 0;
our $mapped    = &share( {} );

use Moo;

use Thread::Queue;
use Time::HiRes 'usleep';

use lib 'lib';

extends 'App::dupfind';

with 'App::dupfind::Threaded::Overrides';

has work_queue => ( is => 'rw', default => sub { Thread::Queue->new } );

before threads_progress => sub { require Term::ProgressBar };


sub mapped { $mapped }

sub counter { $counter }

sub reset_all
{
   my $self = shift;

   $self->reset_queue;

   $self->clear_counter;

   $self->reset_mapped;

   $self->init_flag( 0 );

   $self->term_flag( 0 );
}

sub reset_queue { shift->work_queue( Thread::Queue->new ) };

sub clear_counter { lock $counter; $counter = 0; return $counter; }

sub reset_mapped { $mapped = &share( {} ); $mapped; }

sub increment_counter { lock $counter; return ++$counter; }

sub term_flag
{
   shift;

   if ( @_ ) { lock $term_flag; $term_flag = shift; }

   return $term_flag
}

sub init_flag
{
   shift;

   if ( @_ ) { lock $init_flag; $init_flag = shift; }

   return $init_flag
}

sub push_mapped
{
   my ( $self, $key, @vals ) = @_;

   lock $mapped;

   $mapped->{ $key } ||= &share( [] );

   push @{ $mapped->{ $key } }, @vals;

   return $mapped;
}

sub delete_mapped
{
   my ( $self, @keys ) = @_;

   lock $mapped;

   delete $mapped->{ $_ } for @keys;

   return $mapped;
}

sub create_thread_pool
{
   my ( $self, $map_code, $dup_count ) = @_;

   $self->init_flag( 1 );

   threads->create( threads_progress => $self => $dup_count )
      if $self->opts->{progress};

   for ( 1 .. $self->opts->{threads} )
   {
      # $map coderef is responsible for calling $self->increment_counter!

      threads->create( $map_code );
   }
}

sub end_wait_thread_pool
{
   my $self = shift;

   $self->term_flag( 1 );

   $self->work_queue->end;

   $_->join for threads->list;
}

sub threads_progress
{
   my ( $self, $task_item_count ) = @_;

   my $last_update = 0;

   my $threads_progress = Term::ProgressBar->new
      (
         {
            name   => '   ...PROGRESS',
            count  => $task_item_count,
            remove => 1,
         }
      );

   while ( !$self->term_flag )
   {
      usleep 1000; # sleep for 1 millisecond

      $threads_progress->update( $self->counter )
         if $self->counter > $last_update;

      last if $self->counter == $task_item_count;

      $last_update = $self->counter;
   }

   $threads_progress->update( $task_item_count );
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 NAME

App::dupfind::Threaded::ThreadManagement - Thread management logic, abstracted safely away in its own namespace

=head1 DESCRIPTION

Safely tucks away the management of threads and all the threading logic
that makes the Map-Reduce feature of App::dupfind possible.  Thanks goes
out to BrowserUk at perlmonks.org who helped me get this code on the right
track.

Please don't use this module by itself.  It is for internal use only.

=head1 METHODS

=over

=item clear_counter

The "counter" in App::dupfind::Threaded::ThreadManagment is used to keep
track of how many items have been processed by the thread pool.  This
clear_counter method resets the counter.

=item counter

The counter itself is a read-only accessor around a thread-shared scalar int

=item create_thread_pool

Method that spawns N threads to do work for the map-reducer, where N is the
number of threads that the user has specified with the "--threads N" flag.

If the user has requested a progress bar, one more thread is spawned which
does nothing but monitor overall progress of the thread pool and update
the progress bar.

=item delete_mapped

Deletes a same-size file grouping from the global hashref of same-size file
groupings, by key.  Thread-safe management of the datastructure is insured.

=item end_wait_thread_pool

Ends the global work queue, sets the thread terminate flag to 1, and joins
the threads in the pool.

=item increment_counter

Thread-safe way to increment the global shared counter (scalar int value).
The counter is key to the successful execution of all threads, and it is
imperative that any code executed by the map-reduce engine properly calls
increment_counter for work every item it processes.

=item init_flag

R/W accessor whose read value indicates that the thread pool has been initiated
when the return value is true.

=item mapped

Read-only accessor to the global shared hashref of "work items", i.e.- the
groupings of same-size files which are potential duplicates

=item push_mapped

The thread-safe way to push a new item or items onto a grouping in the global
mapped work-item registry.  $obj->push_mapped( key => @items );

=item reset_all

Resets all flags, queues, work mappings, and counters.

In turn, it calls:

=over

=item *

$self->reset_queue

=item *

$self->clear_counter

=item *

$self->reset_mapped

=item *

$self->init_flag( 0 )

=item *

$self->term_flag( 0 )

=back

=item reset_mapped

Destroys the globally-shared mapping of work items.  Takes no arguments.

=item reset_queue

Creates a new Thread::Queue object, which is then accessible via a call to
$self->work_queue.  This does not end the previous Thread::Queue object.
That is the responsibility of $self->end_wait_thread_pool

=item term_flag

R/W accessor method that indicates to threads that they should exit when
a true value is returned.

=item threads_progress

This method is executed by the single helper thread whose sole responsibility
is to update the progress bar for the thread pool, if the user has requested
a progress bar

=item work_queue

Thread-safe shared Thread::Queue object for the current $self object.  It can
be ended via $self->end_wait_thread_pool and it can thereafter be recreated
via $self->reset_queue

The map part of the map-reduce engine pushes work items into this queue.

=back

=cut

