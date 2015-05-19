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

my %CLASSES_LOSSES = (
'OTHER' => 0.390,
'il' => 0.277,
'ce' => 0.089,
'elle' => 0.087,
'ils' => 0.085,
'elles' => 0.032,
'cela' => 0.023,
'on' => 0.017,
'ça' => 0.001,
);

my @EN_NODES_COUNT_BINS = (0, 1);
my @KENLM_PROB_BINS = (0.001, 0.01, 0.1, 0.3, 0.5, 0.7, 0.9, 1);
my @KENLM_RANK_BINS = (1, 2, 3, 5, 10, 20);
my @KENLM_RANK_3_BINS = (3);
my @KENLM_RANK_5_BINS = (5);
my @NADA_PROB_BINS = @KENLM_PROB_BINS;

sub binning {
    my ($value, @bins) = @_;
    my $idx = scalar(grep {$_ < $value} @bins);
    return "Inf" if ($idx == scalar @bins);
    return $bins[$idx];
}

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

sub get_losses {
    my ($self, $class) = @_;

    my @losses = map {$_ eq $class ? $CLASSES_LOSSES{$_} : 1} keys %CLASSES_LOSSES;
    return \@losses;
}

sub get_shared_feats {
    my ($self, $fr_anode) = @_;

    my ($en_anodes, $ali_types) = Treex::Tool::Align::Utils::get_aligned_nodes_by_filter($fr_anode, {language => 'en'});
    my $en_main_anode = $self->get_main_en_node($fr_anode);

    my @feats = ();

    push @feats, $self->get_en_feats($en_main_anode, $en_anodes);
    push @feats, $self->get_fr_feats($fr_anode);
    push @feats, $self->get_fr_feats_over_en_nodes($en_main_anode);
    push @feats, $self->combine_feats(\@feats);

    my $feat_str = join " ", map {$_->[0] . "=" . $_->[1]} @feats;
   
    # return with a namespace
    return "s $feat_str";
}

sub get_class_feats {
    my ($self) = @_;

    my @class_feats = map {"t trg_class=$_"} %CLASSES_LOSSES;
    return \@class_feats;
}

sub get_main_en_node {
    my ($self, $fr_anode) = @_;
    my ($replace, $ord) = split /_/, $fr_anode->form;
    my $bundle = $fr_anode->get_bundle;
    my $en_atree = $bundle->get_tree('en', 'a', $self->selector);
    my @en_anodes = $en_atree->get_descendants({ordered => 1});
    return $en_anodes[$ord];
}


###################### ENGLISH FEATURES ###################################################

# FEAT: en_anodes_aligned_count=*
sub get_en_feats {
    my ($self, $en_main_anode, $en_anodes) = @_;

    my @en_feats = ();

    push @en_feats, ['en_anodes_aligned_count', binning(scalar(@$en_anodes),@EN_NODES_COUNT_BINS)];
    push @en_feats, $self->get_morpho_feats([$en_main_anode], 'en', 1);
    push @en_feats, $self->get_morpho_feats($en_anodes, 'en');
    push @en_feats, $self->get_synt_feats($en_main_anode);
    push @en_feats, $self->get_nada_feats($en_main_anode);

    return @en_feats;
}

# FEAT: [en|fr]_lemma=*
sub get_morpho_feats {
    my ($self, $anodes, $lang, $is_main) = @_;
    return map {[$lang.'_'.($is_main ? 'main_' : '').'lemma', $_->lemma]} @$anodes;
}

