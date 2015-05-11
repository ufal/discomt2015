package Treex::Block::Print::ExtractDiscomt2015Table;
use Moose;
use Treex::Core::Common;
use utf8;

use Treex::Tool::ML::VowpalWabbit::Util;
use Treex::Tool::Align::Utils;
use Treex::Tool::Python::RunFunc;

extends 'Treex::Block::Write::BaseTextWriter';


has '_scores_from_kenlm' => (is => 'rw', isa => 'HashRef');

has '_python' => (is => 'ro', isa => 'Treex::Tool::Python::RunFunc', builder => '_build_python');

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

my @KENLM_PROB_BINS = (0.001, 0.01, 0.1, 0.3, 0.5, 0.7, 0.9, 1);

sub _build_python {
    my $python = Treex::Tool::Python::RunFunc->new();
    my $python_lib_dir = $ENV{DISCOMT2015_ROOT}.'/lib';
    my $code = <<CODE;
import sys
reload(sys)
sys.setdefaultencoding('utf8')
sys.path.append('$python_lib_dir')
CODE
    my $res = $python->command($code);
    print STDERR $res . "\n";
    my $kenlm_path = $ENV{DISCOMT2015_ROOT}.'/data/corpus.5.fr.trie.kenlm';
    $code = <<CODE;
import discomt_baseline as db
model = db.KenLM('$kenlm_path')
CODE
    $python->command($code);
    return $python;
}

sub get_shared_feats {
    my ($self, $fr_anode) = @_;

    my ($en_nodes, $ali_types) = Treex::Tool::Align::Utils::get_aligned_nodes_by_filter($fr_anode, {language => 'en', selector => 'src'});
    my $en_node = shift @$en_nodes;

    my $feats = [];
    push @$feats, "lemma=".$en_node->lemma;
    push @$feats, $self->kenlm_probs($fr_anode);
    
    return $feats;
}

sub get_class_feats {
    my ($self) = @_;

    my @class_feats = map {["trg_class=$_"]} @CLASSES;
    return \@class_feats;
}

sub get_losses {
    my ($self, $class) = @_;

    my @losses = map {$_ eq $class ? 0 : 1} @CLASSES;
    return \@losses;
}

sub kenlm_probs {
    my ($self, $fr_anode) = @_;
    my $form = $fr_anode->form;

    my $scores = $self->_scores_from_kenlm->{$form};
    my @feats = map {['kenlm_'.$_->[0], kenlm_binning($_->[1])]} @$scores;
    return @feats;
}

sub kenlm_binning {
    my ($value) = @_;
    my $idx = scalar(grep {$_ < $value} @KENLM_PROB_BINS);
    return $KENLM_PROB_BINS[$idx];
}

before 'process_zone' => sub {
    my ($self, $zone) = @_;
    my $sent = $zone->sentence();
    $sent =~ s/\"/\\\"/g;
    my $result = $self->_python->command('sent = "'. $sent . '"'."\nmodel.score_sentence(sent)");
    if ($result) {
        my $all_scores = {};
        foreach my $line (split /\n/, $result) {
            my ($label, @words) = split /\t/, $line;
            my @word_scores = map {[split / /, $_]} @words;
            $all_scores->{$label} = \@word_scores;
        }
        $self->_set_scores_from_kenlm($all_scores);
    }
};

sub process_anode {
    my ($self, $fr_anode) = @_;

    my $class = $fr_anode->wild->{class};

    return if (!defined $class);

    my $class_feats = $self->get_class_feats();
    my $shared_feats = $self->get_shared_feats($fr_anode);
    my $feats = [ $class_feats, $shared_feats ];
    my $losses = $self->get_losses($class);

    my $instance_str = Treex::Tool::ML::VowpalWabbit::Util::format_multiline($feats, $losses);
    print {$self->_file_handle} $instance_str;
}

1;
