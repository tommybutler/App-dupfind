use strict;
use warnings;

package File::DupFind;

use 5.010;

use Moose;
use File::Util;
use Digest::xxHash 'xxhash_hex';
use Term::Prompt 'prompt';
use Term::ProgressBar;

has opts => ( is => 'ro', isa => 'HashRef', required => 1 );
has ftl  => ( is => 'ro', lazy_build => 1 );

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

sub get_size_dups
{
   my $self = shift;

   my ( $size_dups, $scan_count, $size_dup_count ) = ( {}, 0, 0 );

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

   $size_dup_count += @$_ for map { $size_dups->{ $_ } } keys %$size_dups;

   return $size_dups, $scan_count, $size_dup_count;
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

   $size_dups = $self->_pull_weeds
      (
         $size_dups => '_get_file_first_bytes' => ++$pass_count
      );

   $size_dups = $self->_pull_weeds
      (
         $size_dups => '_get_file_last_bytes' => ++$pass_count
      );

   $size_dups->{0} = $zero_sized if ref $zero_sized;

   return $size_dups;
}

sub _pull_weeds
{
   # weed out files that are obviously different, based on the last
   # few bytes in the file.  This saves us from unnecessary hashing

   my ( $self, $size_dups, $weeder, $pass_count ) = @_;

   my $dup_count = 0;

   $dup_count += @$_ for map { $size_dups->{ $_ } } keys %$size_dups;

   my $progress_bar = Term::ProgressBar->new
      (
         {
            name   => '   ...WEED-OUT PASS ' . $pass_count,
            count  => $dup_count,
            remove => 1,
         }
      );

   my $i = 0;

   for my $same_size ( keys %$size_dups )
   {
      my @group = sort { $a cmp $b } @{ $size_dups->{ $same_size } };

      my $same_bytes = {};

      for my $file ( @group )
      {
         my $bytes_read = $self->$weeder( $file );

         push @{ $same_bytes->{ $bytes_read } }, $file
            if defined $bytes_read;

         $progress_bar->update( $i++ );
      }

      # delete obvious non-dupe files from the group of same-size files
      # by virtue of the fact that they will be a single length arrayref

      delete $same_bytes->{ $_ }
         for grep { @{ $same_bytes->{ $_ } } == 1 }
         keys %$same_bytes;

      # recompose the arrayref of filenames for the same-size file grouping
      # but leave out the files we just weeded out from the group

      $size_dups->{ $same_size } = []; # start fresh

      push @{ $size_dups->{ $same_size } },
         map { @{ $same_bytes->{ $_ } } }
         keys %$same_bytes;
   }

   $progress_bar->update( $i );

   return $size_dups;
}

sub _get_file_first_bytes
{
   my ( $self, $file, $len ) = @_;

   my $buff;

   $len ||= 64;

   sysopen my $fh, $file, 0 or warn $!;

   return unless defined $fh;

   sysread $fh, $buff, $len;

   close $fh or return;

   return $buff;
}

sub _get_file_last_bytes
{
   my ( $self, $file, $len ) = @_;

   my $buff;

   $len ||= 64;

   sysopen my $fh, $file, 0 or warn $!;

   return unless defined $fh;

   sysseek $fh, $len - $len, 0;

   sysread $fh, $buff, $len;

   close $fh or return;

   return $buff;
}

sub digest_dups
{
   my ( $self, $size_dups ) = @_;
   my $digests   = {};
   my $dup_count = 0;
   my $prgs_iter = 0;

   # don't bother to hash zero-size files
   $digests->{ xxhash_hex '', 0 } = delete $size_dups->{0}
      if exists $size_dups->{0};

   $dup_count += @$_ for map { $size_dups->{ $_ } } keys %$size_dups;

   my $progress  = Term::ProgressBar->new
      (
         {
            name   => '   ...PROGRESS',
            count  => $dup_count,
            remove => 1,
         }
      );

   local $/;

   for my $size ( keys %$size_dups )
   {
      my $group = $size_dups->{ $size };

      for my $file ( @$group )
      {
         open my $fh, '<', $file or next;

         my $data = <$fh>;

         close $fh;

         my $digest = xxhash_hex $data, 0;

         push @{ $digests->{ $digest } }, $file;

         $progress->update( $prgs_iter++ );
      }
   }

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

   $progress->update( $dup_count );

   undef $digests;

   return $priv_digests;
}

sub show_dups
{
   my ( $self, $digests ) = @_;
   my $dupes = 0;

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
            unless ( prompt 'y', "REMOVE DUPLICATE? $dup", '', 'n' )
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

__PACKAGE__->meta->make_immutable;

1;
