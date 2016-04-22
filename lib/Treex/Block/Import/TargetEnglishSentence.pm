package Treex::Block::Import::TargetEnglishSentence;
use Moose;
use Treex::Core::Common;
extends 'Treex::Core::Block';

has 'from_dir' => (is => 'ro', isa => 'Str', required => 1);
has 'src_language' => (is => 'ro', isa => 'Treex::Type::LangCode', required => 1);

sub process_document {
    my ($self, $doc) = @_;
    my $doc_name = $doc->file_stem;

    my $input_file = $self->from_dir . "/" . $doc_name . ".txt";
    return if (! -f $input_file);

    open my $input_fh, "<:utf8", $input_file;

    my @bundles = $doc->get_bundles;
    while (my $line = <$input_fh>) {
        chomp $line;
        my ($class, $missing_word, $src_sent, $trg_sent, $align) = split /\t/, $line;

        my $bundle = shift @bundles;
        my $zone = $bundle->create_zone($self->language, $self->selector);
        $zone->set_sentence($trg_sent);
        my $trg_atree = $zone->create_atree();
        my @tokens = split / /, $trg_sent;
        my $i = 0;
        foreach my $token (@tokens) {
            my ($lemma, $tag) = split /\|/, $token;
            my $child = $trg_atree->create_child({
                form           => $lemma,
                ord            => $i + 1,
                lemma          => $lemma,
                tag            => $tag,
            });
            $i++;
        }
        my $src_atree = $bundle->get_tree($self->src_language, 'a', $self->selector);
        $self->_add_aligns([$src_atree, $trg_atree], $align);
        
        my @classes = split / /, $class;
        my @miss_words = split / /, $missing_word;
        my @replace_nodes = grep {$_->form =~ /^REPLACE_/} $trg_atree->get_descendants({ordered => 1});
        for (my $i = 0; $i < @replace_nodes; $i++) {
            $replace_nodes[$i]->wild->{class} = $classes[$i];
            $replace_nodes[$i]->wild->{miss_word} = $miss_words[$i];
        }
    }
    close $input_fh;
}

sub _add_aligns {
    my ($self, $atrees, $align) = @_;

    my @lang1_nodes = $atrees->[0]->get_descendants({ordered => 1});
    my @lang2_nodes = $atrees->[1]->get_descendants({ordered => 1});

    my @align_list = split / /, $align;
    foreach my $align_pair (@align_list) {
        my ($lang1_idx, $lang2_idx) = split /-/, $align_pair;
        $lang1_nodes[$lang1_idx]->add_aligned_node($lang2_nodes[$lang2_idx], "import");
    }
}

1;
