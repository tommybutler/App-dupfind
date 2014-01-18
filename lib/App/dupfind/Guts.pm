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

__END__

=pod

=head1 NAME

App::dupfind::Guts - Private methods supporting the App::dupfind::Common public interface

=head1 DESCRIPTION

These are private methods that are the underpinnings of the more friendly,
high-level public methods in App::dupfind::Common, which is where you should go
if you're searching for documentation on the App::dupfind namespace.

Please don't use this module by itself.  It is for internal use only.

=head1 ATTRIBUTES

=over

=item weed_pass_map

Conversion table for user-friendly names to the weeding algorithms to their
internal method names.

=item stats

R/W Hashref accessor used for internally storing statistics (specifically with
regard to cache hits/misses during the digest_dups phase)

=back

=head1 METHODS

=over

=item _plan_weed_passes

Based on either or both the default settings and the user-specified weed-out
algorithms to run on potential duplicates before resorting to calculating
digests, this private method builds the ordered execution plan which is then
caried out by $self->_pull_weeds

=item _pull_weeds

Runs the weed-out passes against the datastructure containing the list of
potential file duplicates.  A weed-out pass is simply the implementation of
a particular algorithm that can be run against a file or files in order to
determine the uniqueness of a file.

Weeding is typically much more efficient than calculating the digests of files
and so these digests are only calculated as a last resort.  Weeding out files
doesn't always get rid of all potential duplicates.  When it doesn't, that's
when you either (based on user input) run another different type of weeding
algorithm or fall back directly on file hashing (digests).

=item _do_weed_pass

Runs a single given weed-out pass against the list of potential file duplicates.

Keeps track of how many files it has scanned, how many non-duplicates it ruled
out, and how many potential duplicates remain.

=back

=cut

