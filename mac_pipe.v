// -----------------------------------------------------------------------------
// mac_pipe.v : 4-stage pipelined fixed-point Multiply-Accumulate
//
//   Format   : signed Q(DW-FRAC).FRAC   (default Q1.15, 16-bit)
//   Product  : 2*DW bits  (Q2.30)
//   Acc      : 2*DW+GUARD bits (guard bits prevent overflow for 2^GUARD MACs)
//   Output   : round-to-nearest, saturate back to Q1.15
//
//   Pipeline (maps 1:1 onto Xilinx DSP48E1: AREG/BREG -> MREG -> PREG)
//     S1  input regs      a_r, b_r
//     S2  multiply reg    p_r  = a_r * b_r
//     S3  accumulate reg  acc_q (first ? 0 : acc_q) + p_r
//     S4  round + sat     out_data
//
//   Throughput : 1 MAC / cycle
//   Latency    : 4 cycles (input sampled -> out_valid/out_data)
//
//   Protocol   : in_first = first element of a dot product (acc restarts)
//                in_last  = last element  (result emitted 4 cycles later)
//                single-element dot product: first=last=1
// -----------------------------------------------------------------------------
module mac_pipe #(
    parameter DW    = 16,
    parameter FRAC  = 15,
    parameter GUARD = 8
)(
    input  wire                         clk,
    input  wire                         rst,        // sync, control only
    input  wire                         in_valid,
    input  wire                         in_first,
    input  wire                         in_last,
    input  wire signed [DW-1:0]         in_a,
    input  wire signed [DW-1:0]         in_b,

    output reg                          out_valid,
    output reg  signed [DW-1:0]         out_data,   // rounded + saturated
    output reg  signed [2*DW+GUARD-1:0] out_acc     // full precision result
);
    localparam PW = 2*DW;
    localparam AW = 2*DW + GUARD;

    // ---------------- S1 : input registers ----------------
    reg signed [DW-1:0] a_r, b_r;
    reg                 v1, f1, l1;

    always @(posedge clk) begin
        a_r <= in_a;                 // datapath: no reset (DSP-friendly)
        b_r <= in_b;
        if (rst) begin v1 <= 1'b0; f1 <= 1'b0; l1 <= 1'b0; end
        else     begin v1 <= in_valid; f1 <= in_first; l1 <= in_last; end
    end

    // ---------------- S2 : multiplier register ----------------
    (* use_dsp = "yes" *)
    reg signed [PW-1:0] p_r;
    reg                 v2, f2, l2;

    always @(posedge clk) begin
        p_r <= a_r * b_r;
        if (rst) begin v2 <= 1'b0; f2 <= 1'b0; l2 <= 1'b0; end
        else     begin v2 <= v1;   f2 <= f1;   l2 <= l1;   end
    end

    // ---------------- S3 : accumulator ----------------
    wire signed [AW-1:0] p_ext = p_r;               // sign extend
    reg  signed [AW-1:0] acc_q;
    reg                  done3;

    always @(posedge clk) begin
        if (v2) acc_q <= (f2 ? {AW{1'b0}} : acc_q) + p_ext;
        if (rst) done3 <= 1'b0;
        else     done3 <= v2 & l2;
    end

    // ---------------- S4 : round + saturate ----------------
    wire signed [AW-1:0] half = {{(AW-FRAC){1'b0}}, 1'b1, {(FRAC-1){1'b0}}};
    wire signed [AW-1:0] rnd  = (acc_q + half) >>> FRAC;
    wire signed [AW-1:0] smax = {{(AW-DW+1){1'b0}}, {(DW-1){1'b1}}};
    wire signed [AW-1:0] smin = {{(AW-DW+1){1'b1}}, {(DW-1){1'b0}}};

    always @(posedge clk) begin
        if (rst) out_valid <= 1'b0;
        else     out_valid <= done3;
        if (done3) begin
            out_acc  <= acc_q;
            out_data <= (rnd > smax) ? smax[DW-1:0] :
                        (rnd < smin) ? smin[DW-1:0] : rnd[DW-1:0];
        end
    end
endmodule
