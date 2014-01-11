use strict;
use warnings;

package File::DupFind::Threaded::MapReduce::Digest;

use 5.010;

use threads;
use threads::shared;

use Moo::Role;

use Time::HiRes 'usleep';
use Digest::xxHash 'xxhash_hex';

requires 'opts';

my $read_semaphore :shared;

sub digest_dups
{
   my ( $self, $size_dups ) = @_;

   # you have to do this for this threaded version of dupfind, and it has
   # to happen after you've already pruned out the hardlinks

   # don't bother to hash zero-size files

   my $zero_digest = xxhash_hex '', 0;

   my $zero_files  = delete $size_dups->{0};

   my $map_code    = sub { $self->_digest_worker( @_ ) };

   my $reduced     = $self->map_reduce( $size_dups => $map_code );

   $reduced->{ $zero_digest } = $zero_files if ref $zero_files;

   return $reduced;
}

# !! The code to be mapped MUST increment $self->counter for each item it sees
sub _digest_worker
{
   my $self = shift;

   my $digest_cache  = {};
   my $cache_stop    = $self->opts->{cachestop};
   my $max_cache     = $self->opts->{cachesize};
   my $ram_caching   = !! $self->opts->{ramcache};
   my $cache_size    = 0;
   my $cache_hits    = 0;
   my $cache_misses  = 0;

   local $/;

   WORKER: while
   (
       ! $self->term_flag
      && defined ( my $grouping = $self->work_queue->dequeue )
   )
   {
      my $data;

      GROUPING: for my $file ( @$grouping )
      {
         my $size = -s $grouping->[0];
         my $digest;

         open my $fh, '<', $file or do
            {
               $self->increment_counter;

               next GROUPING;
            };

         READ_LOCK:
         {
            lock $read_semaphore;

            $data = <$fh>;
         }

         close $fh;

         if ( $ram_caching )
         {
            if ( $digest = $digest_cache->{ $data } )
            {
               $cache_hits++;
            }
            else
            {
               if ( $cache_size < $max_cache && $size <= $cache_stop )
               {
                  $digest_cache->{ $data } = $digest = xxhash_hex $data, 0;

                  $cache_size++;

                  $cache_misses++;
               }
               else
               {
                  $digest = xxhash_hex $data, 0;
               }
            }
         }
         else
         {
            $digest = xxhash_hex $data, 0;
         }

         $self->push_mapped( $digest => $file );

         $self->increment_counter;
      }

      $digest_cache = {}; # it's only worthwhile per-size-grouping
      $cache_size   = 0;

      $self->add_stats( cache_hits   => $cache_hits );
      $self->add_stats( cache_misses => $cache_misses );
   }
}

1;
