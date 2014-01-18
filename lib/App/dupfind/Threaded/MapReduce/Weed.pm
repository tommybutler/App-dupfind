# ABSTRACT: Map-reduce version of weed_dups, and the worker thread for it

use strict;
use warnings;

package App::dupfind::Threaded::MapReduce::Weed;

use 5.010;

use threads;
use threads::shared;

use Moo::Role;

use Time::HiRes 'usleep';

requires 'opts';

sub weed_dups
{
   my ( $self, $size_dups ) = @_;

   # you have to do this for this threaded version of dupfind, and it has
   # to happen after you've already pruned out the hardlinks

   my $zero_files = delete $size_dups->{0};

   my $dup_count  = $self->count_dups( $size_dups );

   my ( $map_code, $pass_count, $new_count, $diff, $len );

   $len = $self->opts->{wpsize} || 32;

   for my $planned_pass ( $self->_plan_weed_passes )
   {
      $pass_count++;

      $self->say_stderr( "** $dup_count POTENTIAL DUPLICATES" );

      $map_code  = sub { $self->_weed_worker( $planned_pass, $len ) };

      $size_dups = $self->map_reduce( $size_dups => $map_code );

      $new_count = $self->count_dups( $size_dups );

      $diff      = $dup_count - $new_count;

      $dup_count = $new_count;

      $self->say_stderr( "   ...ELIMINATED $diff NON-DUPS IN PASS $pass_count" );
      $self->say_stderr( "      ...$new_count POTENTIAL DUPS REMAIN" );
   }

   $size_dups->{0} = &shared_clone( $zero_files ) if ref $zero_files;

   return $size_dups;
}

sub _weed_worker
{
   my ( $self, $weeder, $len ) = @_;

   WORKER: while
   (
       ! $self->term_flag
      && defined ( my $grouping = $self->work_queue->dequeue )
   )
   {
      my $same_bytes  = {};
      my $weed_failed = [];

      next unless !! @$grouping; # why?

      my $file_size = -s $grouping->[0];

      GROUPING: for my $file ( @$grouping )
      {
         my $bytes_read = $self->$weeder( $file, $len, $file_size );

         $self->increment_counter;

         push @{ $same_bytes->{ $bytes_read } }, $file
            if defined $bytes_read;

         push @$weed_failed, $file unless defined $bytes_read;
      }

      # delete obvious non-dupe files from the group of same-size files
      # by virtue of the fact that they will be a single length arrayref

      delete $same_bytes->{ $_ }
         for grep { @{ $same_bytes->{ $_ } } == 1 }
         keys %$same_bytes;

      # recompose the arrayref of filenames for the same-size file grouping
      # but leave out the files we just weeded out from the group

      my @group = map { @{ $same_bytes->{ $_ } } } keys %$same_bytes;

      push @group, @$weed_failed if @$weed_failed;

      $self->push_mapped( $file_size => @group );
   }
}

1;

__END__

=pod

=head1 NAME

App::dupfind::Threaded::MapReduce::Weed - Map-reduce version of weed_dups, and the worker thread for it

=head1 DESCRIPTION

Overrides the weed_dups method from App::dupfind::Common and implements an worker
thread routine that is invoked therein.  In this threaded version of weed_dups,
the set of same-size file groupings is mapped as a task and sent to the main
map reducer logic engine implemented in App::dupfind::Threaded::MapReduce.  The
outcome of that multithreaded map-reduce operation is a significantly smaller list
of potential duplicates (or no duplicates if none were left after the weeding-out).

Please don't use this module by itself.  It is for internal use only.

=head1 METHODS

=over

=item weed_dups

Calls the map-reduce logic on the $size_dups hashref, providing a wrapped
coderef calling out to _weed_worker for every weeding algorithm that has been
specified by the user.  The coderef mappings are then invoked by the map-reduce
engine for same-size size file groupings

This overrides the weed_dups method in App::dupfind::Common

=item _weed_worker

Runs weed-out passes for same-size file groupings, using $weeder, where $weeder
is a weed-out algorithm that tosses out non-dupes by use of more efficient
means than hashing alone.  The idea is to read as little as possible from the
disk while searching out dupes, and to use file hashing (digests) as a last
resort.

=back

=cut

