// ==========================================================
// snn_core.v
// (최상위 "지휘자" FSM 모듈)
// - 기능: 1. start_inference 신호를 받으면 3000 타임스텝 시작
//         2. 매 타임스텝마다 L1 -> L2 -> L3 순서로 snn_layer 호출
//         3. L3의 최종 2-bit 스파이크를 누적
//         4. 3000스텝 후, 누적값 비교하여 LED 출력
// ==========================================================

// ==========================================================
// snn_core.v (Ver 4.0 - Latch-Free FSM)
// ==========================================================
`timescale 1ns / 1ps

module snn_core 
(
    input clk,
    input rst_n,
    input start_inference,
    input [19:0] uart_spike_vector,
    output reg led_out,
    output [3:0] debug_t_state,
    output [11:0] debug_t_count,
    output [15:0] debug_spk_alexa,
    output [15:0] debug_spk_neg
);
    //localparam MEM_PATH = "C:/vini_dir/kws_snn/kws_snn.srcs/sources_1/new/mem_files/";
    localparam T_MAX = 3000;

    // ===================================
    // 1. FSM 상태 (동일)
    // ===================================
    localparam T_STATE_IDLE      = 4'd0;
    localparam T_STATE_INIT      = 4'd1;
    localparam T_STATE_L1_START  = 4'd2;
    localparam T_STATE_L1_WAIT   = 4'd3;
    localparam T_STATE_L2_START  = 4'd4;
    localparam T_STATE_L2_WAIT   = 4'd5;
    localparam T_STATE_L3_START  = 4'd6;
    localparam T_STATE_L3_WAIT   = 4'd7;
    localparam T_STATE_ACCUM     = 4'd8;
    localparam T_STATE_CHECK_T   = 4'd9;
    localparam T_STATE_DECIDE    = 4'd10;

    // ===================================
    // 2. 모든 레지스터 선언
    // ===================================
    reg [3:0] t_state, t_next_state;
    reg [11:0] t_count, t_next_count;
    reg [15:0] total_spk_neg, next_total_spk_neg;
    reg [15:0] total_spk_alexa, next_total_spk_alexa;
    reg [19:0] t_step_spike_vector, next_t_step_spike_vector; // 🚨 래칭용

    wire [127:0] spk1_buffer, spk2_buffer;
    wire [1:0]   spk3_buffer;
    wire l1_done, l2_done, l3_done;
    reg l1_start, l2_start, l3_start; // 펄스 신호는 조합논리로
    // 💡 [추가] BRAM 리셋 신호
    wire l1_bram_clear, l2_bram_clear, l3_bram_clear;
    // ===================================
    // 3. 레이어 인스턴스화 (동일)
    // ===================================
    snn_layer #(
        .INPUT_DIM(20), .NUM_NEURONS(128), .J_WIDTH(7), 
        .W_ADDR_WIDTH(12), .B_ADDR_WIDTH(7), 
        .W_MEM_FILE("W1.mem"), 
        .B_MEM_FILE("B1.mem"),
        .LAYER_ID(1) // 💡 [표지 설치]
        )
    U_SNN_L1 (.clk(clk), .rst_n(rst_n),
    .bram_clear(l1_bram_clear), // 💡 연결
     .layer_start(l1_start), 
     .layer_done(l1_done), 
     .spike_vector_in(t_step_spike_vector), 
     .spike_buffer_out(spk1_buffer));

    snn_layer #(.INPUT_DIM(128), 
    .NUM_NEURONS(128), 
    .J_WIDTH(7), 
    .W_ADDR_WIDTH(14), 
    .B_ADDR_WIDTH(7), 
    .W_MEM_FILE("W2.mem"), 
    .B_MEM_FILE("B2.mem"),
    .LAYER_ID(2)  
    )
    U_SNN_L2 (.clk(clk), 
    .rst_n(rst_n), 
    .bram_clear(l2_bram_clear), 
    .layer_start(l2_start), 
    .layer_done(l2_done), 
    .spike_vector_in(spk1_buffer), 
    .spike_buffer_out(spk2_buffer));

    snn_layer #(.INPUT_DIM(128), 
    .NUM_NEURONS(2), 
    .J_WIDTH(1), 
    .W_ADDR_WIDTH(8), 
    .B_ADDR_WIDTH(1), 
    .W_MEM_FILE("W3.mem"), 
    .B_MEM_FILE("B3.mem"),
    .LAYER_ID(3)
    )
    U_SNN_L3 (.clk(clk), 
    .rst_n(rst_n), 
    .bram_clear(l3_bram_clear), 
    .layer_start(l3_start), 
    .layer_done(l3_done), 
    .spike_vector_in(spk2_buffer), 
    .spike_buffer_out(spk3_buffer));

    // ===================================
    // 4. "지휘자" FSM - 순차 로직 (Sequential)
    // ===================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            t_state               <= T_STATE_IDLE;
            t_count               <= 0; 
            total_spk_neg         <= 0;
            total_spk_alexa       <= 0;
            t_step_spike_vector   <= 0;
        end else begin
            t_state               <= t_next_state;
            t_count               <= t_next_count;
            total_spk_neg         <= next_total_spk_neg;
            total_spk_alexa       <= next_total_spk_alexa;
            t_step_spike_vector   <= next_t_step_spike_vector;
        end
    end

    // ===================================
    // 5. "지휘자" FSM - 조합 로직 (Combinational)
    // ===================================
    assign l1_bram_clear = (t_state == T_STATE_INIT);
    assign l2_bram_clear = (t_state == T_STATE_INIT);
    assign l3_bram_clear = (t_state == T_STATE_INIT);
    always @(*) begin
        // 기본값: 현재 값 유지 (Latch 방지)
        t_next_state           = t_state;
        t_next_count           = t_count;
        next_total_spk_neg     = total_spk_neg;
        next_total_spk_alexa   = total_spk_alexa;
        next_t_step_spike_vector = t_step_spike_vector; // 👈 기본은 유지

        // 출력 포트 기본값
        l1_start = 1'b0;
        l2_start = 1'b0;
        l3_start = 1'b0;
        led_out  = (total_spk_alexa > total_spk_neg); // 👈 최종값 미리 계산

        case (t_state)
            T_STATE_IDLE: begin
                if (start_inference) begin
                    t_next_state = T_STATE_INIT;
                end
            end
            
            T_STATE_INIT: begin
                t_next_count           = 0;
                next_total_spk_neg     = 0;
                next_total_spk_alexa   = 0;
                t_next_state           = T_STATE_L1_START;
            end
            
            T_STATE_L1_START: begin
                // 💡 [수정!] 조합논리가 아닌, '다음 클럭'에 래칭되도록 예약
                next_t_step_spike_vector = uart_spike_vector;
                l1_start       = 1'b1;
                t_next_state = T_STATE_L1_WAIT;
                if (t_count == 0) begin
                    $display("--- 🐞 [VERILOG T=0] Input Spike Vector: %h ---", uart_spike_vector);
                end
                if (t_count == 1) begin
                    $display("--- 🐞 [VERILOG T=1] Input Spike Vector: %h ---", uart_spike_vector);
                end
            end
            
            T_STATE_L1_WAIT: begin
                if (l1_done) t_next_state = T_STATE_L2_START;
            end
            
            T_STATE_L2_START: begin
                l2_start       = 1'b1;
                t_next_state = T_STATE_L2_WAIT;
            end
            
            T_STATE_L2_WAIT: begin
                if (l2_done) t_next_state = T_STATE_L3_START;
            end
            
            T_STATE_L3_START: begin
                l3_start       = 1'b1;
                t_next_state = T_STATE_L3_WAIT;
            end
            
            T_STATE_L3_WAIT: begin
                if (l3_done) begin
                    // 💡 [표지 설치 1]
                    // L3가 끝나면, 누적(ACCUM) 전에 
                    // L1, L2, L3의 결과 버퍼를 $display로 출력
                    
                    // t_count가 10 미만일 때만 출력 (로그 폭발 방지)\
                    // 💡 [수정] T=0 일때만 확인하도록 t_count < 1로 변경
                    if (t_count < 3000) begin
                        $display("--- [T=%0d] ---", t_count);
                        if (spk1_buffer == 0)
                            $display("  L1_spk_buf: 0");
                        else if (spk1_buffer == 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
                            $display("  L1_spk_buf: All 1s");
                        else
                            $display("  L1_spk_buf: Mixed");
                            
                        if (spk2_buffer == 0)
                            $display("  L2_spk_buf: 0");
                        else if (spk2_buffer == 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
                            $display("  L2_spk_buf: All 1s");
                        else
                            $display("  L2_spk_buf: Mixed");

                        $display("  L3_spk_buf: %b", spk3_buffer); 
                    end
                    
                    t_next_state = T_STATE_ACCUM;
                end
            end
            
            T_STATE_ACCUM: begin
                // 💡 [수정!] 조합논리가 아닌, '다음 클럭'에 덧셈되도록 예약
                if (spk3_buffer[0]) next_total_spk_neg   = total_spk_neg + 1;
                if (spk3_buffer[1]) next_total_spk_alexa = total_spk_alexa + 1;
                t_next_state = T_STATE_CHECK_T;
            end
            
            T_STATE_CHECK_T: begin
                if (t_count == (T_MAX - 1)) begin
                    t_next_state = T_STATE_DECIDE;
                end else begin
                    t_next_count = t_count + 1; // 👈 다음 카운트 예약
                    t_next_state = T_STATE_L1_START;
                end
            end
            
            T_STATE_DECIDE: begin
                // led_out은 이미 계산됨 (조합논리)
                t_next_state = T_STATE_IDLE;
            end
            
            default: begin
                t_next_state = T_STATE_IDLE;
            end
        endcase
    end
    assign debug_t_state = t_state;
    assign debug_t_count = t_count;
    assign debug_spk_alexa = total_spk_alexa;
    assign debug_spk_neg   = total_spk_neg;
endmodule