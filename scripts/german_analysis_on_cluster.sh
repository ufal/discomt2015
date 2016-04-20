#!/bin/bash

inputdir=$1
outputdir=$2
is_trg=${3:-0}

mkdir -p log
job_count=`find $inputdir -name '*.txt' 2> /dev/null | wc -l`
i=0
for infile in $inputdir/*.txt; do
    echo "Processing $infile ..." >&2
    if [ $is_trg -ne 1 ]; then
        outfile=$outputdir/`basename -s .txt $infile`.conll
    else
        outfile=$outputdir/`basename $infile`
    fi
    if [ ! -e $outfile ]; then
        if [ $i -eq 0 ]; then
            if [ `qstat | wc -l` -gt 5000 ]; then
                echo "sleep 300" >&2
                sleep 300
            fi
        fi
        qsubmit --jobname='de_analysis' --mem="10g" --logdir="log/" \
            "scripts/german_analysis.sh $infile $outputdir $is_trg"
        i=$((i++))
        if [ $i -gt 500 ]; then
            i=0
        fi
    fi
done
if [ $is_trg -ne 1 ]; then
    pattern='*.conll'
else
    pattern='*.txt'
fi
while [ `find $outputdir -name "$pattern"  2> /dev/null | wc -l` -lt $job_count ]; do
    sleep 10
done
