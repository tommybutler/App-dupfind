# ABSTRACT: Private methods supporting the App::dupfind::Common public interface

use strict;
use warnings;

package App::dupfind::Guts;

use 5.010;

use File::Util;

use Moo::Role;

use lib 'lib';

requires 'opts';

with 'App::dupfind::Guts::Algorithms';

has weed_pass_map => ( is => 'ro', builder => '_build_wpmap' );

has ftl => ( is => 'ro', builder => '_build_ftl', lazy => 1 );

has stats => ( is => 'rw', builder => sub { {} } );


sub _build_ftl
{
   my $self = shift;

   return File::Util->new
   (
      {
         use_flock   => 0,
         diag        => 1,
         read_limit  => $self->opts->{bytes},
         abort_depth => $self->opts->{maxdepth},
         onfail      => 'undefined',
      }
   );
}

sub _build_wpmap
{
   {
                   last => '_get_last_bytes',
                  first => '_get_first_bytes',
                 middle => '_get_middle_byte',
            middle_last => '_get_middle_last_bytes',
          almost_middle => '_get_bytes_n_offset_n',
      first_middle_last => '_get_first_middle_last_bytes',
   }
}

sub _plan_weed_passes
{
   my $self = shift;
   my @plan = ();

   for my $pass_type ( @{ $self->opts->{wpass} } )
   {
      die "Unrecognized weed pass type $pass_type"
         if ! exists $self->weed_pass_map->{ $pass_type };

      push @plan, $self->weed_pass_map->{ $pass_type };
   }

   return @plan;
}

sub _do_weed_pass
{
   my ( $self, $size_dups, $pass_type, $pass_count ) = @_;

   my $dup_count = $self->count_dups( $size_dups );

   my ( $new_count, $difference );

   $self->say_stderr( "      $dup_count POTENTIAL DUPLICATES" );

   $size_dups  = $self->_pull_weeds( $size_dups => $pass_type => $pass_count );

   $new_count  = $self->count_dups( $size_dups );

   $difference = $dup_count - $new_count;

   $dup_count  = $new_count;

   $self->say_stderr( <<__WEED_PASS__ );
      ...ELIMINATED $difference NON-DUPS IN PASS #$pass_count. $new_count REMAIN
__WEED_PASS__

   return $size_dups;
}

sub _pull_weeds
{
   # weed out files that are obviously different, based on the last
   # few bytes in the file.  This saves us from unnecessary hashing

   my ( $self, $size_dups, $weeder, $pass_count ) = @_;

   my $len = $self->opts->{wpsize};

   my ( $progress, $i );

   if ( $self->opts->{progress} )
   {
      my $dup_count = $self->count_dups( $size_dups );

      $progress = Term::ProgressBar->new
      (
         {
            name   => '   ...WEED-OUT PASS ' . $pass_count,
            count  => $dup_count,
            remove => 1,
         }
      );
   }

   for my $same_size ( keys %$size_dups )
   {
      my $same_bytes  = {};
      my $weed_failed = [];

      for my $file ( @{ $size_dups->{ $same_size } } )
      {
         my $bytes_read = $self->$weeder( $file, $len, $same_size );

         push @{ $same_bytes->{ $bytes_read } }, $file
            if defined $bytes_read;

         push @$weed_failed, $file unless defined $bytes_read;

         $progress->update( $i++ ) if $progress;
      }

      # delete obvious non-dupe files from the group of same-size files
      # by virtue of the fact that they will be a single length arrayref

      delete $same_bytes->{ $_ }
         for grep { @{ $same_bytes->{ $_ } } == 1 }
         keys %$same_bytes;

      # recompose the arrayref of filenames for the same-size file grouping
      # but leave out the files we just weeded out from the group

      $size_dups->{ $same_size } = []; # start fresh

      @{ $size_dups->{ $same_size } } =
         map { @{ $same_bytes->{ $_ } } }
         keys %$same_bytes;

      push @{ $size_dups->{ $same_size } }, @$weed_failed if @$weed_failed;
   }

   $progress->update( $i ) if $progress;

   return $size_dups;
}

1;
