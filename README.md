# noc
A simple [spidergon network-on-chip](http://sci-hub.tw/https://ieeexplore.ieee.org/abstract/document/1411133) with [wormhole switching](https://en.wikipedia.org/wiki/Wormhole_switching) feature

USAGE :
1. Synthesis : yosys spidergon.ys
2. Place and Route : nextpnr-ice40 --lp8k --pcf pins.pcf --json spidergon.json --package cm81 --gui

TODO :
1. Formal Verification of NoC
2. Add support for [GALS (Globally Asynchronous, Locally Synchronous)](https://en.wikipedia.org/wiki/Globally_asynchronous_locally_synchronous)
