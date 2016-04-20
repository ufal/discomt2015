SHELL=/bin/bash
TRANSL_PAIR=fr-en
SRC_LANG:=$(shell echo $(TRANSL_PAIR) | cut -f1 -d'-')
TRG_LANG:=$(shell echo $(TRANSL_PAIR) | cut -f2 -d'-')

ORIG_TEST_DATA=data/input/TEDdev.$(TRANSL_PAIR).data.filtered.gz


ORIG_TRAIN_DATA_NAMES = Europarl IWSLT14 NCv9


TREEX = PERL5LIB=$$PERL5LIB:$$PWD/lib treex

LRC=1
MEM=20G
ifeq ($(LRC),1)
LRC_FLAG=-p --jobs 100 --qsub '-hard -l mem_free=$(MEM) -l act_mem_free=$(MEM) -l h_vmem=$(MEM)'
endif


input/%/done : data/input/%.data.filtered.gz
	doc_ids=`perl -e 'my ($$id, $$langs) = split /\./, "$*"; my ($$src, $$trg) = split /-/, $$langs; print ($$trg eq "en" ? $$id.".".$$langs : $$id.".".$$trg."-".$$src);'`; \
	mkdir -p $(dir $@); \
	if [ -f data/input/$$doc_ids.doc-ids.gz ]; then \
		ids_file=data/input/$$doc_ids.doc-ids.gz; \
	fi; \
	zcat $< | scripts/split_data_to_docs.pl $(dir $@) $$ids_file
	touch $@ 

trees/%/done : input/%/done
	translpair=`echo $* | cut -f2 -d'.'`; \
	srclang=`echo $$translpair | cut -f1 -d'-'`; \
	trglang=`echo $$translpair | cut -f2 -d'-'`; \
	mkdir -p $(dir $@); \
	$(TREEX) $(LRC_FLAG) -Ssrc \
		Read::Discomt2015 from='!$(dir $<)/*.txt' langs="$$translpair" skip_finished='{$(dir $<)(.+).txt$$}{$(dir $@)$$1.streex}' \
		scen/$$srclang.src.analysis.scen \
		scen/$$trglang.trg.analysis.scen \
		Write::Treex path=$(dir $@) storable=1
	touch $@

#	job_count=`find $(dir $(word 1,$^)) -name '*.txt' 2> /dev/null | wc -l`; \
#	for infile in $(dir $(word 1,$^))/*.txt; do \
#		qsubmit --jobname='trg_analysis.$*' --mem="10g" --logdir="log/" \
#			"scripts/do_trg_analysis.sh $$infile $(dir $@)"; \
#	done; \
#	while [ `find $(dir $@) -name '*.txt' 2> /dev/null | wc -l` -lt $$job_count ]; do \
#		sleep 10; \
#	done; 
trg_analysis/%/done : input/%/done trees/%/done
	translpair=`echo $* | cut -f2 -d'.'`; \
	trglang=`echo $$translpair | cut -f2 -d'-'`; \
	mkdir -p $(dir $@); \
	mkdir -p log; \
	$(TREEX) $(LRC_FLAG) -Ssrc -L$$trglang \
		Read::Treex from='!$(dir $(word 2,$^))/*.streex' \
		Import::TargetMorpho from_dir='$(dir $@)' \
		Write::Treex path=$(dir $@) storable=1
	touch $@

tables/%/done : trees/%/done
	mkdir -p $(dir $@); \
	$(TREEX) $(LRC_FLAG) -Ssrc -Lfr \
		Read::Treex from='!$(dir $<)/*.streex' skip_finished='{$(dir $<)(.+).streex$$}{$(dir $@)$$1.txt}' \
		Print::ExtractDiscomt2015Table extension=".txt" path=$(dir $@)
	touch $@

tables/%.data.gz : tables/%/done
	find $(dir $<) -name '*.txt' | sort | xargs cat | gzip -c > $@

.PRECIOUS : input/%/done trees/%/done trees_coref/%/done trees_fr/%/done tables/%/done

TRAIN_DATA=tables/train.data.gz
TEST_DATA=tables/TEDdev.data.gz

$(TRAIN_DATA) : tables/Europarl.data.gz tables/NCv9.data.gz
	zcat $^ | gzip -c > $@

prepare_train_data : $(TRAIN_DATA)
prepare_dev_data : $(TEST_DATA)

#FEATSET_LIST=conf/$(LANGUAGE).featset_list

train_test :
	$(ML_FRAMEWORK_DIR)/run.sh -f conf/params.ini \
		EXPERIMENT_TYPE=train_test \
		DATA_LIST="TRAIN_DATA TEST_DATA" \
		TEST_DATA_LIST="TRAIN_DATA TEST_DATA" \
		TRAIN_DATA=$(TRAIN_DATA) \
		TEST_DATA=$(TEST_DATA) \
		ML_METHOD_LIST=conf/ml_method.list \
		LRC=$(LRC) \
		TMP_DIR=ml_runs \
		D="$(D)"

#$(RESULT).adjusted : $(RESULT)
#	cat $< | scripts/postprocess_vw_results.pl > $@
#eval : $(RESULT).adjusted

eval : $(RESULT)
	name=`echo "$<" | perl -ne '$$_ =~ s|^ml_runs/||; $$_ =~ s|/result/.*$$||; $$_ =~ s|/|_|g; print $$_;'`; \
	cat $< | scripts/vw_res_to_official_res.pl $(ORIG_TEST_DATA) > res/$$name.res; \
	./WMT16_CLPP_scorer.pl $(ORIG_TEST_DATA) res/$$name.res

###########################################################################
##################### BASELINE ############################################
###########################################################################

baseline : baseline/result/TEDdev.$(TRANSL_PAIR).res
baseline/result/TEDdev.$(TRANSL_PAIR).res : $(ORIG_TEST_DATA)
	 baseline/discomt_baseline.py \
	 	--fmt=replace --removepos \
	 	--conf baseline/$(TRANSL_PAIR).yml \
		--lm baseline/mono+para.5.$(TRG_LANG).lemma.trie.kenlm \
		$< > $@

eval_baseline : $(ORIG_TEST_DATA) baseline/result/TEDdev.$(TRANSL_PAIR).res
	perl eval/WMT16_CLPP_scorer.pl <( zcat $(word 1,$^) ) $(word 2,$^) $(TRANSL_PAIR)
