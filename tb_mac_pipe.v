`timescale 1ns/1ps
// Self-checking TB: random dot products (with/without idle gaps),
// directed saturation, latency + throughput report.
module tb_mac_pipe;
    localparam DW = 16, FRAC = 15, GUARD = 8, AW = 2*DW+GUARD;
    localparam MAXV = 512;

    reg clk = 0, rst = 1;
    reg in_valid = 0, in_first = 0, in_last = 0;
    reg signed [DW-1:0] in_a = 0, in_b = 0;
    wire out_valid;
    wire signed [DW-1:0] out_data;
    wire signed [AW-1:0] out_acc;

    mac_pipe #(.DW(DW), .FRAC(FRAC), .GUARD(GUARD)) dut (
        .clk(clk), .rst(rst),
        .in_valid(in_valid), .in_first(in_first), .in_last(in_last),
        .in_a(in_a), .in_b(in_b),
        .out_valid(out_valid), .out_data(out_data), .out_acc(out_acc));

    always #5 clk = ~clk;

    integer seed = 32'hC0FFEE;
    integer cyc = 0, errors = 0, ridx = 0, total_macs = 0;
    integer t_first_in = -1, t_first_out = -1;
    reg signed [DW-1:0] exp_mem [0:MAXV-1];

    always @(posedge clk) cyc <= cyc + 1;

    // ---------------- checker ----------------
    always @(posedge clk) if (out_valid) begin
        if (t_first_out < 0) t_first_out = cyc;
        if (out_data !== exp_mem[ridx]) begin
            errors = errors + 1;
            $display("MISMATCH #%0d: got %0d exp %0d", ridx, out_data, exp_mem[ridx]);
        end
        ridx = ridx + 1;
    end

    // ---------------- golden model ----------------
    function signed [DW-1:0] sat_round(input signed [63:0] s);
        reg signed [63:0] r;
        begin
            r = (s + (64'sd1 <<< (FRAC-1))) >>> FRAC;
            if      (r >  64'sd32767)  sat_round = 16'sh7FFF;
            else if (r < -64'sd32768)  sat_round = 16'sh8000;
            else                       sat_round = r[DW-1:0];
        end
    endfunction

    // ---------------- driver ----------------
    task drive(input integer first, input integer last,
               input signed [DW-1:0] a, input signed [DW-1:0] b);
        begin
            @(negedge clk);
            in_valid = 1; in_first = first; in_last = last; in_a = a; in_b = b;
            if (t_first_in < 0) t_first_in = cyc;
        end
    endtask

    task idle;
        begin @(negedge clk); in_valid = 0; in_first = 0; in_last = 0; end
    endtask

    task run_phase(input integer nvec, input integer gaps,
                   input integer maxlen, input integer directed);
        integer v, k, len, g;
        reg signed [DW-1:0] a, b;
        reg signed [63:0] s;
        begin
            ridx = 0;
            for (v = 0; v < nvec; v = v + 1) begin
                len = 1 + ({$random(seed)} % maxlen);
                s = 0;
                for (k = 0; k < len; k = k + 1) begin
                    if (gaps) for (g = {$random(seed)} % 3; g > 0; g = g - 1) idle;
                    a = $random(seed);
                    b = $random(seed);
                    if (directed) begin           // worst-case: -1 * -1
                        a = 16'sh8000; b = (v % 2) ? 16'sh8000 : 16'sh7FFF;
                    end
                    s = s + a * b;
                    drive(k == 0, k == len-1, a, b);
                    total_macs = total_macs + 1;
                end
                exp_mem[v] = sat_round(s);
            end
            idle;
            while (ridx < nvec) @(posedge clk);   // drain
            repeat (3) @(posedge clk);
        end
    endtask

    integer c0, m0;
    initial begin
        repeat (4) @(posedge clk);
        @(negedge clk) rst = 0;

        // 1) latency probe: single MAC, first=last=1
        run_phase(1, 0, 1, 0);
        $display("LATENCY  : %0d cycles (input sampled -> out_valid)",
                 t_first_out - t_first_in);

        // 2) random, with idle bubbles
        run_phase(300, 1, 16, 0);
        // 3) directed saturation
        run_phase(40, 0, 16, 1);

        // 4) back-to-back throughput (no bubbles)
        total_macs = 0; c0 = cyc;
        run_phase(400, 0, 16, 0);
        m0 = total_macs;
        $display("THROUGHPUT: %0d MACs streamed, ~%0d cycles incl. drain => ~%0.3f MAC/cycle",
                 m0, cyc - c0, m0 * 1.0 / (cyc - c0));

        if (errors == 0) $display("PASS: all checks matched");
        else             $display("FAIL: %0d mismatches", errors);
        $finish;
    end
endmodule
