`timescale 1ns / 1ps

module mac_unit
#(
    parameter INPUT_DIM    = 20,
    parameter W_ROM_WIDTH  = 16,
    parameter ACC_WIDTH    = 32,
    parameter J_WIDTH        = 7,
    parameter W_ADDR_WIDTH = 12,
    parameter B_ADDR_WIDTH = 7
)
(
    input                      clk,
    input                      rst_n,
    input                      calc_start,
    input      [J_WIDTH-1:0]   neuron_idx_in,
    input      [(INPUT_DIM-1):0] spike_vector_in,
    input signed [(W_ROM_WIDTH-1):0] rom_w_data_in,
    input signed [(W_ROM_WIDTH-1):0] rom_b_data_in,
    
    output reg                   calc_done,
    output reg                   busy,
    output reg signed [(ACC_WIDTH-1):0] cur_out,
    output reg [W_ADDR_WIDTH-1:0] rom_w_addr_out,
    output reg [B_ADDR_WIDTH-1:0] rom_b_addr_out
);

    localparam STATE_IDLE       = 3'd0;
    localparam STATE_MAC_READ   = 3'd1; 
    localparam STATE_MAC_WAIT   = 3'd2; 
    localparam STATE_MAC_ACCUM  = 3'd3; 
    localparam STATE_BIAS_READ  = 3'd4; 
    localparam STATE_BIAS_WAIT  = 3'd5; 
    localparam STATE_BIAS_ADD   = 3'd6; 
    localparam STATE_DONE       = 3'd7; 

    reg [2:0]                  state, next_state;
    reg [7:0]                  i_count, next_i_count;
    reg signed [(ACC_WIDTH-1):0] acc_reg, next_acc_reg;
    reg [(INPUT_DIM-1):0]      spike_vector_reg;
    reg [J_WIDTH-1:0]          neuron_idx_reg;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= STATE_IDLE;
            i_count  <= 0;
            acc_reg  <= 0;
            spike_vector_reg <= 0;
            neuron_idx_reg   <= 0;
        end else begin
            state    <= next_state;
            i_count  <= next_i_count;
            acc_reg  <= next_acc_reg;
            
            // IDLE -> MAC_READ로 갈 때 (calc_start) 값 래칭
            if (state == STATE_IDLE && next_state == STATE_MAC_READ) begin
                spike_vector_reg <= spike_vector_in;
                neuron_idx_reg   <= neuron_idx_in;
            end
        end
    end

    always @(*) begin
        // 기본값 (Latch 방지)
        next_state   = state;
        next_i_count = i_count;
        next_acc_reg = acc_reg;
        
        // 출력 포트 기본값
        calc_done      = 1'b0;
        busy           = 1'b1; // IDLE일 때만 0
        cur_out        = acc_reg;
        rom_w_addr_out = 0;
        rom_b_addr_out = 0;

        case (state)
            STATE_IDLE: begin
                busy = 1'b0;
                
                if (calc_start) begin
                    next_acc_reg = 0;
                    next_i_count = 0;
                    next_state   = STATE_MAC_READ;
                end
            end
            
            // 💡 [버그 1 수정]
            STATE_MAC_READ: begin
                // W ROM 주소 계산 및 설정
                rom_w_addr_out = (neuron_idx_reg * INPUT_DIM) + i_count;
                next_state     = STATE_MAC_WAIT; // 💡 다음 클럭에 바로 누적하지 않음
            end
            
            // 💡 [버그 1 수정]
            STATE_MAC_WAIT: begin
                // W ROM이 데이터를 가져오는 1클럭 동안 대기
                rom_w_addr_out = (neuron_idx_reg * INPUT_DIM) + i_count; 
                next_state = STATE_MAC_ACCUM;

            end
            
            STATE_MAC_ACCUM: begin
                
                if (spike_vector_reg[i_count] == 1'b1) begin
                    next_acc_reg = acc_reg + $signed(rom_w_data_in);
                end
                
                if (i_count == (INPUT_DIM - 1)) begin
                    // 모든 x[i] (i=0~19) 연산 완료
                    next_state = STATE_BIAS_READ;
                end else begin
                    // 다음 i
                    next_i_count = i_count + 1;
                    next_state   = STATE_MAC_READ; 
                end
            end
            
            
            STATE_BIAS_READ: begin
                
                rom_b_addr_out = neuron_idx_reg;
                next_state     = STATE_BIAS_WAIT; 
            end
            
            STATE_BIAS_WAIT: begin
                rom_b_addr_out = neuron_idx_reg;
                next_state = STATE_BIAS_ADD;
            end
            
            STATE_BIAS_ADD: begin
                
                next_acc_reg = acc_reg + $signed(rom_b_data_in);
                next_state   = STATE_DONE;
            end
            
            STATE_DONE: begin
                cur_out   = next_acc_reg;
                calc_done = 1'b1;
                next_state = STATE_IDLE;
            end
            
            default: begin
                next_state = STATE_IDLE;
            end
        endcase
    end

endmodule