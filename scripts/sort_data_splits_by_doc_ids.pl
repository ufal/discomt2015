#!/usr/bin/env perl

use strict;
use warnings;

my $input_dir = $ARGV[0];
my $input_doc_ids_file =$ARGV[1];

exit if (!-f $input_doc_ids_file);

open my $doc_ids_fh, "<:utf8:gzip", $input_doc_ids_file;
my @lines = <$doc_ids_fh>;

my @uniq_ids = ();
my $prev = undef;
foreach (@lines) {
    chomp $_;
    my ($doc_id) = split /\t/, $_;
    $doc_id =~ s/^.*\///;
    $doc_id =~ s/([^.]*)\..*$/$1/;
    if (!defined $prev || $doc_id ne $prev) {
        push @uniq_ids, $doc_id;
    }
    $prev = $doc_id;
}

my %ids_to_idx = map {$uniq_ids[$_] => $_} 0..$#uniq_ids;

my @all_files = glob "$input_dir/doc_*.txt";

my @sorted_files = sort {
    my $id_a = $a;
    $id_a =~ s/^.*doc_(.*)_....\.txt$/$1/g;
    my $id_b = $b;
    $id_b =~ s/^.*doc_(.*)_....\.txt$/$1/g;
    if ($ids_to_idx{$id_a} == $ids_to_idx{$id_b}) {
        $a cmp $b;
    }
    else {
        $ids_to_idx{$id_a} <=> $ids_to_idx{$id_b};
    }
} @all_files;

print join "\n", @sorted_files;
print "\n";
