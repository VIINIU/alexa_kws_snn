`timescale 1ns / 1ps

// ==========================================================
// Pipelined LIF 뉴런 모듈 (Ver 2.0 - Timing Fix)
// - 기능: 3-cycle FSM을 도입하여 WNS(타이밍) 문제 해결
// - 제어: 'lif_start' 펄스를 받으면 'lif_done' 펄스를 반환
// ==========================================================
module lif_neuron
#(
    parameter ACC_WIDTH = 32,
    parameter  [15:0] BETA_Q0_16 = 16'd62259, 
    parameter signed [15:0] THRESHOLD_Q5_11 = 16'h0400 
)
(
    input clk,
    input rst_n,
    
    // --- 제어 신호 (수정) ---
    input lif_start, // 💡 'mac_done' 대신 'lif_start' 펄스
    output reg lif_done,   // 💡 연산 완료 펄스
    
    input signed [(ACC_WIDTH-1):0] cur_in, // MAC의 'cur_out' (Q22.9)
    input signed [(ACC_WIDTH):0] mem_in,   // 상위 모듈(BRAM)에서 오는 '현재 전위' (Q23.9)
    output reg signed [(ACC_WIDTH):0] mem_out,  // BRAM에 저장될 '다음 전위' (Q23.9)
    output reg spk_out             // 최종 스파이크 출력 (1-bit)
);

    // --- 내부 Q-Format 상수 (동일) ---
    localparam MEM_WIDTH = ACC_WIDTH + 1;
    localparam FRAC_BITS_IN = 9;
    localparam FRAC_BITS_BETA = 16;
    localparam FRAC_BITS_THRESH = 11;
    
    // --- THRESHOLD 정렬 (동일) ---
    localparam signed [MEM_WIDTH-1:0] THRESHOLD_ALIGNED = {{(MEM_WIDTH-16){THRESHOLD_Q5_11[15]}}, (THRESHOLD_Q5_11 >> (FRAC_BITS_THRESH - FRAC_BITS_IN))};

    // --- FSM 상태 ---
    localparam STATE_IDLE      = 2'd0;
    localparam STATE_LEAK      = 2'd1; // 1. Leak ( 곱셈 )
    localparam STATE_INTEGRATE = 2'd2; // 2. Integrate ( 덧셈/쉬프트 )
    localparam STATE_FIRE      = 2'd3; // 3. Fire ( 비교/결정 )

    reg [1:0] state, next_state;

    // --- 파이프라인 레지스터 ---
    // 💡 입력/중간값을 클럭마다 래칭(latch)하여 타이밍 확보
    reg signed [(MEM_WIDTH-1):0] cur_in_reg;
    reg signed [(MEM_WIDTH-1):0] mem_in_reg;
    reg signed [(MEM_WIDTH*2)-1:0] mem_decay_intermediate_reg; // 66비트
    reg signed [MEM_WIDTH-1:0] mem_next_reg;

    // --- 연산 Wire (조합논리) ---
    wire signed [MEM_WIDTH-1:0] beta_extended = {{(MEM_WIDTH-16){1'b0}}, BETA_Q0_16};
    wire signed [(MEM_WIDTH*2)-1:0] round_const = (1 << (FRAC_BITS_BETA - 1));
    
    // 💡 1. Leak (곱셈) : 1클럭 소요
    wire signed [(MEM_WIDTH*2)-1:0] mem_decay_intermediate_wire = $signed(mem_in_reg) * $signed(beta_extended);
    
    // 💡 2. Shift (누수) : 1클럭 소요
    wire signed [MEM_WIDTH-1:0] mem_decay_wire = (mem_decay_intermediate_reg + round_const) >> FRAC_BITS_BETA;
    
    // 💡 3. Integrate (덧셈) : 1클럭 소요
    wire signed [MEM_WIDTH-1:0] mem_next_wire = mem_decay_wire + cur_in_reg;

    // ==================
    // 1. 순차 로직 (FSM + Pipeline Registers)
    // ==================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            cur_in_reg <= 0;
            mem_in_reg <= 0;
            mem_decay_intermediate_reg <= 0;
            mem_next_reg <= 0;
        end else begin
            state <= next_state;
            
            // FSM 상태에 따라 파이프라인 래칭
            if (state == STATE_IDLE && next_state == STATE_LEAK) begin
                // Latch inputs
                mem_in_reg <= mem_in;
                cur_in_reg <= {{1{cur_in[ACC_WIDTH-1]}}, cur_in}; // 33비트로 확장해서 래칭
            end
            
            if (state == STATE_LEAK) begin
                // Latch multiplication result
                mem_decay_intermediate_reg <= mem_decay_intermediate_wire;
            end
            
            if (state == STATE_INTEGRATE) begin
                // Latch addition result
                mem_next_reg <= mem_next_wire;
            end
        end
    end

    // ==================
    // 2. 조합 로직 (FSM)
    // ==================
    always @(*) begin
        // 기본값
        next_state = state;
        lif_done = 1'b0;
        spk_out = 1'b0;
        mem_out = mem_in_reg; // 💡 기본값 (바뀔 예정)

        case (state)
            STATE_IDLE: begin
                if (lif_start) begin
                    next_state = STATE_LEAK;
                end
            end
            
            STATE_LEAK: begin
                // (곱셈이 mem_decay_intermediate_wire에서 진행 중...)
                // (다음 클럭에 래칭될 것임)
                next_state = STATE_INTEGRATE;
            end
            
            STATE_INTEGRATE: begin
                // (덧셈/쉬프트가 mem_next_wire에서 진행 중...)
                // (다음 클럭에 래칭될 것임)
                next_state = STATE_FIRE;
            end
            
            STATE_FIRE: begin
                // (이제 mem_next_reg에 최종 값이 들어있음)
                
                // 3단계: 임계값 비교
                if (mem_next_reg > THRESHOLD_ALIGNED) begin
                    spk_out = 1'b1;
                    mem_out = mem_next_reg - THRESHOLD_ALIGNED; // Reset-by-Subtraction
                end else begin
                    spk_out = 1'b0;
                    mem_out = mem_next_reg; // 전위 업데이트
                end
                
                lif_done = 1'b1; // 1-cycle 펄스
                next_state = STATE_IDLE;
            end
            
            default: begin
                next_state = STATE_IDLE;
            end
        endcase
    end
endmodule