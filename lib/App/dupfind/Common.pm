# ABSTRACT: Public methods for the App::dupfind deduplication engine

use strict;
use warnings;

package App::dupfind::Common;

use 5.010;

use Moo;
use Digest::xxHash 'xxhash_hex';

use lib 'lib';

has opts  => ( is => 'ro', required => 1 );

with 'App::dupfind::Guts';

before [ qw/ weed_dups digest_dups / ] => sub
{
   eval 'use Term::ProgressBar' if shift->opts->{progress}
};

before delete_dups => sub { eval 'use Term::Prompt' };


sub count_dups
{
   my ( $self, $dups ) = @_;

   my $count = 0;

   $count += @$_ for map { $dups->{ $_ } } keys %$dups;

   return $count;
}

sub get_size_dups
{
   my $self = shift;

   my ( $size_dups, $scan_count ) = ( {}, 0 );

   $self->ftl->list_dir
   (
      $self->opts->{dir} =>
      {
         recurse => 1,
         callback => sub
            {
               my ( $selfdir, $subdirs, $files ) = @_;

               $scan_count += @$files;

               push @{ $size_dups->{ -s $_ } }, $_
                  for grep { !-l $_ && defined -s $_ } @$files;
            }
      }
   );

   delete $size_dups->{ $_ }
      for grep { @{ $size_dups->{ $_ } } == 1 }
      keys %$size_dups;

   return $size_dups, $scan_count, $self->count_dups( $size_dups );
}

sub toss_out_hardlinks
{
   my ( $self, $size_dups ) = @_;

   for my $size ( keys %$size_dups )
   {
      my $group = $size_dups->{ $size };
      my %dev_inodes;

      # this will automatically throw out hardlinks, with the only surviving
      # file being the first asciibetically-sorted entry
      $dev_inodes{ join '', ( stat $_ )[0,1] } = $_ for reverse sort @$group;

      if ( scalar keys %dev_inodes == 1 )
      {
         delete $size_dups->{ $size };
      }
      else
      {
         $size_dups->{ $size } = [ values %dev_inodes ];
      }
   }

   return $size_dups;
}

sub weed_dups
{
   my ( $self, $size_dups ) = @_;

   my $zero_sized = delete $size_dups->{0};

   my $pass_count = 0;

   $self->_do_weed_pass( $size_dups => $_ => ++$pass_count )
      for $self->_plan_weed_passes;

   $size_dups->{0} = $zero_sized if ref $zero_sized;

   return $size_dups;
}

sub digest_dups
{
   my ( $self, $size_dups ) = @_;

   my ( $digests, $progress, $i ) = ( {}, undef, 0 );

   my $digest_cache  = {};
   my $cache_stop    = $self->opts->{cachestop};
   my $max_cache     = $self->opts->{cachesize};
   my $ram_caching   = !! $self->opts->{ramcache};
   my $cache_size    = 0;
   my $cache_hits    = 0;
   my $cache_misses  = 0;

   # don't bother to hash zero-size files
   $digests->{ xxhash_hex '', 0 } = delete $size_dups->{0}
      if exists $size_dups->{0};

   if ( $self->opts->{progress} )
   {
      my $dup_count = $self->count_dups( $size_dups );

      $progress = Term::ProgressBar->new
      (
         {
            name   => '   ...PROGRESS',
            count  => $dup_count,
            remove => 1,
         }
      );
   }

   local $/;

   SIZES: for my $size ( keys %$size_dups )
   {
      my $group = $size_dups->{ $size };

      GROUPING: for my $file ( @$group )
      {
         my $digest;

         open my $fh, '<', $file or next;

         my $data = <$fh>;

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

         push @{ $digests->{ $digest } }, $file;

         $progress->update( ++$i ) if $progress;
      }

      $digest_cache = {}; # it's only worthwhile per-size-grouping
      $cache_size   = 0;
   }

   delete $digests->{ $_ }
      for grep { @{ $digests->{ $_ } } == 1 }
      keys %$digests;

   $self->stats->{cache_hits}   = $cache_hits;
   $self->stats->{cache_misses} = $cache_misses;

   return $digests;
}

sub sort_dups
{
   my ( $self, $dups ) = @_;

   # sort dup groupings
   for my $identifier ( keys %$dups )
   {
      my @group = @{ $dups->{ $identifier } };

      $dups->{ $identifier } = [ sort { $a cmp $b } @group ];
   }

   return $dups;
}

sub show_dups # also calls $self->sort_dups before displaying output
{
   my ( $self, $digests ) = @_;
   my $dupes = 0;

   $digests = $self->sort_dups( $digests );

   my $for_humans = sub # human-readable output
   {
      my ( $digest, $files ) = @_;

      say sprintf 'DUPLICATES (digest: %s | size: %db)', $digest, -s $$files[0];

      say "   $_" for @$files;

      say '';
   };

   my $for_robots = sub # machine parseable output
   {
      my ( $digest, $files ) = @_;

      say join "\t", @$files
   };

   my $formatter = $self->opts->{format} eq 'human' ? $for_humans : $for_robots;

   for my $digest
   (
      sort { $digests->{ $a }->[0] cmp $digests->{ $b }->[0] } keys %$digests
   )
   {
      my $files = $digests->{ $digest };

      $formatter->( $digest => $files );

      $dupes += @$files - 1;
   }

   return $dupes
}

sub delete_dups
{
   my ( $self, $digests ) = @_;

   my $removed = 0;

   for my $digest ( keys %$digests )
   {
      my $group = $digests->{ $digest };

      say sprintf 'KEPT    (%s) %s', $digest, $group->[0];

      shift @$group;

      for my $dup ( @$group )
      {
         if ( $self->opts->{prompt} )
         {
            unless ( Term::Prompt->prompt( 'y', "REMOVE DUPE? $dup", '', 'n' ) )
            {
               say sprintf 'KEPT    (%s) %s', $digest, $dup;

               next;
            }
         }

         unlink $dup or warn "COULD NOT REMOVE $dup!  $!" and next;

         $removed++;

         say sprintf 'REMOVED (%s) %s', $digest, $dup;
      }

      say '--';
   }

   say "** TOTAL DUPLICATE FILES REMOVED: $removed";
}

sub cache_stats
{
   my $self = shift;

   return $self->stats->{cache_hits},
          $self->stats->{cache_misses}
}

sub say_stderr { shift; chomp for @_; warn "$_\n" for @_ };

__PACKAGE__->meta->make_immutable;

1;
