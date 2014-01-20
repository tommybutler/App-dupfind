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
   require Term::ProgressBar if shift->opts->{progress}
};

before delete_dups => sub { require Term::Prompt };


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
               ## my ( $selfdir, $subdirs, $files ) = @_;

               my $files = $_[2]; # save two vars

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
      my $files = pop;

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

      say sprintf 'ORIGINAL (%s) %s', $digest, $group->[0];

      shift @$group;

      for my $dup ( @$group )
      {
         if ( $self->opts->{prompt} )
         {
            unless ( Term::Prompt::prompt( 'y', "REMOVE DUPE? $dup", '', 'n' ) )
            {
               say sprintf 'KEPT     (%s) %s', $digest, $dup;

               next;
            }
         }

         unlink $dup or warn "COULD NOT REMOVE $dup!  $!" and next;

         $removed++;

         say sprintf 'REMOVED  (%s) %s', $digest, $dup;
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

__END__

=pod

=head1 NAME

App::dupfind::Common - Public methods for the App::dupfind deduplication engine

=head1 DESCRIPTION

Together with App::dupfind::Guts, the methods from this module are composed into
the App::dupfind class in order to provide the user with the high-level methods
that are directly callable from the user's application.

=head1 INTERNALS

There are some implementation-based concepts that don't really matter to the
end user, but which are briefly discussed here because they form concepts that
are used throughout the entirety of the codebase and are referred to by a large
number of documented class methods.

=head2 THE DUPLICATES MASTER HASH

Potential duplicate files are kept in groupings of same-size files, organized
by file size.  They are tracked in a hashref datastructure.

Specifically, the keys of the hashref are the integers indicating file sizes
in bytes.  The corresponding value for each of these "size" keys is a listref
containing the group of filenames that are of that file size.

Random example:

   $dupes =
      {
         0 => # a zero-size file
            [
               '~/run/some_file.lock',
            ],

         1024 => # some files that are 1024 bytes
            [
               '~/Pictures/kitty.jpg',
               '~/Pictures/cat.jpg'
               '~/.cache/foo'
            ],

         4096 => # some files that are 4096 bytes
            [
               '~/Documents/notes.txt',
               '~/Downloads/bar.gif',
            ],
      }

=head1 METHODS

=over

=item cache_stats

Retrieve information about cache hits/misses that happened during the
calculation of file digests in the digest_dups method.  Used as part of the
run summary that gets printed out at the end of execution of $bin/dupfind

Returns $cache_hits, $cache_misses (both integers)

=item count_dups

Examines its argument and sums up the number of its members.  Expects a
datastructure in the form of the master dupes hashref.

Returns $dup_count (integer)

=item delete_dups

Deletes duplicate files, optionally prompting the user for which files to
delete and for confirmation of deletion (if command-line parameters supplied
by the user dictate that interactive prompting is desired)

Returns nothing

=item digest_dups

Expects a datastructure in the form of the master dupes hashref.

Iterates over the datastructure and calculates digests for each of the files.

If ramcache is enabled (which is the default), a rudimentary caching mechanism
is used in order to avoid calculating digests multiple times for files with
the same content.

Returns a lexical copy of the duplicates hashref with non-dupes removed

=item get_size_dups

Scans the directory specified by the user and assembles the master dupes
hashref datastructure as described above.  Files with no same-size counterparts
are not included in the datastructure.

Returns $dupes_hashref, $scan_count, $size_dup_count ...
...where $dupes_hashref is the master duplicates hashref, $scan_count is the
number of files that were scanned, and $size_dup_count is the total number of
same-size files encompassing each same-size group

=item opts

A read-only accessor method that returns a hashref of options as specified by
either or both of the default settings and user input at invocation time.

Examples:

   $self->opts->{threads}  # contains the number of threads the user wants
   $self->opts->{dir}      # name of the directory to scan for duplicates

=item say_stderr

The same as Perl's built-in say function, except that:

=over

=item *

It is a class method

=item *

It outputs to STDERR instead of STDOUT

=back

=item show_dups

Expects a datastructure in the form of the master dupes hashref.

Produces the formatted output for $bin/dupfind based on what duplicate files
were found during execution.  Currently two output formats are supported:
"human" and "robot".  Logically, the robot output is easily machine-parsable,
while the human output is more visually palatable to human users (it makes
sense to people).

Returns the number of duplicates shown.

=item sort_dups

Expects a datastructure in the form of the master dupes hashref.

Iterates through the hashref and examines the listrefs of file names that
comprise its values.  It then sorts the listrefs in place with the following
sort:

   sort { $a cmp $b }

Returns a lexical copy of the newly-sorted master duplicates hashref

=item toss_out_hardlinks

Expects a datastructure in the form of the master dupes hashref.

Iterates through the hashref and examines the listrefs of file names that
comprise its values.

For each file in each group, it looks at the underlying storage for the file
on the storage medium using a stat call.  Any files with the same
device major number AND the same inode number are obvious hardlinks.

After alphabetizing any hard links that are detected, it throws out all hard
links but the first one.  This simplifies the output, and the easy rationale
behind this is that a hard link constitutes a file that has already been
deduplicated because it refers to the same underlying storage.

Returns a lexical copy of the master duplicates hashref

=item weed_dups

Expects a datastructure in the form of the master dupes hashref.

Runs the weed out pass(es) on the datastructure in an attempt to eliminate
as many non-duplicate files as possible from the same-size file groupings
without having to resort to resource-intensive file hashing (i.e.- the
calculation of file digests).

If no duplicates remain after the weed out pass(es), then the need for
hashing is obviated and it doesn't get performed.  For any remaining
potential duplicates however, the hashing is ultimately used to provide
the final decision on file uniqueness.

One or more passes may be performed, based on user input.  Currently the
default is to use only one pass, with the "first_middle_last" weed-out
algorithm which has proved so far to be the most efficient.

Returns a (hopefully reduced) lexical copy of the master duplicates hashref

=back

=cut

