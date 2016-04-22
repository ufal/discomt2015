package Treex::Block::W2A::FR::GuessGender;

use Moose;
use Treex::Core::Common;
use Treex::Tool::Tagger::MElt;

use List::Util qw/sum/;

extends 'Treex::Core::Block';

has '_tagger' => ( is => 'ro', isa => 'Treex::Tool::Tagger::MElt', builder => '_build_tagger');

sub _build_tagger {
    my ($self) = @_;
    return Treex::Tool::Tagger::MElt->new();
}


sub process_anode {
    my ($self, $anode) = @_;

    return if (!defined $anode->tag || $anode->tag !~ /^(NOM)|(NAM)$/);

    my ($tag, $new_lemma) = $self->_tagger->tag_sentence([ $anode->lemma ]);
    
    ($tag) = @$tag;
    ($new_lemma) = @$new_lemma;
    $anode->wild->{tag} = $tag;
    $anode->wild->{lemma} = $new_lemma;
    if ($tag =~ /g=(.)/) {
        $anode->wild->{gender} = $1;
    }
}

1;
