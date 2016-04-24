#!/usr/bin/env perl

use strict;
use warnings;

my $distr_file = $ARGV[0];

my %losses = ();
open my $distr_fh, "<", $distr_file;
while (<$distr_fh>) {
    chomp $_;
    next if ($_ =~ /-----/);
    next if ($_ =~ /TOTAL/);
    my ($rel, $cum, $cumc, $abs, $label) = split /\s+/, $_;
    $losses{$label} = $rel;
}
close $distr_fh;

while (<STDIN>) {
    chomp $_;
    if ($_ =~ /^(\d+):(\d)/) {
        my $new_loss = $losses{$1};
        if (!$2) {
            $new_loss = $new_loss-100;
        }
        else {
            $new_loss = 1;
        }
        $_ =~ s/^(\d+):(\d)/$1:$new_loss/;
    }
    print $_."\n";
}
