#!/usr/bin/env perl

use strict;
use warnings;
use Data::Dumper;
use List::Util qw/min/;

my @CLASSES = qw/
OTHER
il
ce
elle
ils
elles
cela
on
ça
/;

my $orig_data = $ARGV[0];

open my $fh_orig, "<:gzip:utf8", $orig_data;
while (my $orig_line = <$fh_orig>) {
    chomp $orig_line;
    my ($class, $miss_word, $en_sent, $fr_sent, $ali) = split /\t/, $orig_line;
    my $replace_num = scalar(split /REPLACE_[0-9]+/, $fr_sent) - 1;

    my @scores_per_instance = ();
    while ($replace_num && (my $res_line = <STDIN>)) {
        if ($res_line =~ /^\s*$/) {
            my $min = min @scores_per_instance;
            my ($min_idx) = grep {$scores_per_instance[$_] == $min} 0 .. $#scores_per_instance;
            print $CLASSES[$min_idx];
            
            $replace_num--;
            if ($replace_num) {
                print " ";
            }
            @scores_per_instance = ();
            next;
        }
        my ($pred, $tag) = split / /, $res_line;
        my ($id, $score) = split /:/, $pred;
        push @scores_per_instance, $score;
    }
    print "\n";
}
close $fh_orig;
