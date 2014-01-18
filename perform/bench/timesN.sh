#!/bin/bash

function do_command_quietly () { $@ >/dev/null 2>&1 ; }

function repeat_command ()
{
   repeat=$1;

   shift;

   command=$1;

   shift;

   echo going to "'$command'" for "'$repeat'" times...

   for repetition in $( seq 1 $repeat );
   do
      echo -n doing repetition $repetition

      time do_command_quietly $@ 2>&1 | head -n1 | awk '{ print $2 }'
   done;

   echo all done
}

time repeat_command $@;
