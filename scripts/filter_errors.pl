#!/usr/bin/env perl

use warnings;
use strict;

use Getopt::Long;
use Treex::Tool::ML::VowpalWabbit::Util;
use List::Util qw/min/;
use Data::Dumper;

while ( my ($feats, $losses, $tags, $comments) = Treex::Tool::ML::VowpalWabbit::Util::parse_multiline(*STDIN) ) {
    my ($tag) = @{$tags->[0]};
    next if (!defined $tag);
    my ($true_idx) = split /-/, $tag;
    my $min_loss = min @$losses;
    my ($pred_idx) = grep {$losses->[$_] == $min_loss} 0..$#$losses;
    if ($pred_idx != ($true_idx-1)) {
        print Treex::Tool::ML::VowpalWabbit::Util::format_multiline($feats, $losses, $comments, $tags);
    }
}
