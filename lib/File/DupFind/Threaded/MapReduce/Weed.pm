use strict;
use warnings;

package File::DupFind::Threaded::MapReduce::Weed;

use 5.010;

use threads;
use threads::shared;

use Moose::Role;

use Time::HiRes 'usleep';

requires 'opts';

sub weed_dups
{
   my ( $self, $size_dups ) = @_;

   # you have to do this for this threaded version of dupfind, and it has
   # to happen after you've already pruned out the hardlinks

   my $zero_files  = delete $size_dups->{0};

   my $map_code    = sub { $self->_weed_worker( '_get_file_first_bytes' ) };

   my $reduced     = $self->map_reduce( $size_dups => $map_code );

      $map_code    = sub { $self->_weed_worker( '_get_file_last_bytes' ) };

      $reduced     = $self->map_reduce( $reduced => $map_code );

   $size_dups->{0} = $zero_files if ref $zero_files;

   return $reduced;
}

sub _weed_worker
{
   my ( $self, $weeder ) = @_;

   local $/;

   WORKER: while
   (
       ! $self->term_flag
      && defined ( my $grouping = $self->work_queue->dequeue )
   )
   {
      my $same_bytes = {};

      next unless !! @$grouping; # why?

      GROUPING: for my $file ( @$grouping )
      {
         my $bytes_read = $self->$weeder( $file );

         $self->increment_counter;

         push @{ $same_bytes->{ $bytes_read } }, $file
            if defined $bytes_read;
      }

      my $file_size = -s $grouping->[0];

      # delete obvious non-dupe files from the group of same-size files
      # by virtue of the fact that they will be a single length arrayref

      delete $same_bytes->{ $_ }
         for grep { @{ $same_bytes->{ $_ } } == 1 }
         keys %$same_bytes;

      # recompose the arrayref of filenames for the same-size file grouping
      # but leave out the files we just weeded out from the group

      my @group = map { @{ $same_bytes->{ $_ } } } keys %$same_bytes;

      $self->push_mapped( $file_size => @group );
   }
}

1;
