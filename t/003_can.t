
use strict;
use warnings;

use Test::More tests => 47;
use Test::NoWarnings;

use lib 'lib';

use App::dupfind::Threaded;

my $adf = App::dupfind::Threaded->new( opts => {} );

map { ok( ref( $adf->can( $_ ) ) eq 'CODE', "can $_" ) } qw
   (
      work_queue
      mapped
      counter
      reset_all
      reset_queue
      clear_counter
      reset_mapped
      increment_counter
      term_flag
      init_flag
      push_mapped
      delete_mapped
      create_thread_pool
      end_wait_thread_pool
      threads_progress
      map_reduce
      mapper
      reducer
      _get_first_bytes
      _get_middle_last_bytes
      _get_first_middle_last_bytes
      _get_last_bytes
      _get_middle_byte
      _get_bytes_n_offset_n
      _build_ftl
      _build_wpmap
      _plan_weed_passes
      _do_weed_pass
      _pull_weeds
      weed_pass_map
      ftl
      stats
      opts
      count_dups
      get_size_dups
      toss_out_hardlinks
      weed_dups
      digest_dups
      sort_dups
      show_dups
      delete_dups
      cache_stats
      say_stderr
      add_stats
      _digest_worker
      _weed_worker

   );

exit;
