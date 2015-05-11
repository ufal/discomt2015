ORIG_TRAIN_DATA_NAMES = Europarl IWSLT14 NCv9


TREEX = PERL5LIB=$$PERL5LIB:$$PWD/lib treex

ifeq ($(LRC),1)
LRC_FLAG=-p --jobs 100 --qsub '-hard -l mem_free=6G -l act_mem_free=6G -l h_vmem=6G'
endif


input/%/done : data/input/%.data.gz
	mkdir -p $(dir $@); \
	if [ -f data/input/$*.en-fr.doc-ids.gz ]; then \
		ids_file=data/input/$*.en-fr.doc-ids.gz; \
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

tables/%/done : trees/%/done
	mkdir -p $(dir $@); \
	$(TREEX) $(LRC_FLAG) -Ssrc -Lfr \
		Read::Treex from='!$(dir $<)/*.streex' skip_finished='{$(dir $<)(.+).streex$$}{$(dir $@)$$1.txt}' \
		Print::ExtractDiscomt2015Table extension=".txt" path=$(dir $@)
	touch $@

prepare_dev_data : tables/TEDdev/done
