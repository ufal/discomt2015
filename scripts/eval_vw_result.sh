#!/bin/bash

test_data=$1
result_file=$2
transl_pair=$3
out_result_file=$4
out_eval_file=$5

cat $result_file | scripts/vw_res_to_official_res.pl $test_data $transl_pair > $out_result_file
perl eval/WMT16_CLPP_scorer.pl <( zcat $test_data ) $out_result_file $transl_pair > $out_eval_file
