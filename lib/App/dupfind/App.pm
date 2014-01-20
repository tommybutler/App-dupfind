# ABSTRACT: This is the application that gets run() by $bin/dupfind

use strict;
use warnings;

package App::dupfind::App;

BEGIN { STDERR->autoflush; STDOUT->autoflush; }

use 5.010;

use Getopt::Long;
use Benchmark ':hireswallclock';

use lib 'lib';

use App::dupfind;
use App::dupfind::Threaded;

use Moo;

exit run() unless caller;

has opts =>
(
   is       => 'rw',
   required => 1,
   builder  => '_build_opts'
);

has metrics =>
(
   is       => 'rw',
   required => 1,
   builder  => sub
   {
      {
         scan_count     => 0,
         size_dup_count => 0,
         real_dup_count => 0,
      }
   }
);

has benchmarks =>
(
   is       => 'rw',
   required => 1,
   builder  => sub
   {
      {
         scanfs   => { },
         prune    => { },
         weed     => { },
         digest   => { },
         remove   => { },
         run      => { },
      }
   }
);

has deduper =>
(
   is       => 'ro',
   required => 1,
   lazy     => 1,
   builder  => sub
   {
      my $self    = shift;
      my $ddclass = $self->opts->{threads}
         ? 'App::dupfind::Threaded'
         : 'App::dupfind';

      $ddclass->new( opts => $self->opts );
   }
);


sub BUILD
{
   my $self = shift;
   my $opts = $self->opts;

   $opts->{threads} //= 0;

   $opts->{progress}  = 1 if $opts->{verbose};

   $opts->{remove}    = 1 if $opts->{prompt};

   $opts->{weed}      = 0 if $opts->{weed} =~ /^(n|no)$/i;

   $opts->{weed}      = 1 if !! @{ $opts->{wpass} };

   $opts->{wpass}     = [ 'first_middle_last' ]
      if $opts->{weed} && ! @{ $opts->{wpass} };

   die 'Bogus cache parameters provided!  Just use the defaults buddy.'
      if $opts->{cachestop} < 0 || $opts->{ramcache} < 0;

   die 'Invalid cachestop size; must be a small fraction of total ramcache.'
      if $opts->{ramcache} && $opts->{cachestop} > ( $opts->{ramcache} / 100 );

   $opts->{cachesize} = int ( $opts->{ramcache} / $opts->{cachestop} );
}

sub _build_opts
{
   my $self = shift;

   my $opts =
   {
      bytes     => 1024 ** 3,           # 1 GB max read
      cachestop => ( 1024 ** 2 ) * 2,   # 2 MB file size limit on cache candidacy
      dir       => undef,
      format    => 'human',             # options are "human" or "robot"
      help      => undef,
      links     => 0,
      maxdepth  => 50,
      progress  => 0,
      prompt    => 0,
      quiet     => 0,
      ramcache  => ( 1024 ** 2 ) * 300, # 300 MB default cache size
      remove    => 0,
      threads   => 0,
      verbose   => 0,
      weed      => 1,
      wpass     => [ ],
      wpsize    => 32,
   };

   GetOptions
   (
      'bytes|b=i'    => \$opts->{bytes},
      'cachestop=i'  => \$opts->{cachestop},
      'dir|d=s'      => \$opts->{dir},
      'format|f=s'   => \$opts->{format},
      'help|h|?'     => \$opts->{help},
      'links|l'      => \$opts->{links},
      'maxdepth|m=i' => \$opts->{maxdepth},
      'progress'     => \$opts->{progress},
      'prompt|p'     => \$opts->{prompt},
      'quiet|q'      => \$opts->{quiet},
      'ramcache=i'   => \$opts->{ramcache},
      'remove|x'     => \$opts->{remove},
      'threads|t=i'  => \$opts->{threads},
      'verbose|v'    => \$opts->{verbose},
      'weedout|w=s'  => \$opts->{weed},
      'wpass=s'      =>  $opts->{wpass},
      'wpsize=i'     => \$opts->{wpsize},
   ) or exit _usage();

   exit _usage() unless defined $opts->{dir};

   return $opts;
}

sub _usage
{
   # This is just the help message:

   require Pod::Usage;

   Pod::Usage::pod2usage( { -exitval => 1, -verbose => 2 } )
}

sub _bench_this
{
   my ( $self, $mark, $event ) = @_;

   $self->benchmarks->{ $mark }->{ $event } = Benchmark->new();
}

