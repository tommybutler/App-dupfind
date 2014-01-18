# ABSTRACT: The private weeding algorithms available for use by public interface

use strict;
use warnings;

package App::dupfind::Guts::Algorithms;

use 5.010;

use File::Util;
use Moo::Role;

requires 'opts';


sub _get_first_bytes
{
   my ( $self, $file, $len ) = @_;

   my $buff;

   $len ||= 64;

   sysopen my $fh, $file, 0 or warn $!;

   return unless defined $fh;

   sysread $fh, $buff, $len;

   close $fh or warn qq(Couldn't close filehandle to $file $!);

   return $buff;
}

sub _get_middle_last_bytes
{
   my ( $self, $file, $len, $size ) = @_;

   my ( $buff_mid, $buff_last );

   $len ||= 32;

   my $pos = int $size / 2;

   sysopen my $fh, $file, 0 or warn $!;

   return unless defined $fh;

   sysseek $fh, $pos, 0;

   sysread $fh, $buff_mid, 1;

   sysseek $fh, $size - $len, 0;

   sysread $fh, $buff_last, $len;

   close $fh or warn qq(Couldn't close filehandle to $file $!);

   return $buff_mid . $buff_last;
}

sub _get_first_middle_last_bytes
{
   my ( $self, $file, $len, $size ) = @_;

   my ( $buff_first, $buff_mid, $buff_last );

   $len ||= 32;

   my $pos = int $size / 2;

   sysopen my $fh, $file, 0 or warn $!;

   return unless defined $fh;

   sysread $fh, $buff_first, $len;

   close $fh and return $buff_first if $size <= $len;

   sysseek $fh, $pos, 0;

   sysread $fh, $buff_mid, 1;

   sysseek $fh, $size - $len, 0;

   sysread $fh, $buff_last, $len;

   close $fh or warn qq(Couldn't close filehandle to $file $!);

   return $buff_first . $buff_mid . $buff_last;
}

sub _get_last_bytes
{
   my ( $self, $file, $len, $size ) = @_;

   my $buff;

   $len ||= 64;

   sysopen my $fh, $file, 0 or warn $!;

   return unless defined $fh;

   sysseek $fh, $size - $len, 0;

   sysread $fh, $buff, $len;

   close $fh or warn qq(Couldn't close filehandle to $file $!);

   return $buff;
}

sub _get_middle_byte
{
   my ( $self, $file, $len, $size ) = @_;

   my $buff;

   $len = 1;

   my $pos = int $size / 2;

   sysopen my $fh, $file, 0 or warn $!;

   return unless defined $fh;

   sysseek $fh, $pos, 0;

   sysread $fh, $buff, $len;

   close $fh or warn qq(Couldn't close filehandle to $file $!);

   return $buff;
}

sub _get_bytes_n_offset_n
{
   my ( $self, $file, $len, $size, $pos ) = @_;

   my $buff;

   $len ||= 32;

   return if $size <= $len;

   $pos ||= int $size / 3;

   sysopen my $fh, $file, 0 or warn $!;

   return unless defined $fh;

   sysseek $fh, $pos, 0;

   sysread $fh, $buff, $len;

   close $fh or warn qq(Couldn't close filehandle to $file $!);

   return $buff;
}

1;

__END__

=pod

=head1 NAME

App::dupfind::Guts::Algorithms - The private weeding algorithms available for use by public interface

=head1 DESCRIPTION

Unless you're contributing to the codebase, don't go poking around here.
This is a private namespace that implements the algorithms that are exposed
to the user in the application interface, which is where you should go
looking if you are searching for algorithms to use for weeding-out dupes.

Please don't use this module by itself.  It is for internal use only.

=cut

