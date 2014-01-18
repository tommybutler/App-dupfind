# ABSTRACT: Composed class providing seemless threading support for $bin/dupfind

use strict;
use warnings;

package App::dupfind::Threaded;

use 5.010;

use Moo;

use lib 'lib';

extends 'App::dupfind::Threaded::ThreadManagement';

extends 'App::dupfind::Threaded::MapReduce';

with 'App::dupfind::Threaded::MapReduce::Weed';

with 'App::dupfind::Threaded::MapReduce::Digest';

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 NAME

App::dupfind::Threaded - Composed class providing seamless threading support for $bin/dupfind

=head1 DESCRIPTION

yada yada

=cut

