# noc
A simple [spidergon network-on-chip](http://sci-hub.do/https://ieeexplore.ieee.org/abstract/document/1411133) with [wormhole switching](https://en.wikipedia.org/wiki/Wormhole_switching) feature

USAGE :
1. Synthesis : `yosys spidergon.ys`
2. Place and Route : 

    FPGA : `nextpnr-ice40 --lp8k --pcf pins.pcf --json spidergon.json --package cm81 --gui`
    
    ASIC : `git clone https://github.com/The-OpenROAD-Project/OpenROAD-flow`
    
           cd OpenROAD-flow/ && source setup_env.sh
           
           ./build_openroad.sh -o --or-branch openroad
           
           cd ./flow && mv PATH_TO_NOC_REPO ./designs/src/
           
           make DESIGN_CONFIG=./designs/src/noc/spidergon.mk
           
           klayout -e ./results/nangate45/noc/6_1_merged.gds results/nangate45/noc/6_final.gds
           

TODO :
1. Formal Verification of NoC
2. Add support for [GALS (Globally Asynchronous, Locally Synchronous)](https://en.wikipedia.org/wiki/Globally_asynchronous_locally_synchronous)
