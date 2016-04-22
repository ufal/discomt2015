SHELL=/bin/bash
TRANSL_PAIR=en-de
SRC_LANG:=$(shell echo $(TRANSL_PAIR) | cut -f1 -d'-')
TRG_LANG:=$(shell echo $(TRANSL_PAIR) | cut -f2 -d'-')

ORIG_TEST_DATA=data/input/TEDdev.$(TRANSL_PAIR).data.filtered.gz


ORIG_TRAIN_DATA_NAMES = Europarl IWSLT14 NCv9


TREEX = PERL5LIB=$$PERL5LIB:$$PWD/lib treex

LRC=1
MEM=20G
ifeq ($(LRC),1)
LRC_FLAG_F=-p --jobs 100 --priority=-50 --qsub '-hard -l mem_free=$(1) -l act_mem_free=$(1) -l h_vmem=$(1)'
LRC_FLAG=$(call LRC_FLAG_F,$(MEM))
endif


input/%/done : data/input/%.data.filtered.gz
	doc_ids=`perl -e 'my ($$id, $$langstr) = split /\./, "$*"; my (@langs) = split /-/, $$langstr; print $$id.".".(join "-", sort @langs);'`; \
	mkdir -p $(dir $@); \
	if [ -f data/input/$$doc_ids.doc-ids.gz ]; then \
		ids_file=data/input/$$doc_ids.doc-ids.gz; \
	fi; \
	zcat $< | scripts/split_data_to_docs.pl $(dir $@) $$ids_file
	touch $@ 

trees/%.de-en/done : input/%.de-en/done
	mkdir -p $(dir $@); \
	scripts/german_analysis_on_cluster.sh $(dir $(word 1,$^)) $(dir $@) 0; \
	$(TREEX) $(call LRC_FLAG_F,2G) -Ssrc -Lde \
		Read::CoNLL2009 from='!$(dir $@)/*.conll' use_p_attribs=1 skip_finished='{$(dir $@)(.+).conll$$}{$(dir $@)$$1.streex}' \
		Write::Treex path='$(dir $@)' storable=1
	touch $@
	

trees/%/done : input/%/done
	translpair=`echo $* | cut -f2 -d'.'`; \
	srclang=`echo $$translpair | cut -f1 -d'-'`; \
	trglang=`echo $$translpair | cut -f2 -d'-'`; \
	mkdir -p $(dir $@); \
	$(TREEX) $(LRC_FLAG) -Ssrc \
		Read::Discomt2015 from='!$(dir $<)/*.txt' langs="$$translpair" skip_finished='{$(dir $<)(.+).txt$$}{$(dir $@)$$1.streex}' \
		scen/$$srclang.src.analysis.scen \
		Write::Treex path=$(dir $@) storable=1
	touch $@

#	mkdir -p log; \
#	job_count=`find $(dir $(word 1,$^)) -name '*.txt' 2> /dev/null | wc -l`; \
#	i=0; \
#	for infile in $(dir $(word 1,$^))/*.txt; do \
#		if [ $$i -eq 0 ]; then \
#			if [ `qstat | wc -l` -gt 5000 ]; then \
#				sleep 300; \
#			fi; \
#		fi; \
#		if [ ! -e $(dir $@)/`basename $$infile` ]; then \
#			qsubmit --jobname='de_trg_analysis.$*' --mem="6g" --logdir="log/" \
#				"scripts/german_analysis.sh $$infile $(dir $@) 1"; \
#			i=$$((i++)); \
#		fi; \
#		if [ $$i -gt 500 ]; then \
#			i=0; \
#		fi; \
#	done; \
#	while [ `find $(dir $@) -name '*.txt' 2> /dev/null | wc -l` -lt $$job_count ]; do \
#		sleep 10; \
#	done;
trg_analysis/%.en-de/done : input/%.en-de/done trees/%.en-de/done
	mkdir -p $(dir $@); \
	scripts/german_analysis_on_cluster.sh $(dir $(word 1,$^)) $(dir $@) 1; \
	$(TREEX) $(call LRC_FLAG_F,2G) -Ssrc -Lde \
		Read::Treex from='!$(dir $(word 2,$^))/*.streex' skip_finished='{$(dir $(word 2,$^))(.+).streex$$}{$(dir $@)$$1.streex}' \
		Import::TargetMorpho from_dir='$(dir $@)' \
		Write::Treex path=$(dir $@) storable=1
	touch $@

trg_analysis/%.en-fr/done : trees/%.en-fr/done
	mkdir -p $(dir $@); \
	$(TREEX) $(call LRC_FLAG_F,2G) -Ssrc -Lfr \
		Read::Treex from='!$(dir $<)/*.streex' skip_finished='{$(dir $<)(.+).streex$$}{$(dir $@)$$1.streex}' \
		W2A::FR::GuessGender \
		Write::Treex path=$(dir $@) storable=1
	touch $@

