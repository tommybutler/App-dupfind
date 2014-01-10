use strict;
use warnings;

package File::DupFind::Threaded::AllTasks;

use 5.010;

use Moose;
use MooseX::XSAccessor;

use lib 'lib';

extends 'File::DupFind::Threaded::MapReduce';

with 'File::DupFind::Threaded::MapReduce::Weed';

with 'File::DupFind::Threaded::MapReduce::Digest';

__PACKAGE__->meta->make_immutable;

1;
