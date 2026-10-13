`timescale 1ns/1ps

// Interface
interface sha256_if(input logic clk, input logic reset_n);
  logic init;
  logic next;
  logic mode;
  logic [511:0] block;
  logic ready;
  logic [255:0] digest;
  logic digest_valid;

  clocking cb @(posedge clk);
    output init, next, mode, block;
    input ready, digest, digest_valid;
  endclocking

  modport DUT (
    input clk, reset_n, init, next, mode, block,
    output ready, digest, digest_valid
  );

  modport TEST (
    input clk, reset_n, ready, digest, digest_valid,
    output init, next, mode, block
  );
endinterface

// ----------------------------------------------------------------------
// Transaction class
// ----------------------------------------------------------------------
class sha256_txn;
  rand bit init;
  rand bit next;
  rand bit mode;
  rand bit [511:0] block;
  
  bit ready;
  bit [255:0] digest;
  bit digest_valid;

  function void display(string tag = "");
    $display("[%0s] init=%0b next=%0b mode=%0b ready=%0b digest_valid=%0b", 
             tag, init, next, mode, ready, digest_valid);
    if (digest_valid) begin
      $display("     digest=0x%064h", digest);
    end
  endfunction
endclass

// ----------------------------------------------------------------------
// Generator with VERIFIED Test Vectors
// ----------------------------------------------------------------------
class sha256_gen;
  mailbox #(sha256_txn) gen2drv;
  int num_txns;

  // VERIFIED test vectors with known SHA256 results
  typedef struct {
    bit [511:0] block;
    bit [255:0] expected_digest;
    string description;
  } test_vector_t;

  test_vector_t test_vectors[] = '{
    // "abc" test vector - VERIFIED
    '{512'h61626380000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000018, 
      256'hba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad, "abc"},

    // Empty message - VERIFIED
    '{512'h80000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
      256'he3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855, "empty message"},

    // "test" message - VERIFIED  
    '{512'h74657374800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000020,
      256'h9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08, "test"}
  };

  function new(mailbox #(sha256_txn) mb, int n = 1);
    gen2drv = mb;
    num_txns = n;
  endfunction

  task run();
    sha256_txn t;
    
    $display("[GEN] Starting SHA256 test sequence with %0d VERIFIED vectors", test_vectors.size());
    
    // Test each vector
    foreach (test_vectors[i]) begin
      $display("[GEN] Test #%0d: %s", i+1, test_vectors[i].description);
      $display("[GEN] Block: 0x%0128h", test_vectors[i].block);
      $display("[GEN] Expected: 0x%064h", test_vectors[i].expected_digest);
      
      // Wait for ready before starting new test
      #100;
      
      // First transaction: INIT (reset the core)
      t = new();
      t.init = 1;
      t.next = 0;
      t.mode = 1'b1;
      t.block = test_vectors[i].block;
      gen2drv.put(t);
      #100; // Wait for init to complete
      
      // Second transaction: NEXT (process the block)
      t = new();
      t.init = 0;
      t.next = 1;
      t.mode = 1'b1;
      t.block = test_vectors[i].block;
      gen2drv.put(t);
      #200; // Wait for processing
      
      $display("[GEN] Test #%0d done: %0d/%0d completed", i+1, i+1, test_vectors.size());
    end
    
    $display("[GEN] Finished testing %0d vectors", test_vectors.size());
  endtask
endclass

// ----------------------------------------------------------------------
// Driver - FIXED to prevent init/next assertion conflicts
// ----------------------------------------------------------------------
class sha256_drv;
  virtual sha256_if vif;
  mailbox #(sha256_txn) gen2drv;

  function new(virtual sha256_if vif, mailbox #(sha256_txn) mb);
    this.vif = vif;
    this.gen2drv = mb;
  endfunction

  task run();
    sha256_txn t;
    forever begin
      gen2drv.get(t);
      $display("[DRV] Driving transaction");
      t.display("DRV");
      drive(t);
    end
  endtask

  task drive(sha256_txn t);
    // Wait for current operation to complete if any
    if (vif.init || vif.next) begin
      wait(!vif.init && !vif.next);
      #10;
    end
    
    @(posedge vif.clk);
    vif.cb.init  <= t.init;
    vif.cb.next  <= t.next;
    vif.cb.mode  <= t.mode;
    vif.cb.block <= t.block;
    
    // Deassert after one cycle
    @(posedge vif.clk);
    vif.cb.init  <= 0;
    vif.cb.next  <= 0;
    
    // Wait for ready with timeout
    fork
      begin
        wait(vif.ready);
        $display("[DRV] Transaction completed - ready asserted");
      end
      begin
        #2000; // 2000 cycle timeout
        $display("[DRV] WARNING: Ready timeout after 2000 cycles");
      end
    join_any
    disable fork;
  endtask
endclass

// ----------------------------------------------------------------------
// Functional Coverage
// ----------------------------------------------------------------------
class sha256_cov;
  virtual sha256_if vif;
  bit [255:0] expected;
  real coverage_score;

  covergroup cg @(posedge vif.clk);
    option.per_instance = 1;
    option.comment = "SHA256 Functional Coverage";

    cp_cmds : coverpoint {vif.init, vif.next} {
      bins both_zero = {2'b00};
      bins next_only = {2'b01};
      bins init_only = {2'b10};
      illegal_bins both_one  = {2'b11};
    }

    cp_mode : coverpoint vif.mode {
      bins mode0 = {0};
      bins mode1 = {1};
    }

    cp_dvalid : coverpoint vif.digest_valid {
      bins no  = {0};
      bins yes = {1};
    }

    cross_cmds_mode : cross cp_cmds, cp_mode;
  endgroup

  function new(virtual sha256_if vif, bit [255:0] exp);
    this.vif = vif;
    this.expected = exp;
    cg = new();
  endfunction

  function real get_coverage();
    coverage_score = cg.get_inst_coverage();
    return coverage_score;
  endfunction

  function void report();
    real cov = get_coverage();
    $display("[COVERAGE] Functional Coverage = %0.2f%%", cov);
  endfunction
endclass

// ----------------------------------------------------------------------
// Monitor - FIXED to only capture first digest_valid per test
// ----------------------------------------------------------------------
class sha256_mon;
  virtual sha256_if vif;
  mailbox #(sha256_txn) mon2sb;
  sha256_cov cov;
  bit capture_enabled = 1;

  function new(virtual sha256_if vif, mailbox #(sha256_txn) mb);
    this.vif = vif;
    this.mon2sb = mb;
  endfunction

  task run();
    sha256_txn t;
    forever begin
      @(posedge vif.clk);
      if (vif.digest_valid && capture_enabled) begin
        t = new();
        t.digest = vif.digest;
        t.digest_valid = 1'b1;
        mon2sb.put(t);
        $display("[MON] Digest valid: 0x%064h", vif.digest);
        
        // Disable capture until next test to avoid multiple samples
        capture_enabled = 0;
        
        // Re-enable capture after a delay
        fork
          begin
            #500; // Wait before enabling capture for next test
            capture_enabled = 1;
            $display("[MON] Capture re-enabled for next test");
          end
        join_none
      end
    end
  endtask
endclass

// ----------------------------------------------------------------------
// Enhanced Scoreboard
// ----------------------------------------------------------------------
class sha256_sb;
  mailbox #(sha256_txn) mon2sb;
  int test_index = 0;
  int total_tests = 0;
  int passed_tests = 0;
  int failed_tests = 0;
  
  bit [255:0] expected_digests[];
  string test_names[];
  
  function new(mailbox #(sha256_txn) mb);
    mon2sb = mb;
    
    // VERIFIED expected digests (3 tests only)
    expected_digests = '{
      256'hba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad, // "abc"
      256'he3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855, // empty
      256'h9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08  // "test"
    };
    
    test_names = '{
      "abc",
      "empty", 
      "test"
    };
    
    total_tests = expected_digests.size();
  endfunction

  task run();
    sha256_txn t;
    forever begin
      mon2sb.get(t);
      if (test_index < total_tests) begin
        $display("[SB] Checking Test #%0d '%s'", test_index + 1, test_names[test_index]);
        $display("[SB] Expected: 0x%064h", expected_digests[test_index]);
        $display("[SB] Received: 0x%064h", t.digest);
        
        if (t.digest === expected_digests[test_index]) begin
          passed_tests++;
          $display("[SB] ✓ Test #%0d '%s' PASSED", test_index + 1, test_names[test_index]);
        end else begin
          failed_tests++;
          $display("[SB] ✗ Test #%0d '%s' FAILED", test_index + 1, test_names[test_index]);
        end
        test_index++;
        
        if (test_index < total_tests) begin
          $display("[SB] Test #%0d done: %0d/%0d completed", test_index, test_index, total_tests);
        end else begin
          $display("[SB] All tests completed");
          report();
        end
      end
    end
  endtask
  
  function void report();
    $display("\n[REPORT] Total=%0d Passed=%0d Failed=%0d", 
             total_tests, passed_tests, failed_tests);
  endfunction
endclass

// ----------------------------------------------------------------------
// Environment
// ----------------------------------------------------------------------
class sha256_env;
  sha256_gen gen;
  sha256_drv drv;
  sha256_mon mon;
  sha256_sb  sb;
  sha256_cov cov;

  mailbox #(sha256_txn) gen2drv;
  mailbox #(sha256_txn) mon2sb;

  virtual sha256_if vif;

  function new(virtual sha256_if vif);
    this.vif = vif;
    gen2drv = new();
    mon2sb  = new();

    gen = new(gen2drv, 3); // 3 tests only
    drv = new(vif, gen2drv);
    mon = new(vif, mon2sb);
    sb  = new(mon2sb);

    cov = new(vif, 256'h0);
    mon.cov = cov;
  endfunction

  task run();
    $display("[ENV] Starting SHA256 test environment");
    fork
      gen.run();
      drv.run();
      mon.run();
      sb.run();
    join_none
  endtask

  function void report();
    sb.report();
    cov.report();
  endfunction
endclass

// ----------------------------------------------------------------------
// Testbench Top - SIMPLIFIED
// ----------------------------------------------------------------------
module sha256_tb;
  logic clk;
  logic reset_n;

  int init_count = 0;
  int next_count = 0;
  int digest_valid_count = 0;

  sha256_if tb_if(clk, reset_n);

  sha256_core dut (
    .clk(tb_if.clk),
    .reset_n(tb_if.reset_n),
    .init(tb_if.init),
    .next(tb_if.next),
    .mode(tb_if.mode),
    .block(tb_if.block),
    .ready(tb_if.ready),
    .digest(tb_if.digest),
    .digest_valid(tb_if.digest_valid)
  );

  sha256_env env;

  // SIMPLIFIED Assertions - only check critical conditions
  property no_init_next_simultaneous;
    @(posedge clk) disable iff (!reset_n)
    !(tb_if.init && tb_if.next);
  endproperty
  
  assert_no_init_next_simultaneous: assert property (no_init_next_simultaneous)
    else $error("init and next asserted simultaneously");

  // Clock generation
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // Reset generation
  initial begin
    reset_n = 0;
    #100 reset_n = 1;
    $display("[TB] Reset deasserted at %0t", $time);
  end

  // Test sequence
  initial begin
    $display("[TB] Starting SHA256 testbench at %0t", $time);
    wait(reset_n == 1);
    #200; // Wait after reset
    env = new(tb_if);
    env.run();
    #10000; // Allow enough time for all tests
    env.report();
    $display("[TB] Simulation completed at %0t", $time);
    $finish;
  end

  // Simple counters
  always @(posedge clk) begin
    if (tb_if.init) init_count++;
    if (tb_if.next) next_count++;
    if (tb_if.digest_valid) digest_valid_count++;
  end

  // Final summary
  final begin
    $display("\n[VERIFICATION SUMMARY]");
    $display("================================");
    $display("Total Tests Executed : %0d", env.sb.total_tests);
    $display("Tests Passed         : %0d", env.sb.passed_tests);
    $display("Tests Failed         : %0d", env.sb.failed_tests);
    $display("Functional Coverage  : %0.2f%%", env.cov.get_coverage());
    $display("INIT commands        : %0d", init_count);
    $display("NEXT commands        : %0d", next_count);
    $display("DIGEST_VALID events  : %0d", digest_valid_count);
    $display("================================");
  end

  // VCD dump
  initial begin
    $dumpfile("sha256_tb.vcd");
    $dumpvars(0, sha256_tb);
  end
endmodule
