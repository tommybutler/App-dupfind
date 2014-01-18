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

__END__

=pod

=head1 NAME

App::dupfind - Composed class exposing the App::dupfind interface used in $bin/dupfind

=head1 DESCRIPTION

The real magic in this module takes place in the namespaces it subclasses and in
the roles it consumes.  See the POD in the following modules to get the details
of what this class actually does by virtue of inheritance:

=over

=item *

App::dupfind::Common

=item *

App::dupfind::Guts

=back

=head1 COPYRIGHT

Copyright(C) 2013-2014, Tommy Butler.  All rights reserved.

=head1 LICENSE

This library is free software, you may redistribute it and/or modify it
under the same terms as Perl itself. For more details, see the full text of
the LICENSE file that is included in this distribution.

=cut

