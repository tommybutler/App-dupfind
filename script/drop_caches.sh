#!/bin/bash

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

if [[ $UID -ne 0 ]];
then
   echo Only run this script as root or with sudo.

   exit 1
fi

if [[ ! -e '/proc/sys/vm/drop_caches' ]];
then
   echo This script is for Linux only.

   exit 1
fi

echo -n Really clear system-wide buffered and cached RAM? '(y/N) '

read confirm;

if [[ "$confirm" == 'y' || "$confirm" == 'Y' ]];
then
   sync && sync && sync && echo 3 > /proc/sys/vm/drop_caches

   echo Buffered/Cached RAM cleared.
else
   echo Aborted.
fi