trg_analysis/%.de-en/done : input/%.de-en/done trees/%.de-en/done
	mkdir -p $(dir $@); \
	$(TREEX) $(call LRC_FLAG_F,2G) -Ssrc -Len \
		Read::Treex from='!$(dir $(word 2,$^))/*.streex' skip_finished='{$(dir $(word 2,$^))(.+).streex$$}{$(dir $@)$$1.streex}' \
		Import::TargetEnglishSentence from_dir='$(dir $(word 1,$^))' src_language='de' \
		W2A::EN::GuessGender \
		Write::Treex path=$(dir $@) storable=1
	touch $@
		
tables/%/done : trg_analysis/%/done
	translpair=`echo $* | cut -f2 -d'.'`; \
	srclang=`echo $$translpair | cut -f1 -d'-'`; \
	trglang=`echo $$translpair | cut -f2 -d'-'`; \
	mkdir -p $(dir $@); \
	$(TREEX) $(LRC_FLAG) -Ssrc -L$$trglang \
		Read::Treex from='!$(dir $<)/*.streex' skip_finished='{$(dir $<)(.+).streex$$}{$(dir $@)$$1.txt}' \
		Print::ExtractDiscomt2015Table src_language=$$srclang extension=".txt" path=$(dir $@)
	touch $@

tables/%.data.gz : tables/%/done
	doc_ids=`perl -e 'my ($$id, $$langs) = split /\./, "$*"; my ($$src, $$trg) = split /-/, $$langs; print ($$trg eq "en" ? $$id.".".$$langs : $$id.".".$$trg."-".$$src);'`; \
	if [ -f data/input/$$doc_ids.doc-ids.gz ]; then \
		for part_file in `scripts/sort_data_splits_by_doc_ids.pl $(dir $<) data/input/$$doc_ids.doc-ids.gz`; do \
			cat $$part_file >> $(basename $@); \
		done; \
		gzip $(basename $@); \
	else \
		find $(dir $<) -name '*.txt' | sort | xargs cat | gzip -c > $@; \
	fi

.PRECIOUS : input/%/done trees/%/done trees_coref/%/done trees_fr/%/done tables/%/done

TRAIN_DATA=tables/NCv9.$(TRANSL_PAIR).data.gz
#TRAIN_DATA=tables/train.$(TRANSL_PAIR).data.gz
TEST_DATA=tables/TEDdev.$(TRANSL_PAIR).data.gz

#$(TRAIN_DATA) : tables/Europarl.data.gz tables/NCv9.data.gz
#$(TRAIN_DATA) : tables/Europarl.$(TRANSL_PAIR).data.gz tables/IWSLT15.$(TRANSL_PAIR).data.gz tables/NCv9.$(TRANSL_PAIR).data.gz
#	zcat $^ | gzip -c > $@

prepare_train_data : $(TRAIN_DATA)
prepare_dev_data : $(TEST_DATA)

#FEATSET_LIST=conf/$(LANGUAGE).featset_list

train_test :
	$(MLYN_DIR)/run.sh -f conf/params.ini \
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

DATE := $(shell date +%Y-%m-%d_%H-%M-%S)

.PHONY : eval
eval : $(ORIG_TEST_DATA) $(RESULT)
	name=`echo "$(word 2,$^)" | perl -ne '$$_ =~ s|^ml_runs/||; $$_ =~ s|/result/.*$$||; $$_ =~ s|/|_|g; print $$_;'`; \
	cat $(word 2,$^) | scripts/vw_res_to_official_res.pl $(word 1,$^) $(TRANSL_PAIR) > res/$$name.res; \
	perl eval/WMT16_CLPP_scorer.pl <( zcat $(word 1,$^) ) res/$$name.res $(TRANSL_PAIR) > eval/res/$$name.eval; \
	score=`cat eval/res/$$name.eval | grep "MACRO-averaged R" | sed 's/^.*: *//'`; \
	echo -e "$(DATE)\t$$score\t$$name" >> results.$(TRANSL_PAIR).txt; \
	cat eval/res/$$name.eval

####################### DIAGNOSTICS #######################################

# shows only incorrextly resolved instances from the TEST_DATA
# features can be filtered by appending:
# $(MLYN_DIR)/scripts/filter_feat.pl --in kenlm_w_prob,kenlm_w_rank,trg_class |
show_error_instances : $(TEST_DATA) $(RESULT)
	zcat $(word 1,$^) | \
		$(MLYN_DIR)/scripts/paste_data_results.pl --log $(word 2,$^) | \
		scripts/filter_errors.pl | \
		$(MLYN_DIR)/scripts/filter_feat.pl --in kenlm_w_prob,kenlm_w_rank,trg_class | \
		less -S

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