sub _calculate_bench_times
{
   my $self       = shift;
   my $benchmarks = $self->benchmarks;

   for my $mark ( keys %$benchmarks )
   {
      next unless $benchmarks->{ $mark }->{start};

      $self->benchmarks->{ $mark }->{result} =
         timestr timediff
         (
            $benchmarks->{ $mark }->{end},
            $benchmarks->{ $mark }->{start}
         );
   }

   $self->benchmarks->{weed}->{result}   ||= 'did not weed';
   $self->benchmarks->{remove}->{result} ||= 'no deletions';
}

sub _run_summary
{
   my $self        = shift;
   my $opts        = $self->opts;
   my $benchmarks  = $self->benchmarks;
   my $metrics     = $self->metrics;

   my ( $cache_hits, $cache_misses ) = $self->deduper->cache_stats;

   $self->_stderr( <<__SUMMARY__ );
------------------------------
** THREADS...............$opts->{threads}
** RAM CACHE.............$opts->{ramcache} bytes
** CACHE HITS/MISSES.....$cache_hits/$cache_misses
** TOTAL FILES SCANNED...$metrics->{scan_count}
** TOTAL SAME SIZE.......$metrics->{size_dup_count}
** TOTAL ACTUAL DUPES....$metrics->{real_dup_count}
      -- TIMES --
** TREE SCAN TIME........$benchmarks->{scanfs}->{result}
** HARDLINK PRUNE TIME...$benchmarks->{prune}->{result}
** WEED-OUT TIME.........$benchmarks->{weed}->{result}
** CRYPTO-HASHING TIME...$benchmarks->{digest}->{result}
** DELETION TIME.........$benchmarks->{remove}->{result}
** TOTAL RUN TIME........$benchmarks->{run}->{result}
__SUMMARY__
}

