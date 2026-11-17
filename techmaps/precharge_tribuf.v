// Yosys techmap that turns each tri-state buffer into a mux that reads all
// ones while it isn't enabled.
//
// The CPU's internal buses are precharged high, and the bus multiplexer reads
// an undriven ('Z') bit as 1. GHDL's synthesis drops the 'Z' choice, so in the
// netlist that 1 has to come from the tri-state buffers themselves. `synth`
// runs `tribuf -merge` first, so each bus has a single buffer, then this map.
// (`tribuf -logic` leaves an undriven bus undefined, and drops the enable of a
// buffer that's the only driver of its net, so it can't model the precharge.)
(* techmap_celltype = "$tribuf" *)
module _precharge_tribuf (A, EN, Y);
    parameter WIDTH = 1;
    input [WIDTH-1:0] A;
    input EN;
    output [WIDTH-1:0] Y;
    assign Y = EN ? A : {WIDTH{1'b1}};
endmodule
