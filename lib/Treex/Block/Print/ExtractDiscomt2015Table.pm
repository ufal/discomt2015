package Treex::Block::Print::ExtractDiscomt2015Table;
use Moose;
use Treex::Core::Common;
use utf8;

use List::Util qw/sum/;
use Treex::Tool::ML::VowpalWabbit::Util;
use Treex::Tool::Python::RunFunc;
use Treex::Tool::Context::Sentences;

extends 'Treex::Block::Write::BaseTextWriter';

has 'src_language' => (is => 'ro', isa => 'Treex::Type::LangCode', required => 1);
has 'weighted_examples' => (is => 'ro', isa => 'Bool', default => 0);

has '_scores_from_kenlm' => (is => 'rw', isa => 'HashRef');

has '_python' => (is => 'ro', isa => 'Treex::Tool::Python::RunFunc', builder => '_build_python', lazy => 1);

has '_classes_losses' => (is => 'ro', isa => 'HashRef[HashRef[HashRef[Num]]]', builder => '_build_classes_losses');

sub BUILD {
    my ($self) = @_;
    $self->_python;
}

sub _build_classes_losses {
    my ($self) = @_;
    my $classes_losses = {
        en => {
            de => {
                'er' => 1,
                'sie' => 1,
                'es' => 1,
                'man' => 1,
                'OTHER' => 1,
            },
            fr => {
                'ce' => 0.089,
                'elle' => 0.087,
                'elles' => 0.032,
                'il' => 0.277,
                'ils' => 0.085,
                'cela' => 0.023,
                'on' => 0.017,
                'OTHER' => 0.390,
            },
        },
        de => {
            en => {
                'he' => 1,
                'she' => 1,
                'it' => 1,
                'they' => 1,
                'you' => 1,
                'this' => 1,
                'these' => 1,
                'there' => 1,
                'OTHER' => 1,
            },
        },
        fr => {
            en => {
                'he' => 1,
                'she' => 1,
                'it' => 1,
                'they' => 1,
                'this' => 1,
                'these' => 1,
                'there' => 1,
                'OTHER' => 1,
            },
        },
    };
    return $classes_losses;
}

my @SRC_NODES_COUNT_BINS = (0, 1);
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
    my ($self) = @_;
    my $python = Treex::Tool::Python::RunFunc->new();
    my $python_lib_dir = $ENV{WMT16PRON_ROOT}.'/lib';
    my $code = <<CODE;
import sys
reload(sys)
sys.setdefaultencoding('utf8')
sys.path.append('$python_lib_dir')
CODE
    my $res = $python->command($code);
    print STDERR $res . "\n";
    my $kenlm_path = $ENV{WMT16PRON_ROOT}.'/baseline/mono+para.5.'.$self->language.'.lemma.trie.kenlm';
    my $conf_path = $ENV{WMT16PRON_ROOT}.'/baseline/'.$self->src_language.'-'.$self->language.'.yml';
    $code = <<CODE;
import discomt_baseline as db
model = db.KenLM('$kenlm_path', '$conf_path')
CODE
    $python->command($code);
    return $python;
}

sub get_losses {
    my ($self, $class) = @_;

    my $classes_losses = $self->_classes_losses->{$self->src_language}{$self->language};
    
    my @losses;
    if ($self->weighted_examples) {
        my $losses_sum = sum values %$classes_losses;
        @losses = map {($_ eq $class) ? 1 - ($classes_losses->{$_} / $losses_sum) : 1} sort keys %$classes_losses;
    }
    else {
        @losses = map {($_ eq $class) ? 0 : 1} sort keys %$classes_losses;
    }
    
    return \@losses;
}

sub get_shared_feats {
    my ($self, $trg_anode) = @_;

    my ($src_anodes, $ali_types) = $trg_anode->get_undirected_aligned_nodes({language => $self->src_language});
    my $src_main_anode = $self->get_main_src_node($trg_anode);

    my @feats = ();

    push @feats, $self->get_src_feats($src_main_anode, $src_anodes);
    push @feats, $self->get_trg_feats($trg_anode);
    push @feats, $self->get_trg_feats_over_src_nodes($src_main_anode);
    push @feats, $self->combine_feats(\@feats);

   
    # prepend a namespace
    unshift @feats, ["|s", undef];
    return \@feats;
}

sub get_class_feats {
    my ($self) = @_;
    my $classes_losses = $self->_classes_losses->{$self->src_language}{$self->language};

    my @class_feats = map {[["|t", undef], ["trg_class", $_]]} sort keys %$classes_losses;
    return \@class_feats;
}

