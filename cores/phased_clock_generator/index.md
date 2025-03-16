# Phased Clock Generator {#PhasedClockGen}

This core implements a 2-phase set of exclusive signals, necessary to drive the
various subcomponents of the MOS 6502.

In effect, this module takes in 1 clock signal and outputs 2 different signals
at the same frequency, but offset and shortened such that at most only one of
the two signals are high at any given time.

@ref phased_clock_generator