
use strict;
use warnings;

use Test::More tests => 3;
use Test::NoWarnings;

use lib 'lib';

use App::dupfind;
use App::dupfind::Threaded;


# check object constructor
ok
(
   ref App::dupfind->new( opts => {} ) eq 'App::dupfind',
   'New bare App::dupfind class instantiation'
);

# check object constructor
ok
(
   ref App::dupfind::Threaded->new( opts => {} ) eq 'App::dupfind::Threaded',
   'New bare App::dupfind class instantiation'
);

exit;