sub get_main_src_node {
    my ($self, $trg_anode) = @_;
    my ($replace, $ord) = split /_/, $trg_anode->form;
    my $bundle = $trg_anode->get_bundle;
    my $src_atree = $bundle->get_tree($self->src_language, 'a', $self->selector);
    my @src_anodes = $src_atree->get_descendants({ordered => 1});
    return $src_anodes[$ord];
}


###################### SOURCE LANGUAGE FEATURES ###################################################

# FEAT: src_anodes_aligned_count=*
sub get_src_feats {
    my ($self, $src_main_anode, $src_anodes) = @_;

    my @src_feats = ();

    push @src_feats, ['src_anodes_aligned_count', binning(scalar(@$src_anodes),@SRC_NODES_COUNT_BINS)];
    push @src_feats, $self->get_morpho_feats([$src_main_anode], 1);
    push @src_feats, $self->get_morpho_feats($src_anodes);
    push @src_feats, $self->get_synt_feats($src_main_anode);
    if ($self->src_language eq 'en') {
        push @src_feats, $self->get_nada_feats($src_main_anode);
    }

    return @src_feats;
}

# FEAT: [en|fr|de]_[main_|]lemma=*
sub get_morpho_feats {
    my ($self, $anodes, $is_main) = @_;
    return map {['src_'.($is_main ? 'main_' : '').'lemma', $_->lemma]} @$anodes;
}

sub get_afun {
    my ($anode) = @_;
    return $anode->afun // $anode->get_attr("conll/deprel") // "undef";
}

