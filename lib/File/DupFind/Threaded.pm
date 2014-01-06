use strict;
use warnings;

package File::DupFind::Threaded;

use 5.010;

BEGIN { $|++; $SIG{TERM} = $SIG{INT} = \&end_wait_thread_pool; }

use threads;
use threads::shared;

use Moose; extends 'File::DupFind';

use Thread::Queue;
use Time::HiRes 'usleep';
use Digest::xxHash 'xxhash_hex';

my $work_queue    = Thread::Queue->new;
my $digests       = &share( {} );
my $d_counter     :shared = 0;
my $thread_term   :shared = 0;
my $threads_init  :shared = 0;

sub get_dup_digests
{
   my ( $self, $size_dups ) = @_;
   my $dup_count = 0;
   my $queued    = 0;

   # you have to do this for this threaded version of dupfind, and it has
   # to happen after you've already pruned out the hardlinks
   {
      # don't bother to hash zero-size files
      $digests->{ xxhash_hex '', 0 } = &shared_clone( $size_dups->{0} )
         if exists $size_dups->{0};

      delete $size_dups->{0};
   }

   $dup_count += @$_ for map { $size_dups->{ $_ } } keys %$size_dups;

   # creates thread pool, passing in as an argument the number of files
   # that the pool needs to digest.  this is NOT equivalent to the number
   # of threads to be created; that is determined in the options ($opts)

   $self->create_thread_pool( $dup_count );

   for my $size ( keys %$size_dups )
   {
      my $group = $size_dups->{ $size };

      for my $file ( @$group )
      {
         $work_queue->enqueue( $file ) if !$thread_term;
      }
   }

   # wait for threads to finish
   while ( $d_counter < $dup_count )
   {
      usleep 1000; # sleep for 1 millisecond
   }

   # ...tell the threads to exit
   end_wait_thread_pool();

   # get rid of non-dupes
   delete $digests->{ $_ }
      for grep { @{ $digests->{ $_ } } == 1 }
      keys %$digests;

   my $priv_digests = {};

   # sort dup groupings
   for my $digest ( keys %$digests )
   {
      my @group = @{ $digests->{ $digest } };

      $priv_digests->{ $digest } = [ sort { $a cmp $b } @group ];
   }

   undef $digests;

   return $priv_digests;
}

sub create_thread_pool
{
   my ( $self, $files_to_digest ) = @_;

   threads->create( threads_progress => $files_to_digest );

   for ( 1 .. $self->opts->{threads} )
   {
      threads->create( 'worker' );
   }

   lock $threads_init; $threads_init++;
}

sub end_wait_thread_pool
{
   # this is not an object method like its create_thread_pool counterpart;
   # it has to be callable from the SIG handlers (at top of this file)

   exit unless $threads_init;

   $thread_term++;

   $work_queue->end;

   $_->join for threads->list;
}

sub threads_progress
{
   my $files_to_digest  = shift;
   my $last_update      = 0;
   my $threads_progress = Term::ProgressBar->new
      (
         {
            name   => '   ...PROGRESS',
            count  => $files_to_digest,
            remove => 1,
         }
      );

   while ( !$thread_term )
   {
      usleep 1000; # sleep for 1 millisecond

      $threads_progress->update( $d_counter )
         if $d_counter > $last_update;

      $last_update = $d_counter;
   }

   $threads_progress->update( $files_to_digest );
}

sub worker
{
   my $tid = threads->tid;

   local $/;

   WORKER: while ( !$thread_term && defined ( my $file = $work_queue->dequeue ) )
   {
      open my $fh, '<', $file or do { lock $d_counter; $d_counter++; next WORKER };

      my $data = <$fh>;

      close $fh;

      my $digest = xxhash_hex $data, 0;

      lock $digests;

      $digests->{ $digest } ||= &share( [] );

      push @{ $digests->{ $digest } }, $file;

      lock $d_counter; $d_counter++;
   }
}

__PACKAGE__->meta->make_immutable;

1;
