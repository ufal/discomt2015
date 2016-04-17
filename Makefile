SHELL=/bin/bash
TRANSL_PAIR=fr-en
TRG_LANG:=$(shell echo $(TRANSL_PAIR) | cut -f2 -d'-')

ORIG_TEST_DATA=data/input/TEDdev.$(TRANSL_PAIR).data.filtered.gz


ORIG_TRAIN_DATA_NAMES = Europarl IWSLT14 NCv9


TREEX = PERL5LIB=$$PERL5LIB:$$PWD/lib treex

LRC=1
ifeq ($(LRC),1)
LRC_FLAG=-p --jobs 100 --qsub '-hard -l mem_free=20G -l act_mem_free=20G -l h_vmem=20G'
endif


input/%/done : data/input/%.data.filtered.gz
	mkdir -p $(dir $@); \
	if [ -f data/input/$*.$(TRANSL_PAIR).doc-ids.gz ]; then \
		ids_file=data/input/$*.$(TRANSL_PAIR).doc-ids.gz; \
	fi; \
	zcat $< | scripts/split_data_to_docs.pl $(dir $@) $$ids_file
	touch $@ 

trees/%/done : input/%/done
	mkdir -p $(dir $@); \
	$(TREEX) $(LRC_FLAG) -Ssrc \
		Read::Discomt2015 from='!$(dir $<)/*.txt' langs='en,fr' skip_finished='{$(dir $<)(.+).txt$$}{$(dir $@)$$1.streex}' \
		scen/en.analysis.scen \
		Write::Treex path=$(dir $@) storable=1
	touch $@

trees_coref/%/done : trees/%/done
	mkdir -p $(dir $@); \
	$(TREEX) $(LRC_FLAG) -Ssrc \
		Read::Treex from='!$(dir $<)/*.streex' skip_finished='{$(dir $<)(.+).streex$$}{$(dir $@)$$1.streex}' \
		scen/coref.scen \
		Write::Treex path=$(dir $@) storable=1
	touch $@

trees_fr/%/done : trees_coref/%/done
	mkdir -p $(dir $@); \
	$(TREEX) $(LRC_FLAG) -Ssrc \
		Read::Treex from='!$(dir $<)/*.streex' skip_finished='{$(dir $<)(.+).streex$$}{$(dir $@)$$1.streex}' \
		scen/fr.analysis.scen \
		Write::Treex path=$(dir $@) storable=1
	touch $@

tables/%/done : trees_fr/%/done
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