sub get_synt_feats {
    my ($self, $src_anode) = @_;
    my $par = $src_anode->get_parent;
    return if (!defined $par || $par->is_root());

    my @feats = ();
    push @feats, [ 'src_par_lemma', $par->lemma ];
    push @feats, [ 'src_afun', get_afun($src_anode) ];
    push @feats, [ 'src_par_lemma_self_afun', $par->lemma .'_'. get_afun($src_anode) ];
    push @feats, [ 'src_par_lemma_self_afun_lemma', $par->lemma .'_'. get_afun($src_anode) . '_' . $src_anode->lemma ];

    my ($src_tnode) = $src_anode->get_referencing_nodes('a/lex.rf');
    return @feats if (!defined $src_tnode);

    push @feats, [ 'src_fun', $src_tnode->functor ];
    my $src_tpar = $src_tnode->get_parent();
    return @feats if (!defined $src_tpar || $src_tpar->is_root());

    push @feats, [ 'src_par_tlemma_self_fun', $src_tpar->t_lemma . '_'. $src_tnode->functor ];
    push @feats, [ 'src_par_tlemma_self_fun_tlemma', $src_tpar->t_lemma . '_'. $src_tnode->functor . '_' . $src_tnode->t_lemma ];
    push @feats, [ 'src_par_tlemma_self_fun_lemma', $src_tpar->t_lemma . '_'. $src_tnode->functor . '_' . $src_anode->lemma ];

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

sub get_src_a_antes {
    my ($self, $src_anode) = @_;

    my ($src_tnode) = $src_anode->get_referencing_nodes('a/lex.rf');
    return if (!defined $src_tnode);

    my (@src_t_antes) = $src_tnode->get_coref_chain();
    my @src_a_antes = grep {defined $_} map {$_->get_lex_anode} @src_t_antes;
    return @src_a_antes;
}


###################### TARGET LANGUAGE FEATURES ###################################################

sub get_trg_feats {
    my ($self, $trg_anode) = @_;
    
    my @trg_feats = ();

    push @trg_feats, $self->kenlm_probs($trg_anode);
    push @trg_feats, $self->ngram_feats($trg_anode);
    return @trg_feats;
}
#-------------------- KENLM features ------------------------------------------------

# FEAT: kenlm_w_prob=*
# FEAT: kenlm_w_rank=*
sub kenlm_probs {
    my ($self, $trg_anode) = @_;
    my $form = $trg_anode->form;

    my $scores = $self->_scores_from_kenlm->{$form};
    my @feats = map {['kenlm_w_prob', $_->[0].'_'.binning($_->[1], @KENLM_PROB_BINS)]} @$scores;
    push @feats, map {['kenlm_w_rank', $scores->[$_][0].'_'.binning($_+1, @KENLM_RANK_BINS)]} 0 .. $#$scores;
    push @feats, map {['kenlm_w_rank_3', $scores->[$_][0].'_'.binning($_+1, @KENLM_RANK_3_BINS)]} 0 .. $#$scores;
    push @feats, map {['kenlm_w_rank_5', $scores->[$_][0].'_'.binning($_+1, @KENLM_RANK_5_BINS)]} 0 .. $#$scores;
    return @feats;
}

#--------------------------- ngram features ----------------------------------------

sub ngram_feats {
    my ($self, $trg_anode) = @_;

    my @before_nodes = $trg_anode->get_siblings({preceding_only => 1});
    my @after_nodes = $trg_anode->get_siblings({following_only => 1});
    
    my @feats = ();
    my (@bn, @an, @sn);

    @bn = $before_nodes[-1];
    @an = $after_nodes[0];
    @sn = (@bn, @an);
    push @feats, map {['trg_verb_prev_1', $_->lemma]} grep {defined $_->tag && $_->tag =~ /^VER/} grep {defined $_} @bn;
    push @feats, map {['trg_verb_foll_1', $_->lemma]} grep {defined $_->tag && $_->tag =~ /^VER/} grep {defined $_} @an;
    push @feats, map {['trg_verb_surr_1', $_->lemma]} grep {defined $_->tag && $_->tag =~ /^VER/} grep {defined $_} @sn;
    @bn = @before_nodes[-3 .. -1];
    @an = @after_nodes[0 .. 2];
    @sn = (@bn, @an);
    push @feats, map {['trg_verb_prev_3', $_->lemma]} grep {defined $_->tag && $_->tag =~ /^VER/} grep {defined $_} @bn;
    push @feats, map {['trg_verb_foll_3', $_->lemma]} grep {defined $_->tag && $_->tag =~ /^VER/} grep {defined $_} @an;
    push @feats, map {['trg_verb_surr_3', $_->lemma]} grep {defined $_->tag && $_->tag =~ /^VER/} grep {defined $_} @sn;
    @bn = @before_nodes[-5 .. -1];
    @an = @after_nodes[0 .. 4];
    @sn = (@bn, @an);
    push @feats, map {['trg_verb_prev_5', $_->lemma]} grep {defined $_->tag && $_->tag =~ /^VER/} grep {defined $_} @bn;
    push @feats, map {['trg_verb_foll_5', $_->lemma]} grep {defined $_->tag && $_->tag =~ /^VER/} grep {defined $_} @an;
    push @feats, map {['trg_verb_surr_5', $_->lemma]} grep {defined $_->tag && $_->tag =~ /^VER/} grep {defined $_} @sn;

    return @feats;
}

##################### FEATURES OVER ENGLISH NODES ################################

sub get_trg_feats_over_src_nodes {
    my ($self, $src_anode) = @_;

    my @feats = ();
    push @feats, $self->get_trg_feats_over_src_antes($src_anode);
    push @feats, $self->get_trg_feats_over_src_prev_sb($src_anode);
    push @feats, $self->get_trg_feats_over_src_par($src_anode);
    return @feats;
}

sub is_mention_in_lang {
    my ($anode, $lang) = @_;
    return 0 if (!defined $anode->tag);
    if ($lang eq "fr") {
        return $anode->tag =~ /^NOM$/;
    }
    else {
        return $anode->tag =~ /^(NOUN|PRON)$/;
    }
}

# FEAT: trg_n_antes_over_src_count=*
# FEAT: trg_closest_ante_over_src_mfeats=*
# FEAT: trg_closest_ante_over_src_gender=*
# FEAT: trg_closest_ante_over_src_number=*
# FEAT: trg_closest_ante_over_src_gender_number=*
sub get_trg_feats_over_src_antes {
    my ($self, $src_anode) = @_;

    my @trg_noun_antes;
    my @src_a_antes = $self->get_src_a_antes($src_anode);
    if (@src_a_antes) {
        my @trg_antes = map {my ($ali_nodes) = $_->get_undirected_aligned_nodes({language => $self->language}); @$ali_nodes} @src_a_antes;
        # select only target language nouns
        #foreach (@trg_antes) {
        #    if (!defined $_->) {
        #        print STDERR $_->tag . "\n";
        #    }
        #}
        @trg_noun_antes = grep {is_mention_in_lang($_, $self->language)} grep {defined $_} @trg_antes;
    }

    return (["trg_n_antes_over_src_count", 0]) if (!@trg_noun_antes);

    my $trg_closest_ante = $trg_noun_antes[0];

    my @feats = ();

    push @feats, ["trg_closest_ante_over_src_gender", $trg_closest_ante->wild->{gender} // "undef"];
    #my $mfeats = $trg_closest_ante->wild->{mfeats};
    #push @feats, ["trg_closest_ante_over_src_mfeats", $mfeats];
    #my @split_mfeats = split /\|/, $mfeats;
    #my ($gender) = map {$_ =~ s/^g=//; $_} grep {$_ =~ /^g=/} @split_mfeats;
    #my ($number) = map {$_ =~ s/^n=//; $_} grep {$_ =~ /^n=/} @split_mfeats;
    #$gender = $gender // "undef";
    #$number = $number // "undef";
    #push @feats, ["trg_closest_ante_over_src_number", $number];
    #push @feats, ["trg_closest_ante_over_src_gender_number", $gender.$number];

    return @feats;
}

sub get_trg_feats_over_src_prev_sb {
    my ($self, $src_anode) = @_;

    my @feats = ();

    my $context_selector = Treex::Tool::Context::Sentences->new();
    my @src_cands = reverse $context_selector->nodes_in_surroundings($src_anode, -2, 0, {preceding_only => 1});
    
    @src_cands = grep {lc(get_afun($_)) eq "sb"} @src_cands;
    my @trg_genders = map {
        my $src_node = $_;
        my ($trg_nodes) = $src_node->get_undirected_aligned_nodes({language => $self->language});
        # only nouns are accepted - pronouns keep no gender information since they are lemmatized
        my ($gender) = map {$_->wild->{gender}} grep {defined $_->tag && $_->tag =~ /^NO/ && defined $_->wild->{gender}} @$trg_nodes;
        if (!defined $gender) {
            my ($src_pnom) = grep {lc(get_afun($_)) eq "pnom"} $src_node->get_siblings;
            if (defined $src_pnom) {
                ($trg_nodes) = $src_pnom->get_undirected_aligned_nodes({language => $self->language});
                ($gender) = map {$_->wild->{gender}} grep {defined $_->tag && $_->tag =~ /^NO/ && defined $_->wild->{gender}} @$trg_nodes;
            }
        }
        $gender;
    } @src_cands;
    my ($first_def_gender) = grep {defined $_} @trg_genders;
    push @feats, ['trg_gender_over_src_prev_sb', $first_def_gender // "undef"];

    # remove a subject which is a grandpa of src_anode, e.g. in the sentence "The fact that it collapsed is clear."
    my @granpa_idxs = grep {
        my $par = $src_anode->get_parent;
        if (defined $par) {
            my $granpa = $par->get_parent;
            $granpa != $src_cands[$_];
        }
        else {
            1;
        }
    } 0 .. $#src_cands;
    ($first_def_gender) = grep {defined $_} map {$trg_genders[$_]} @granpa_idxs;
    push @feats, ['trg_gender_over_src_prev_sb_no_granpa', $first_def_gender // "undef"];

    return @feats;
}

# FEAT: trg_par_over_src_lemma=*
sub get_trg_feats_over_src_par {
    my ($self, $src_anode) = @_;
    my $src_par = $src_anode->get_parent();
    return if (!defined $src_par);
    my ($trg_pars) = $src_par->get_undirected_aligned_nodes({language => $self->language});
    
    my @feats;

    my @lemmas = map {$_->lemma} @$trg_pars;
    my @tags = map {$_->tag} @$trg_pars;
    push @feats, map {['trg_par_over_src_lemma', $_ =~ /^REPLACE/i ? "replace" : $_]} @lemmas;
    push @feats, map {['trg_par_over_src_tag', $_]} @tags;

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
    my $sent = join " ", map {$_->lemma} $zone->get_atree->get_descendants({ordered => 1});
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
    my ($self, $trg_anode) = @_;

    my $class = $trg_anode->wild->{class};

    return if (!defined $class);

    my $class_feats = $self->get_class_feats();
    my $shared_feats = $self->get_shared_feats($trg_anode);
    my $feats = [ $class_feats, $shared_feats ];
    my $losses = $self->get_losses($class);
    my $src_sent = $trg_anode->get_bundle->get_zone($self->src_language, $self->selector)->sentence;
    $src_sent =~ s/\t/ /g;
    my $comments = [[], $trg_anode->get_address() . " " . $src_sent ];

    my $instance_str = Treex::Tool::ML::VowpalWabbit::Util::format_multiline($feats, $losses, $comments);
    print {$self->_file_handle} $instance_str;
}

1;
