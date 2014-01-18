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

yada yada

=item counter

yada yada

=item create_thread_pool

yada yada

=item delete_mapped

yada yada

=item end_wait_thread_pool

yada yada

=item increment_counter

yada yada

=item init_flag

yada yada

=item mapped

yada yada

=item push_mapped

yada yada

=item reset_all

yada yada

=item reset_mapped

yada yada

=item reset_queue

yada yada

=item term_flag

yada yada

=item threads_progress

yada yada

=item work_queue

yada yada

=back

=cut

