package Treex::Block::Import::TargetMorpho;
use Moose;
use Treex::Core::Common;
extends 'Treex::Core::Block';

has 'from_dir' => (is => 'ro', isa => 'Str', required => 1);

sub process_document {
    my ($self, $doc) = @_;
    my $doc_name = $doc->file_stem;

    my $morpho_file = $self->from_dir . "/" . $doc_name . ".txt";
    open my $morpho_fh, "<:utf8", $morpho_file;

    my @all_nodes = map {
        my $atree = $_->get_tree($self->language, 'a', $self->selector);
        $atree->get_descendants({ordered => 1})
    } $doc->get_bundles;

    while (<$morpho_fh>) {
        my $curr_node = shift @all_nodes;
        chomp $_;
        my ($case, $num, $gen) = split /\|/, $_;
        
        next if (!defined $gen);
        next if ($gen !~ /^(fem)|(masc)|(neut)$/);

        $curr_node->wild->{gender} = $gen;
    }
}

1;
