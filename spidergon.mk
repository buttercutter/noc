export DESIGN_NICKNAME = noc
export DESIGN_NAME = spidergon_top
export PLATFORM    = nangate45

export VERILOG_FILES = $(filter-out ./designs/src/$(DESIGN_NICKNAME)/test_spidergon.v, \
			$(wildcard ./designs/src/$(DESIGN_NICKNAME)/*.v))
export SDC_FILE      = ./designs/src/$(DESIGN_NICKNAME)/spidergon.sdc

# These values must be multiples of placement site
# x=0.19 y=1.4
#export DIE_AREA    = 0 0 320.15 320.6
#export CORE_AREA   = 10.07 11.2 310.27 310.8
export DIE_AREA    = 0 0 620.15 620.6
export CORE_AREA   = 10.07 11.2 610.27 610.8

export CLOCK_PERIOD = 5.000