sub get_synt_feats {
    my ($self, $en_anode) = @_;
    my $par = $en_anode->get_parent;
    return if (!defined $par || $par->is_root());

    my @feats = ();
    push @feats, [ 'en_par_lemma', $par->lemma ];
    push @feats, [ 'en_afun', $en_anode->afun ];
    push @feats, [ 'en_par_lemma_self_afun', $par->lemma .'_'. $en_anode->afun ];
    push @feats, [ 'en_par_lemma_self_afun_lemma', $par->lemma .'_'. $en_anode->afun . '_' . $en_anode->lemma ];

    my ($en_tnode) = $en_anode->get_referencing_nodes('a/lex.rf');
    return @feats if (!defined $en_tnode);

    push @feats, [ 'en_fun', $en_tnode->functor ];
    my $en_tpar = $en_tnode->get_parent();
    return @feats if (!defined $en_tpar || $en_tpar->is_root());

    push @feats, [ 'en_par_tlemma_self_fun', $en_tpar->t_lemma . '_'. $en_tnode->functor ];
    push @feats, [ 'en_par_tlemma_self_fun_tlemma', $en_tpar->t_lemma . '_'. $en_tnode->functor . '_' . $en_tnode->t_lemma ];
    push @feats, [ 'en_par_tlemma_self_fun_lemma', $en_tpar->t_lemma . '_'. $en_tnode->functor . '_' . $en_anode->lemma ];

    return @feats;
}

# FEAT: en_nada_refer=*
# FEAT: en_nada_refer_prob=*
sub get_nada_feats {
    my ($self, $en_anode) = @_;

    my ($en_tnode) = $en_anode->get_referencing_nodes('a/lex.rf');
    return if (!defined $en_tnode);

    my $is_refer = $en_tnode->wild->{'referential.nada_0.5'};
    my $is_refer_prob = $en_tnode->wild->{'referential_prob'};

    return if (!defined $is_refer || !defined $is_refer_prob);

    my @feats = ();
    push @feats, ['en_nada_refer', $is_refer];
    push @feats, ['en_nada_refer_prob', binning($is_refer_prob, @NADA_PROB_BINS)];

    return @feats;
}

#-------------------- COREFERENCE features -----------------------------------------

sub get_en_a_antes {
    my ($self, $en_anode) = @_;

    my ($en_tnode) = $en_anode->get_referencing_nodes('a/lex.rf');
    return if (!defined $en_tnode);

    my (@en_t_antes) = $en_tnode->get_coref_chain();
    my @en_a_antes = grep {defined $_} map {$_->get_lex_anode} @en_t_antes;
    return @en_a_antes;
}


###################### FRENCH FEATURES ###################################################

sub get_fr_feats {
    my ($self, $fr_anode) = @_;
    
    my @fr_feats = ();

    push @fr_feats, $self->kenlm_probs($fr_anode);
    return @fr_feats;
}
#-------------------- KENLM features ------------------------------------------------

# FEAT: kenlm_w_prob=*
# FEAT: kenlm_w_rank=*
sub kenlm_probs {
    my ($self, $fr_anode) = @_;
    my $form = $fr_anode->form;

    my $scores = $self->_scores_from_kenlm->{$form};
    my @feats = map {['kenlm_w_prob', $_->[0].'_'.binning($_->[1], @KENLM_PROB_BINS)]} @$scores;
    push @feats, map {['kenlm_w_rank', $scores->[$_][0].'_'.binning($_+1, @KENLM_RANK_BINS)]} 0 .. $#$scores;
    push @feats, map {['kenlm_w_rank_3', $scores->[$_][0].'_'.binning($_+1, @KENLM_RANK_3_BINS)]} 0 .. $#$scores;
    push @feats, map {['kenlm_w_rank_5', $scores->[$_][0].'_'.binning($_+1, @KENLM_RANK_5_BINS)]} 0 .. $#$scores;
    return @feats;
}

##################### FEATURES OVER ENGLISH NODES ################################

sub get_fr_feats_over_en_nodes {
    my ($self, $en_anode) = @_;

    my @feats = ();
    push @feats, $self->get_fr_feats_over_en_antes($en_anode);
    push @feats, $self->get_fr_feats_over_en_par($en_anode);
    return @feats;
}

