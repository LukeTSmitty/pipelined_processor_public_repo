module cpu
import rv32i_types::*;
(
    input   logic           clk,
    input   logic           rst,

    output  logic   [31:0]  imem_addr,
    output  logic   [3:0]   imem_rmask,
    input   logic   [31:0]  imem_rdata,
    input   logic           imem_resp,

    output  logic   [31:0]  dmem_addr,
    output  logic   [3:0]   dmem_rmask,
    output  logic   [3:0]   dmem_wmask,
    input   logic   [31:0]  dmem_rdata,
    output  logic   [31:0]  dmem_wdata,
    input   logic           dmem_resp
);
    // Note on stalls:
    // if imem stalls, the rest of the pipeline can move forward
    // if dmem stalls, everything before mem stage must stall

    if_id_stage_reg_t   ifid_reg;
    if_id_stage_reg_t   ifid_reg_next;
    id_ex_stage_reg_t   idex_reg;
    id_ex_stage_reg_t   idex_reg_next;
    ex_mm_stage_reg_t   exmm_reg;
    ex_mm_stage_reg_t   exmm_reg_next;
    mm_wb_stage_reg_t   mmwb_reg;
    mm_wb_stage_reg_t   mmwb_reg_next;

    logic   [4:0]   rs1_s;
    logic   [4:0]   rs2_s;
    logic   [31:0]  rs1_v;
    logic   [31:0]  rs2_v;
    logic   [31:0]  rd_v;  
    logic   [4:0]   rd_s;

    logic   [4:0]   rd_s_mm;
    logic   [31:0]  rd_v_mm;

    logic           regf_we;
    logic           regf_we_mm;
    logic   [63:0]  order;

    logic           dmem_stall;
    logic           global_stall;  

    logic           control_taken;
    logic   [31:0]  target_pc;

    logic [4:0]     ifid_rs1; //rs1_s from decode
    logic [4:0]     ifid_rs2;

    assign global_stall = (dmem_stall || !imem_resp) ? 1'b1: 1'b0; 

    logic fetch_decode_stall;
    assign fetch_decode_stall = ((idex_reg.opcode == op_b_store|| idex_reg.opcode == op_b_load ) && (ifid_reg.inst[6:0] == op_b_store|| ifid_reg.inst[6:0] == op_b_load )) ||
                                    (ifid_reg.inst[19:15] == idex_reg.rd_s && idex_reg.opcode == op_b_load) || (ifid_reg.inst[24:20] == idex_reg.rd_s && idex_reg.opcode == op_b_load);
    
    // assign fetch_decode_stall = idex_reg.valid && idex_reg.opcode == op_b_load && idex_reg.rd_s != 5'd0 && ((rs1_s == idex_reg.rd_s) || (rs2_s == idex_reg.rd_s));
    
    fetch fetch_blk (
        .clk(clk),
        .rst(rst),
        .imem_rdata(imem_rdata),
        .global_stall(global_stall),
        .imem_addr(imem_addr),
        .imem_rmask(imem_rmask),
        .ifid_reg_next(ifid_reg_next),
        .fetch_decode_stall(fetch_decode_stall),
        .control_taken(control_taken),
        .target_pc(target_pc)
    );

    decode decode_blk (
        .ifid_reg(ifid_reg),
        .idex_reg_next(idex_reg_next),
        .rs1_v(rs1_v),
        .rs2_v(rs2_v),
        .rs1_s(rs1_s),
        .rs2_s(rs2_s),
        .control_taken(control_taken)
    );
    // define register file
    regfile regfile(
        .clk(clk),
        .rst(rst),
        .rs1_s(rs1_s),
        .rs2_s(rs2_s),
        .rs1_v(rs1_v),
        .rs2_v(rs2_v),
        //TODO: Connect rd_v from writeback stage
        .rd_v(rd_v),
        .rd_s(rd_s),
        .regf_we(regf_we)
    );
    // pass rs1_s output from decode and rs2_s
    execute execute_blk(
        .idex_reg(idex_reg),
        .exmm_reg_next(exmm_reg_next),
        .dmem_addr(dmem_addr),
        .dmem_rmask(dmem_rmask),
        .dmem_wmask(dmem_wmask),
        .dmem_wdata(dmem_wdata),
        .target_pc(target_pc),
        .control_taken(control_taken),
        
        .rd_s_mm(rd_s_mm),
        .rd_s_wb(rd_s),
        .rd_v_mm(rd_v_mm),
        .rd_v_wb(rd_v),
        .regf_we_mm(regf_we_mm),
        .regf_we_wb(regf_we)
    );

    memory memory_blk(
        .clk(clk),
        .rst(rst),
        .exmm_reg(exmm_reg),
        .mmwb_reg_next(mmwb_reg_next),
        .dmem_resp(dmem_resp),
        .dmem_rdata(dmem_rdata),
        .dmem_stall(dmem_stall),
        .global_stall(global_stall),

        .rd_s_mm(rd_s_mm),
        .rd_v_mm(rd_v_mm),
        .regf_we_mm(regf_we_mm)
    );

    writeback writeback_blk(
        .mmwb_reg(mmwb_reg),
        .rd_v(rd_v),
        .regf_we(regf_we),
        .rd_s(rd_s)
    );


    always_ff @(posedge clk) begin
        if (rst) begin
            // reset for fetch register
            ifid_reg <= '0;
            idex_reg <= '0;
            exmm_reg <= '0;
            mmwb_reg <= '0;
            //spike
            order <= '0;
        end else if (!global_stall && fetch_decode_stall) begin   // new pc data valid is current bottleneck
            idex_reg <= '0;
            exmm_reg <= exmm_reg_next;
            mmwb_reg <= mmwb_reg_next;
        end
        else if (!global_stall) begin   // new pc data valid is current bottleneck
            ifid_reg <= ifid_reg_next;
            idex_reg <= idex_reg_next;
            exmm_reg <= exmm_reg_next;
            mmwb_reg <= mmwb_reg_next;
        end
        //edge case handling: load use hazard
        if (!global_stall && mmwb_reg.valid)begin
            order <= order + 1;
        end

    end
            logic           monitor_valid;
            logic   [63:0]  monitor_order;
            logic   [31:0]  monitor_inst;
            logic   [4:0]   monitor_rs1_addr;
            logic   [4:0]   monitor_rs2_addr;
            logic   [31:0]  monitor_rs1_rdata;
            logic   [31:0]  monitor_rs2_rdata;
            logic           monitor_regf_we;
            logic   [4:0]   monitor_rd_addr;
            logic   [31:0]  monitor_rd_wdata;
            logic   [31:0]  monitor_pc_rdata;
            logic   [31:0]  monitor_pc_wdata;
            logic   [31:0]  monitor_mem_addr;
            logic   [3:0]   monitor_mem_rmask;
            logic   [3:0]   monitor_mem_wmask;
            logic   [31:0]  monitor_mem_rdata;
            logic   [31:0]  monitor_mem_wdata;

always_comb begin
    monitor_valid     = '0;
    monitor_order     = order;
    monitor_inst      = mmwb_reg.inst;
    monitor_rs1_addr  = mmwb_reg.rs1_s;
    monitor_rs2_addr  = mmwb_reg.rs2_s;
    monitor_rs1_rdata = mmwb_reg.rs1_v;
    monitor_rs2_rdata = mmwb_reg.rs2_v;
    monitor_rd_addr   = regf_we ? rd_s : 5'd0;
    monitor_rd_wdata  = rd_v;
    monitor_pc_rdata  = mmwb_reg.pc;
    monitor_pc_wdata  = mmwb_reg.pc_next;
    monitor_mem_addr  = mmwb_reg.mem_addr;
    monitor_mem_rmask = mmwb_reg.mem_rmask;
    monitor_mem_wmask = mmwb_reg.mem_wmask;
    monitor_mem_rdata = mmwb_reg.mem_rdata;
    monitor_mem_wdata = mmwb_reg.mem_wdata;
    if(!global_stall) begin
        monitor_valid     = mmwb_reg.valid;
    end
end
endmodule : cpu
