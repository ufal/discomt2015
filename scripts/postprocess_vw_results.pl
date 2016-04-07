#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;

my $OTHER_THRESHOLD = 0;

sub adjust_instance {
    my ($instance) = @_;
    return if !$instance;

    my @scores = map {$instance->{$_}->[0]} sort keys %$instance;
    my ($min, $second_min, @rest) = sort {$a <=> $b} @scores;
    my ($min_idx) = grep {$scores[$_] == $min} 0 .. $#scores;

    if ($min_idx == 0 && $min > $OTHER_THRESHOLD) {
        my ($second_min_idx) = grep {$scores[$_] == $second_min} 0 .. $#scores;
        $instance->{$min_idx+1}->[0] = $second_min;
        $instance->{$second_min_idx+1}->[0] = $min;
    }
    return $instance;
}

sub print_instance {
    my ($instance) = @_;

    foreach my $key (sort keys %$instance) {
        my $value = $instance->{$key};
        print $key . ":" . $value->[0] . " " . $value->[1] . "\n";
    }
    print "\n";
}

my $instance = {};
while (my $line = <STDIN>) {
    chomp $line;
    if ($line =~ /^\s*$/) {
        $instance = adjust_instance($instance);
        print_instance($instance);
        $instance = {};
        next;
    }
    my ($idx, $score, $tag) = split /[: ]/, $line;
    $instance->{$idx} = [$score, $tag];
}
