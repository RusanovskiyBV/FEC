//
// Project       : ldpc DVB-S2
// Author        : Shekhalev Denis (des00)
// Workfile      : bertest.sv
// Description   : testbench for DVB-S2 PLS codec for BPSK AWGN
//

`timescale 1ns/1ns

`include "define.vh"
`include "awgn_class.svh"
`include "pkt_class.svh"

module bertest;

  parameter int pTAG_W  = 4;
  parameter int pDAT_W  = 8;

  //------------------------------------------------------------------------------------------------------
  //
  //------------------------------------------------------------------------------------------------------

  logic                    iclk           ;
  logic                    ireset         ;
  logic                    iclkena        ;

  logic            [7 : 0] iNiter         ;
  logic                    ifmode         ;

  //
  // encoder
  logic                    enc__ival      ;
  logic            [6 : 0] enc__idat      ;
  logic     [pTAG_W-1 : 0] enc__itag      ;
  logic                    enc__ordy      ;
  //
  logic                    enc__ireq      ;
  //
  logic                    enc__osop      ;
  logic                    enc__oval      ;
  logic                    enc__oeop      ;
  logic                    enc__odat      ;
  logic     [pTAG_W-1 : 0] enc__otag      ;

  //
  // decoder
  logic                    dec__isop      ;
  logic                    dec__ival      ;
  logic                    dec__ieop      ;
  logic     [pTAG_W-1 : 0] dec__itag      ;
  logic     [pDAT_W-1 : 0] dec__idat      ;
  logic                    dec__ordy      ;

  logic                    dec__oval      ;
  logic            [6 : 0] dec__odat      ;
  logic     [pTAG_W-1 : 0] dec__otag      ;

  //------------------------------------------------------------------------------------------------------
  // encoder
  //------------------------------------------------------------------------------------------------------

  dvb_pls_enc
  #(
    .pTAG_W ( pTAG_W )
  )
  enc
  (
    .iclk    ( iclk      ) ,
    .ireset  ( ireset    ) ,
    .iclkena ( iclkena   ) ,
    //
    .ival    ( enc__ival ) ,
    .idat    ( enc__idat ) ,
    .itag    ( enc__itag ) ,
    .ordy    ( enc__ordy ) ,
    //
    .ireq    ( enc__ireq ) ,
    //
    .osop    ( enc__osop ) ,
    .oval    ( enc__oval ) ,
    .oeop    ( enc__oeop ) ,
    .odat    ( enc__odat ) ,
    .otag    ( enc__otag ) ,
    //
    .owval   ( ) ,
    .owdat   ( )
  );

  assign enc__ireq = 1'b1;

  //------------------------------------------------------------------------------------------------------
  // pi/2 BPSK mapper. Power is 2
  //------------------------------------------------------------------------------------------------------

  const real cBPSK_POW = 2.0;

  logic             mapper__odat_re ;
  logic             mapper__odat_im ;

  bit               bpsk_sop  ;
  bit               bpsk_val  ;
  bit               bpsk_eop  ;
  cmplx_real_dat_t  bpsk      ;

  dvb_pi_by_2_bpsk_mapper
  #(
    .pONE_IS_PLUS ( 1 )
  )
  mapper
  (
    .iclk    ( iclk            ) ,
    .ireset  ( ireset          ) ,
    .iclkena ( iclkena         ) ,
    //
    .isop    ( enc__osop       ) ,
    .ival    ( enc__oval       ) ,
    .ieop    ( enc__oeop       ) ,
    .idat    ( enc__odat       ) ,
    //
    .osop    ( bpsk_sop        ) ,
    .oval    ( bpsk_val        ) ,
    .oeop    ( bpsk_eop        ) ,
    .odat_re ( mapper__odat_re ) ,
    .odat_im ( mapper__odat_im )
  );

  assign bpsk.re = mapper__odat_re ? 1 : -1;
  assign bpsk.im = mapper__odat_im ? 1 : -1;

  //------------------------------------------------------------------------------------------------------
  // awgn channel
  //------------------------------------------------------------------------------------------------------

  awgn_class        awgn = new;

  cmplx_real_dat_t  awgn_ch;
  bit               awgn_sop;
  bit               awgn_eop;
  bit               awgn_val;

  const bit awgn_bypass = 0;

  always_ff @(posedge iclk) begin
    awgn_sop <= bpsk_sop;
    awgn_eop <= bpsk_eop;
    awgn_val <= bpsk_val;
    if (bpsk_val) begin
      awgn_ch <= awgn.add(bpsk, awgn_bypass);
    end
  end

  //------------------------------------------------------------------------------------------------------
  // scale data: set QPSK ref point to -+1024 point and saturate canstellation to -2047 : + 2047 point
  //------------------------------------------------------------------------------------------------------

  localparam int NGC_MAX = 2047;
  localparam int NGC_REF = 1024;

  bit                 ch_sop  ;
  bit                 ch_val  ;
  bit                 ch_eop  ;
  bit signed [15 : 0] ch_dat_re;
  bit signed [15 : 0] ch_dat_im;

  always_comb begin
    ch_sop = awgn_sop;
    ch_val = awgn_val;
    ch_eop = awgn_eop;
    //
    ch_dat_re = $floor(awgn_ch.re * NGC_REF + 0.5);
    ch_dat_im = $floor(awgn_ch.im * NGC_REF + 0.5);
    // saturate
    if (ch_dat_re > NGC_MAX) begin
      ch_dat_re = NGC_MAX;
    end
    else if (ch_dat_re < -NGC_MAX) begin
      ch_dat_re = -NGC_MAX;
    end
    //
    if (ch_dat_im > NGC_MAX) begin
      ch_dat_im = NGC_MAX;
    end
    else if (ch_dat_im < -NGC_MAX) begin
      ch_dat_im = -NGC_MAX;
    end
  end

  //------------------------------------------------------------------------------------------------------
  // pi/2 BPSK demapper
  //------------------------------------------------------------------------------------------------------

  logic signed [pDAT_W-2 : 0] demapper__idat_re ; // -1 bit don't use saturation
  logic signed [pDAT_W-2 : 0] demapper__idat_im ;
  //
  logic                       demapper__osop    ;
  logic                       demapper__oval    ;
  logic                       demapper__oeop    ;
  logic signed [pDAT_W-1 : 0] demapper__odat    ;

  dvb_pi_by_2_bpsk_demapper
  #(
    .pIDAT_W ( pDAT_W-1 ) ,
    .pODAT_W ( pDAT_W   )
  )
  demapper
  (
    .iclk    ( iclk              ) ,
    .ireset  ( ireset            ) ,
    .iclkena ( iclkena           ) ,
    //
    .isop    ( awgn_sop          ) ,
    .ival    ( awgn_val          ) ,
    .ieop    ( awgn_eop          ) ,
    .idat_re ( demapper__idat_re ) ,
    .idat_im ( demapper__idat_im ) ,
    //
    .osop    ( demapper__osop    ) ,
    .oval    ( demapper__oval    ) ,
    .oeop    ( demapper__oeop    ) ,
    .odat    ( demapper__odat    )
  );

  assign demapper__idat_re = ch_dat_re[11 : 12 - (pDAT_W-1)]; // -1 bit
  assign demapper__idat_im = ch_dat_im[11 : 12 - (pDAT_W-1)];

  //------------------------------------------------------------------------------------------------------
  //
  //------------------------------------------------------------------------------------------------------

  assign dec__isop = demapper__osop;
  assign dec__ival = demapper__oval;
  assign dec__ieop = demapper__oeop;
  assign dec__idat = demapper__odat;

  //------------------------------------------------------------------------------------------------------
  // decoder
  //------------------------------------------------------------------------------------------------------

  dvb_pls_dec
  #(
    .pDAT_W ( pDAT_W ) ,
    .pTAG_W ( pTAG_W )
  )
  uut
  (
    .iclk    ( iclk      ) ,
    .ireset  ( ireset    ) ,
    .iclkena ( iclkena   ) ,
    //
    .isop    ( dec__isop ) ,
    .ival    ( dec__ival ) ,
    .ieop    ( dec__ieop ) ,
    .idat    ( dec__idat ) ,
    .itag    ( dec__itag ) ,
    .ordy    ( dec__ordy ) ,
    //
    .oval    ( dec__oval ) ,
    .odat    ( dec__odat ) ,
    .otag    ( dec__otag )
  );

  //------------------------------------------------------------------------------------------------------
  //
  //------------------------------------------------------------------------------------------------------

  initial begin
    iclk <= 1'b0;
    #5ns forever #5ns iclk = ~iclk;
  end

  initial begin
    ireset = 1'b1;
    repeat (2) @(negedge iclk);
    ireset = 1'b0;
  end

  assign iclkena  = 1'b1;

  //------------------------------------------------------------------------------------------------------
  //
  //------------------------------------------------------------------------------------------------------

  const int B = 1e5;

  int Npkt;

  real SNR [] = '{-5.0, -4.5, -4.0, -3.5, -3.0, -2.5, -2.0, -1.5, -1.0};

  //------------------------------------------------------------------------------------------------------
  // data generator
  //------------------------------------------------------------------------------------------------------

  event test_done;

  pkt_class #(1) code_queue [$];

  initial begin
    real coderate;
    int  data_bit_length;

    pkt_class #(1) code;
    //
    code_queue.delete();
    //
    enc__ival <= '0;
    enc__idat <= '0;
    //
    awgn.init_SNR(.SNR(SNR[0]), .Ps(cBPSK_POW), .seed(0));
    //
    @(posedge iclk iff !ireset);
    //
    data_bit_length = 7;
    coderate        = 7*1.0/64;

    Npkt = B/data_bit_length;

    foreach (SNR[k]) begin
      repeat (10) @(posedge iclk);
      awgn.init_SNR(.SNR(SNR[k]), .Ps(cBPSK_POW), .seed(2));
      awgn.log();
      void'(awgn.add('{0, 0}, 0));
      repeat (10) @(posedge iclk);
      //
      @(posedge iclk iff enc__ordy);
      //
      for (int n = 0; n < Npkt; n++) begin

        // generate data
        code = new(data_bit_length);
        void'(code.randomize());
        //
        // drive data
        enc__ival <= 1'b1;
        for (int i = 0; i < data_bit_length; i++) begin
          enc__idat[i] <= code.dat[i];
        end
        @(posedge iclk iff enc__ordy);
        enc__ival <= 1'b0;
        // save reference
        code_queue.push_back(code);
        //
        @(posedge iclk iff enc__ordy);
        repeat (16) @(posedge iclk);  // true hack
        @(posedge iclk iff dec__ordy);
        if ((n % 128) == 0) begin
          $display("sent %0d packets", n);
        end
      end
      //
      @(test_done);
    end
  end

  //------------------------------------------------------------------------------------------------------
  // data reciver & checker
  //------------------------------------------------------------------------------------------------------

  int numerr      [];

  initial begin
    real coderate;
    int  data_bit_length;
    int  code_bit_length;
    //
    pkt_class #(1) decode;
    pkt_class #(1) code;
    //
    int addr;
    int err;
    int n;
    string s;
    //
    numerr      = new[SNR.size()];
    foreach (numerr[k]) begin
      numerr[k]     = 0;
    end
    //
    //
    @(posedge iclk iff !ireset);
    repeat (2) @(posedge iclk);
    //
    data_bit_length = 7;
    code_bit_length = 64;
    coderate        = 7*1.0/64;
    //
    foreach (SNR[k]) begin
      n = 0;
      //
      do begin
        @(posedge iclk);
        if (dec__oval) begin
          decode = new(data_bit_length);
          for (int i = 0; i < data_bit_length; i++) begin
            decode.dat[i] = dec__odat[i];
          end
          //
          n++;
          code    = code_queue.pop_front();

          err     = code.do_compare(decode);
          //
          numerr[k]     += err;
          //
          if ((n % 128) == 0) begin
            $display("%0t decode done %0d. err = %0d", $time, n, numerr[k]);
          end
        end
      end
      while (n < Npkt);
      -> test_done;

      // intermediate results
      $display("decode SNR = %0.2f done. ber = %0.2e", SNR[k], numerr[k]*1.0/(Npkt*data_bit_length));
    end
    // final results
    for (int k = 0; k < SNR.size(); k++) begin
      $display("bits %0d SNR = %0.2f : ber = %0.2e", Npkt*data_bit_length, SNR[k], numerr[k]*1.0/(Npkt*data_bit_length));
    end
    //
    #1us;
    $display("test done %0t", $time);
    $stop;
  end

endmodule

