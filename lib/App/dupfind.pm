# ABSTRACT: Composed class exposing the App::dupfind iface, used in $bin/dupfind

use strict;
use warnings;

package App::dupfind;

use 5.010;

use Moo;

use lib 'lib';

extends 'App::dupfind::Common';

with 'App::dupfind::Guts';

__PACKAGE__->meta->make_immutable;

1;
