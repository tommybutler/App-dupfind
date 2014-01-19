
use strict;
use warnings;

use Test::More tests => 4;
use Test::NoWarnings;

use lib 'lib';

use App::dupfind;
use App::dupfind::Threaded;

my $adf = App::dupfind->new( opts => {} );

# check to see if App::dupfind ISA [foo, etc.]
ok
(
   UNIVERSAL::isa( $adf, 'App::dupfind' ),
   'ISA App::dupfind bless matches namespace'
);

$adf = App::dupfind::Threaded->new( opts => {} );

# check to see if App::dupfind ISA [foo, etc.]
ok
(
   UNIVERSAL::isa( $adf, 'App::dupfind' ),
   'ISA App::dupfind::Threaded bless matches superclass namespace'
);

# check to see if App::dupfind ISA [foo, etc.]
ok
(
   UNIVERSAL::isa( $adf, 'App::dupfind::Threaded' ),
   'ISA App::dupfind::Threaded bless matches own namespace'
);

exit;
