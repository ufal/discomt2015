#!/usr/bin/env perl

use strict;
use warnings;

my $sents_per_doc = 50;
my $out_dir = $ARGV[0];
my $doc_idx_file = $ARGV[1];

my $doc_idx_fh;
if (defined $doc_idx_file) {
    open $doc_idx_fh, "<:gzip:utf8", $doc_idx_file;
}

my $line_num = 0;
my $sents_in_doc = 0;
my $doc_part = 1;
my $prev_doc_id;
my $new_doc = 1;
my $out_fh;

while (my $line = <STDIN>) {
    if ($line_num % 100000 == 0) {
        print STDERR "Processed lines: " . $line_num . "\n";
    }

    if (defined $doc_idx_fh) {
        my $doc_idx_line = <$doc_idx_fh>;
        my ($doc_id) = split /\t/, $doc_idx_line;
        $doc_id =~ s/^.*\///;
        $doc_id =~ s/([^.]*)\..*$/$1/;
        chomp $doc_id;
        if (!defined $prev_doc_id || ($doc_id ne $prev_doc_id)) {
            $new_doc = 1;
            $doc_part = 1;
        }
        $prev_doc_id = $doc_id;
    }
    
    if ($sents_in_doc >= $sents_per_doc) {
        $new_doc = 1;
        $doc_part++;
        #$prev_doc_id = sprintf "%08d", $line_num / $sents_per_doc;
    }

    if ($new_doc) {
        if (defined $out_fh) {
            close $out_fh;
        }
        my $out_path = $out_dir . "/doc_" . ($prev_doc_id // "") . "_" . sprintf("%04d", $doc_part) . ".txt";
        #print STDERR $out_path . "\n";
        open $out_fh, ">", $out_path;
        $sents_in_doc = 0;
    }

    print $out_fh $line;

    $sents_in_doc++;
    $line_num++;
    $new_doc = 0;
}
if (defined $out_fh) {
    close $out_fh;
}
if (defined $doc_idx_fh) {
    close $doc_idx_fh;
}
