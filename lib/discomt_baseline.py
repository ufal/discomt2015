#!/usr/bin/python
# -*- coding:UTF-8 -*-
import sys
import os
import re
import math
import optparse
import kenlm
from collections import defaultdict
from gzip import GzipFile

'''
takes a classification file (optionally gzipped) as input
and writes a file with two columns (replacement+target)

Input format:
  - classes (ignored)
  - true replacements (ignored)
  - source text (currently ignored)
  - target text
  - alignments (currently ignored)

Output format (for fmt=replace):
  - predicted classes
  - predicted replacements
  - original source text
  - original target text
  - alignments
'''

class KenLM:

    replace_re = re.compile('REPLACE_[0-9]+')

    all_fillers = [
        ['il'], ['elle'],
        ['ils'], ['elles'],
        ["c'"], ["ce"], ["ça"], ['cela'], ["on"]]

    non_fillers = [[w] for w in
                   '''
                   le l' se s' y en qui que qu' tout
                   faire ont fait est parler comprendre chose choses
                   ne pas dessus dedans
                   '''.strip().split()]

    model = None
    NONE_PENALTY = 0

    def map_class(self, x):
        if [x] in self.non_fillers:
            return 'OTHER'
        elif x == 'NONE':
            return 'OTHER'
        elif x == "c'":
            return 'ce'
        else:
            return x


    def gen_items(self, contexts, prev_contexts):
        '''
        extends the items from *prev_contexts* with
        fillers and the additional bits of context from
        *contexts*

        returns a list of (text, score, fillers) tuples,
        and expects prev_contexts to have the same shape.
        '''
        if len(contexts) == 1:
            return [(x+contexts[0], y, z)
                    for (x,y,z) in prev_contexts]
        else:
            #print >>sys.stderr, "gen_items %s %s"%(contexts, prev_contexts)
            context = contexts[0]
            next_contexts = []
            for filler in self.all_fillers:
                next_contexts += [(x+context+filler, y, z+filler)
                                  for (x,y,z) in prev_contexts]
            for filler in self.non_fillers:
                next_contexts += [(x+context+filler, y, z+filler)
                                  for (x,y,z) in prev_contexts]
            next_contexts += [(x+context, y+self.NONE_PENALTY, z+['NONE'])
                                for (x,y,z) in prev_contexts]
            if len(next_contexts) > 5000:
                print >>sys.stderr, "Too many alternatives, pruning some..."
                next_contexts = next_contexts[:200]
                next_contexts.sort(key=self.score_item, reverse=True)
            return self.gen_items(contexts[1:], next_contexts)

    def score_item(self, x):
        model_score = self.model.score(' '.join(x[0]))
        return model_score + x[1]

    def __init__(self, model_path='../data/corpus.5.fr.trie.kenlm', NONE_PENALTY=0):
        self.model = kenlm.LanguageModel(model_path)
        self.NONE_PENALTY = NONE_PENALTY
        
    def score_sentence(self, sent):
        labels = filter(lambda x:x.startswith("REPLACE_"), sent.split(' ')) 
        sent = self.replace_re.sub('REPLACE', sent)
        #classes = [x.strip() for x in classes_str.split(' ')]
        contexts = [x.strip().split() for x in sent.split('REPLACE')]
        items = self.gen_items(contexts, [([], 0.0, [])])
        items.sort(key = self.score_item, reverse=True)
        pred_fillers = items[0][2]
        pred_classes = [self.map_class(x) for x in pred_fillers]
#        return items
        #TODO compute individual scores for each slot
        # and convert the scores to probabilities
        scored_items = []
        for item in items:
            words, penalty, fillers = item
            scored_items.append((words, self.score_item(item), fillers))
        best_penalty = max([x[1] for x in items])
        dists = [defaultdict(float) for k in items[0][2]]
        for words, penalty, fillers in scored_items:
            exp_pty = math.exp(penalty - best_penalty)
            for j, w in enumerate(fillers):
                dists[j][w] += exp_pty
        for j in xrange(len(items[0][2])):
            sum_all = sum(dists[j].values())
            if sum_all == 0:
                sum_all = 1.0
            items = [(k, v/sum_all) for k,v in dists[j].iteritems()]
            items.sort(key=lambda x: -x[1])
            print "%s\t%s"%(
                labels[j], "\t".join([
                    '%s %.4f'%(x[0], x[1])
                    for x in items if x[1] > 0.001]))

