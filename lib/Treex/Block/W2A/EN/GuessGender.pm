package Treex::Block::W2A::EN::GuessGender;

use Moose;
use Treex::Core::Common;
use Treex::Core::Resource qw/require_file_from_share/;

use List::Util qw/sum/;

extends 'Treex::Core::Block';

has 'gennums_path' => ( is => 'ro', isa => 'Str', default => 'data/models/grammateme_transfer/_2en/en_gennum.freqs.gz' );
has '_gennums' => ( is => 'ro', isa => 'HashRef[ArrayRef[Int]]', builder => '_build_gennums', lazy => 1 );

sub _build_gennums {
    my ($self) = @_;

    my $gennum_hash = {};

    my $path = require_file_from_share($self->gennums_path);

    log_info "Loading the list of English genders and numbers from $path";
    open my $fh, "<:gzip:utf8", $path;
    while (my $line = <$fh>) {
        chomp $line;
        my ($word, $freq_str) = split /\t/, $line;
        my @gennums = split / /, $freq_str;
        #print STDERR Dumper($word, \@gennums);
        # skip prefix and suffix patterns
        next if ($word =~ /^!/ || $word =~ /!$/);
        $gennum_hash->{$word} = \@gennums;
    }
    close $fh;
    
    return $gennum_hash;
}

sub process_start {
    my ($self) = @_;
    $self->_gennums;
}

sub process_anode {
    my ($self, $anode) = @_;

    return if (!defined $anode->tag || $anode->tag ne "NOUN");

    my $gender = 'masc';
    
    my $lemma = lc($anode->lemma);
    # replace numbers with # to be able to be found in the hash
    $lemma =~ s/\d/#/g;
    
    my $gennum = $self->_gennums->{$lemma};
    
    return if (!defined $gennum);
        
    # if neutrum is more than 1/3 out of all singular, set neutrum
    my $sum = sum @{$gennum}[0 .. 2];
    if (!$sum) {
        log_warn "No singular number found in the list for lemma '$lemma'";
        return;
    }
    my $neut_ratio = $gennum->[2] / $sum;
    if ($neut_ratio > 1/3) {
        $gender = 'neut';
    }
    else {
        $gender = $gennum->[0] > $gennum->[1] ? 'masc' : 'fem';
    }
    $anode->wild->{gender} = $gender;
}

1;
