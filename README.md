# NESgate

VHDL-based emulator for the NES, targetted at the ULX3S development board.

## Building

### Prerequisites

The easiest way to build this project is with Docker. The makefiles are
already configured to do this, but you'll need Docker installed for them to
work. I highly recommend sticking with Docker here, as building HDL tools from
source (especially for macOS) is a painful adventure through the Dungeon
Dimensions. You might even become unbearably knurd.

```
$ pipenv shell
$ ./synth
```

### Programming

To load the resulting bitstream onto an FPGA board, use your favorite programmer.
For instance, this is the command for openFPGALoader:

```
openFPGALoader -b ulx3s -f ./build/toplevel.ulx3s.bit --unprotect-flash
```

## Organization

The project is broken down into individual, testable sub-modules in the `/cores`
folder, using some scripts to help with independent testing.

### Cores

Each core has an `analyze` script that imports each VHDL file into GHDL. It
recieves an argument to the build folder, which is necessary to ensure we can
CD into it and perform the analysis there. GHDL uses a `work-obj<STD>.cf` file
that records the _input_ paths for each file, not their absolute paths, and
it needs to be populated for elaboration to work because VHDL is a nightmare.

There is also a `test` script that is invoked to test the module independently,
this script receives the base directory to make invoking the python helpers
possible without having to actually install them as a full on module, but this
is not required.

### Targets

Right now, there's only one target supported- the ULX3S with the ECP5-85k. I
plan to extend the synthesis script to allow compilation for other targets as
well, but we'll cross that bridge when we get there.