sub run
{
   my $self = __PACKAGE__->new();

   $self->_bench_this( run => 'start' );

   my( $size_dups, $pruned_dups, $weeded_dups, $digest_dups );

   $size_dups   = $self->scanfs;

   $pruned_dups = $self->prune( $size_dups );

   $weeded_dups = $self->weed( $pruned_dups ) if $self->opts->{weed};

   $digest_dups = $self->digest( $weeded_dups // $pruned_dups );

   $self->metrics->{real_dup_count} = $self->deduper->count_dups( $digest_dups );

   $self->_stderr( '** DISPLAYING OUTPUT', '-' x 30 );

   $self->deduper->show_dups( $digest_dups );

   $self->remove( $digest_dups ) if $self->opts->{remove};

   $self->_bench_this( run => 'end' );

   $self->_calculate_bench_times;

   $self->_run_summary;
}

sub scanfs
{
   my $self = shift;

   $self->_stderr( '** SCANNING ALL FILES FOR SIZE DUPLICATES' );

   $self->_bench_this( scanfs => 'start' );

   my ( $size_dups, $scan_ct, $size_dup_ct ) = $self->deduper->get_size_dups();

   $self->metrics->{scan_count}     = $scan_ct;

   $self->metrics->{size_dup_count} = $size_dup_ct;

   $self->_bench_this( scanfs => 'end' );

   say '** NO DUPLICATES FOUND' and exit unless keys %$size_dups;

   return $size_dups;
}

sub prune
{
   my ( $self, $size_dups ) = @_;

   $self->_stderr( '** PRUNING HARD LINKS' );

   $self->_bench_this( prune => 'start' );

   $size_dups = $self->deduper->toss_out_hardlinks( $size_dups );

   $self->_bench_this( prune => 'end' );

   say '** NO DUPLICATES FOUND' and exit unless keys %$size_dups;

   return $size_dups;
}

sub weed
{
   my ( $self, $size_dups ) = @_;

   $self->_stderr( '** WEEDING-OUT FILES THAT ARE OBVIOUSLY DIFFERENT' );

   $self->_bench_this( weed => 'start' );

   my $weeded_dups = $self->deduper->weed_dups( $size_dups );

   $self->_bench_this( weed => 'end' );

   say '** NO DUPLICATES FOUND' and exit unless keys %$weeded_dups;

   return $weeded_dups;
}

sub digest
{
   my ( $self, $size_dups ) = @_;

   $self->_stderr( '** CHECKSUMMING SIZE DUPLICATES' );

   $self->_bench_this( digest => 'start' );

   my $digest_dups = $self->deduper->digest_dups( $size_dups );

   $self->_bench_this( digest => 'end' );

   say '** NO DUPLICATES FOUND' and exit unless keys %$digest_dups;

   return $digest_dups;
}

sub remove
{
   my ( $self, $digests ) = @_;

   $self->_bench_this( remove => 'start' );

   $self->deduper->delete_dups( $digests );

   $self->_bench_this( remove => 'end' );
}

sub _stderr { return if shift->opts->{quiet}; warn "$_\n" for @_ };

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 NAME

App::dupfind::App - This is the application that gets run() by $bin/dupfind

=head1 DESCRIPTION

This app-in-a-module is run by the dupfind script itself.  This module isn't
meant to be the interface for the end-user (that's the purpose of the dupfind
script which is bundled with this distribution).  The reason the logic is
packed up in this module is to allow for easier unit testing, and also to allow
the application to be extended via inheritance if desired.

So basically, you don't really need to worry about this.  Just install the
App::dupfind distribution and call the dupfind executable in the way you'd
invoke any other app.

=head1 SYNOPSIS

   use App::dupfind::App;

   App::dupfind::App->run;

=head1 ATTRIBUTES

=over

=item opts

Accessor for run time options supplied by the user

=item benchmarks

Accessor to a collection of benchmarks that are gathered over the course
of application execution

=item metrics

Accessor used to save and retrieve metrics information

=item deduper

Depending on user input, it will be an App::dupfind object or an
App::dupfind::Threaded object (if threading was selected).

=back

=head1 METHODS

=over

=item BUILD

The object builder.  Does some validation of user input.

=item _usage

Prints out a help message via Pod::Usage so that the POD documentation in
whatever namespace calls the app gets used as the help message.

This is why $bin/dupfind is very short on code, but has a good POD page.

=item _bench_this

Private method used to make internal benchmarking easier, since the application
makes frequent use of them to time key steps in its workflow.

=item _calculate_bench_times

Takes the collected benchmark objects gathered in the previous method and
calculates the time difference between their start and end marks, then tucks
it away for later display in $self->_run_summary

=item _run_summary

Displays a summary of findings and metrics after the main output is shown.  The
summary looks something like this (some output has been replaced with "..." due
to space constraints):

   ------------------------------
   ** THREADS...............8
   ** RAM CACHE.............314572800 bytes
   ** CACHE HITS/MISSES.....21162392/14997229
   ** TOTAL FILES SCANNED...73389
   ** TOTAL SAME SIZE.......66058
   ** TOTAL ACTUAL DUPES....48760
         -- TIMES --
   ** TREE SCAN TIME........1.78502 wallclock secs  ...
   ** HARDLINK PRUNE TIME...0.438269 wallclock secs ...
   ** WEED-OUT TIME.........4.14188 wallclock secs  ...
   ** CRYPTO-HASHING TIME...6.25566 wallclock secs  ...
   ** DELETION TIME.........no deletions
   ** TOTAL RUN TIME........14.6825 wallclock secs  ...

=item run

Runs the application.  Takes no arguments.  Returns no values.

=item scanfs

Scans the filesystem directory specified by the user and returns a
datastructure containing groupings of files that are the same size, which is
the first step in identifying duplicates.

=item prune

Examines the files returned from $self->scanfs and looks for hard links.  If
two or more hardlinks are found, they are sorted by filename and all but the
first hardlink are discarded.

=item weed

Runs the weed-out pass(es) on the file groups returned by $self->prune, thereby
eliminating as many non-duplicates as possible without having to resort to
expensive file hashing (the calculation of file digests).

=item digest

Calculates file digests against the files returned from $self->weed, and a
simple caching mechanism is used to help avoid hashing the same file content
more than once if one file is found to be a content match for another.

This is the final basis upon which file uniqueness is determined.  After this
step, we know with very-near-complete certainty which files are duplicates.

The certainty is limited to the strength of the underlying cryptographic digest
algorithm, which is currently xxhash.  As with other digests, such as MD5 for
example, collisions are possible but extremely unlikely.

=item remove

Runs a removal (deletion) sequence on file duplicates obtained by $self->digest,
interactively prompting the user for confirmation of deletions.  Interactive
prompting does not happen if the user specified that prompting should be
disabled.

Refer to the help documentation in the dupfind executable proper for an
explanation on run time command line options and switches.

=item _stderr

Works like Perl's built-in say function, except:

=over

=item *

Output goes to STDERR

=item *

It is a class method.  You will have to call it like $object->_stderr( 'foo' );

=item *

IT OUTPUTS NOTHING if the user passed in the "-q" or "--quiet" flag.

=back

=back

=cut

