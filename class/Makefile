ORIG_TRAIN_DATA_NAMES = Europarl IWSLT14 NCv9


TREEX = PERL5LIB=$$PERL5LIB:$$PWD/lib treex

ifeq ($(LRC),1)
LRC_FLAG=-p --jobs 200 --qsub '-hard -l mem_free=2G -l act_mem_free=2G -l h_vmem=2G'
endif


input/%/done : data/input/%.data.gz
	mkdir -p $(dir $@); \
	zcat $< | scripts/split_data_to_docs.pl $(dir $@) data/input/$*.en-fr.doc-ids.gz
	touch $@ 

trees/%/done : input/%/done
	mkdir -p $(dir $@); \
	$(TREEX) $(LRC_FLAG) -Ssrc \
		Read::Discomt2015 from='!$(dir $<)/*.txt' langs='en,fr' skip_finished='{$(dir $<)(.+).txt$$}{$(dir $@)$$1.treex.gz}' \
		scen/en.analysis.scen \
		Write::Treex path=$(dir $@) storable=1
	touch $@

tables/% : trees/%
	mkdir -p $@; \
	$(TREEX) -Ssrc \
		Read::Treex from='!$</*.treex.gz' \