# FEAT: fr_n_antes_over_en_count=*
# FEAT: fr_closest_ante_over_en_mfeats=*
# FEAT: fr_closest_ante_over_en_gender=*
# FEAT: fr_closest_ante_over_en_number=*
# FEAT: fr_closest_ante_over_en_gender_number=*
sub get_fr_feats_over_en_antes {
    my ($self, $en_anode) = @_;

    my @fr_noun_antes;
    my @en_a_antes = $self->get_en_a_antes($en_anode);
    if (@en_a_antes) {
        my @fr_antes = Treex::Tool::Align::Utils::aligned_transitively(\@en_a_antes, [{language => 'fr'}]);
        # select only French nouns
        foreach (@fr_antes) {
            if (!defined $_->conll_cpos) {
                print STDERR $_->tag . "\n";
            }
        }
        @fr_noun_antes = grep {($_->conll_cpos // "") eq "N"} grep {defined $_} @fr_antes;
    }

    return (["fr_n_antes_over_en_count", 0]) if (!@fr_noun_antes);

    my $fr_closest_ante = $fr_noun_antes[0];

    my @feats = ();

    my $mfeats = $fr_closest_ante->wild->{mfeats};
    push @feats, ["fr_closest_ante_over_en_mfeats", $mfeats];
    my @split_mfeats = split /\|/, $mfeats;
    my ($gender) = map {$_ =~ s/^g=//; $_} grep {$_ =~ /^g=/} @split_mfeats;
    my ($number) = map {$_ =~ s/^n=//; $_} grep {$_ =~ /^n=/} @split_mfeats;
    $gender = $gender // "undef";
    $number = $number // "undef";
    push @feats, ["fr_closest_ante_over_en_gender", $gender];
    push @feats, ["fr_closest_ante_over_en_number", $number];
    push @feats, ["fr_closest_ante_over_en_gender_number", $gender.$number];

    return @feats;
}

# FEAT: fr_par_over_en_lemma=*
sub get_fr_feats_over_en_par {
    my ($self, $en_anode) = @_;
    my $en_par = $en_anode->get_parent();
    return if (!defined $en_par);
    my @fr_pars = Treex::Tool::Align::Utils::aligned_transitively([$en_par], [{language => 'fr'}]);
    
    my @feats;

    my @lemmas = map {$_->lemma} @fr_pars;
    my @cposs = map {$_->conll_cpos} @fr_pars;
    push @feats, map {['fr_par_over_en_lemma', $_ =~ /^REPLACE/i ? "replace" : $_]} @lemmas;
    push @feats, map {['fr_par_over_en_cpos', $_]} @cposs;

    return @feats;
}

##################### COMBINED FEATURES ################################

sub combine_feats {
    my ($self, $feats_array) = @_;

    my $feats_hash = _feats_array_to_hash($feats_array);

    my @feats = ();
    push @feats, $self->combine_kenlm_nada($feats_hash);
    return @feats;
}

sub combine_kenlm_nada {
    my ($feats_hash) = @_;

    # take words ranked at 1-3 position
    my @kenlm_first_three = grep {$_ =~ /^4/} @{$feats_hash->{kenlm_w_rank_3}};
    my $nada_ref = $feats_hash->{en_nada_refer} // [ 'undef' ];

    return map {['comb_nada_kenlm_rank_3', $nada_ref->[0] . "_" . $_]} @kenlm_first_three;
}

sub _feats_array_to_hash {
    my ($feats_array) = @_;
    my %feat_hash = ();
    foreach my $feat (@$feats_array) {
        my $val = $feat_hash{$feat->[0]};
        if (defined $val) {
            push @$val, $feat->[1];
        }
        else {
            $feat_hash{$feat->[0]} = [ $feat->[1] ];
        }
    }
    return \%feat_hash;
}

before 'process_zone' => sub {
    my ($self, $zone) = @_;
    my $sent = $zone->sentence();
    $sent =~ s/\\/\\\\/g;
    $sent =~ s/"/\\"/g;
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
    my $en_sent = $fr_anode->get_bundle->get_zone('en',$self->selector)->sentence;
    $en_sent =~ s/\t/ /g;
    my $comments = [[], $fr_anode->get_address() . " " . $en_sent ];

    my $instance_str = Treex::Tool::ML::VowpalWabbit::Util::format_multiline($feats, $losses, $comments);
    print {$self->_file_handle} $instance_str;
}

1;
