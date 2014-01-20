#!/usr/bin/env perl

use strict;
use warnings;

use Storable;
use File::Util;

my ( $datafile, $outfile ) = @ARGV;

die "Usage: $0 /path/to/data_file.txt /dest/outfile"
   unless -e $datafile && $outfile;

store( eval File::Util->new->load_file( $datafile ), $outfile );

exit;
