package Treex::Block::Read::Discomt2015;
use Moose;
use Treex::Core::Common;
extends 'Treex::Block::Read::BaseTextReader';

has 'langs'  => (is => 'ro', isa => 'Str', required => 1);

has 'skip_empty' => (is => 'ro', isa => 'Bool', default => 0);

sub next_document {
    my ($self) = @_;
    my $text = $self->next_document_text();
    return if !defined $text;
    
    my @langs = split /[-, ]/, $self->langs;
    my @lang_sels = map {$_ =~ /-/ ? [ split(/-/, $_) ] : [ $_, $self->selector ]} @langs;
    
    my $document = $self->new_document();
    foreach my $line ( split /\n/, $text ) {
        next if ($line eq '' and $self->skip_empty);
        my ($class, $missing_word, $sent1, $sent2, $align) = split /\t/, $line;
        my @sents = ($sent1, $sent2);
        
        my $bundle = $document->create_bundle();
        my @atrees = $self->_create_atrees($bundle, \@lang_sels, @sents);
        $self->_add_aligns(\@atrees, $align);

        my @classes = split / /, $class;
        my @miss_words = split / /, $missing_word;
        my @replace_nodes = grep {$_->form =~ /^REPLACE_/} $atrees[1]->get_descendants({ordered => 1});
        for (my $i = 0; $i < @replace_nodes; $i++) {
            $replace_nodes[$i]->wild->{class} = $classes[$i];
            $replace_nodes[$i]->wild->{miss_word} = $miss_words[$i];
        }
    }

    return $document;
}

sub _create_atrees {
    my ($self, $bundle, $lang_sels, @sents) = @_;
    
    my @atrees = ();
    my $tagged = 0;
    foreach my $lang_sel (@$lang_sels){
        my ($l, $s) = @$lang_sel;
        my $zone = $bundle->create_zone( $l, $s );
        my $sent = shift @sents;
        $zone->set_sentence($sent);
        my $a_root = $zone->create_atree();
        my $i = 0;
        foreach my $token (split / /, $sent) {
            if ($tagged) {
                my ($lemma, $tag) = split /\|/, $token;
                $a_root->create_child(
                    form           => $lemma,
                    ord            => $i + 1,
                    lemma          => $lemma,
                    tag            => $tag,
                );
            }
            else {
                $a_root->create_child(
                    form           => $token,
                    ord            => $i + 1,
                );
            }
            $i++;
        }
        push @atrees, $a_root;
        $tagged++;
    }
    return @atrees;
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

__END__

=head1 NAME

Treex::Block::Read::SentencesTSV

=head1 SYNOPSIS

 Read::SentencesTSV from='!dir*/file*.txt' langs=en,cs

 # empty selector by default, can be overriden for both (all) languages
 Read::SentencesTSV from='!dir*/file*.txt' langs=en,cs selector=hello
 
 # or if each language should have different selector
 Read::SentencesTSV from='!dir*/file*.txt' langs=en-hello,cs-bye

 # or if one of the columns contains bundle id
 Read::SentencesTSV from='!dir*/file*.txt' langs=BUNDLE_ID,en-hello,cs-bye

=head1 DESCRIPTION

Document reader for multilingual sentence-aligned plain text format.
One sentence per line, each language separated by a TAB character.
The sentences are stored into L<bundles|Treex::Core::Bundle> in the 
L<document|Treex::Core::Document>.

=head1 ATTRIBUTES

=over

=item langs

space or comma separated list of languages
Each line of each file must contain so many columns.
Language code may be followed by a hyphen and a selector.

=item from

space or comma separated list of filenames
See L<Treex::Core::Files> for full syntax.

=item skip_empty

If set to 1, ignore empty lines (don't create empty sentences). 

=back

=head1 METHODS

=over

=item next_document

Loads a document.

=back

=head1 SEE

L<Treex::Block::Read::BaseTextReader>
L<Treex::Core::Document>
L<Treex::Core::Bundle>
L<Treex::Block::Read::AlignedSentences>
L<Treex::Block::Read::Sentences>

=head1 AUTHOR

Martin Popel

=head1 COPYRIGHT AND LICENSE

Copyright © 2013 by Institute of Formal and Applied Linguistics, Charles University in Prague

This module is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
