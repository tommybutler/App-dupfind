use strict;
use warnings;

package File::DupFind::Guts::Algorithms;

use 5.010;

use File::Util;
use Moo::Role;

requires 'opts';


sub _get_first_bytes
{
   my ( $self, $file, $len, $size ) = @_;

   my $buff;

   $len ||= 64;

   sysopen my $fh, $file, 0 or warn $!;

   return unless defined $fh;

   sysread $fh, $buff, $len;

   close $fh or return;

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

   close $fh or return;

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

   close $fh or return;

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

   close $fh or return;

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

   close $fh or return;

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

   close $fh or return;

   return $buff;
}

1;
