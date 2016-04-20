#!/bin/bash

infile=$1
outdir=$2

filename=`basename $infile`
mkdir -p /COMP.TMP/mnovak
tmpdir=`mktemp -d --tmpdir='/COMP.TMP/mnovak' 'wmt16.trg_analysis.XXXXX'`
cat $infile | cut -f4 | \
    perl -ne 'chomp $_; my @words = split / /, $_; print join "\n", map {$_ =~ s/\|.*$//; $_} @words; print "\n";' \
    > $tmpdir/words.txt
java -Xmx2G -classpath tools/transition-1.30.jar is2.util.Split $tmpdir/words.txt > $tmpdir/words.conll
java -Xmx5G -classpath tools/transition-1.30.jar is2.transitionS2a.Parser -test $tmpdir/words.conll -out $tmpdir/words_annot.conll -model tools/pet-ger-S2a-40-0.25-0.1-2-2-ht4-hm4-kk0
cat $tmpdir/words_annot.conll | cut -f8 | grep -v "^$" > $outdir/$filename
rm -rf $tmpdir
