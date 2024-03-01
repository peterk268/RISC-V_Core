\m4_TLV_version 1d: tl-x.org
\SV
   // This code can be found in: https://github.com/stevehoover/LF-Building-a-RISC-V-CPU-Core/risc-v_shell.tlv
   
   m4_include_lib(['https://raw.githubusercontent.com/stevehoover/LF-Building-a-RISC-V-CPU-Core/main/lib/risc-v_shell_lib.tlv'])

   m4_test_prog()

   
\SV
   m4_makerchip_module   // (Expanded in Nav-TLV pane.)
   /* verilator lint_on WIDTH */
\TLV
   
   $reset = *reset;
   
   // Counter
   $next_pc[31:0] = $reset ? 32'b0 :
                    ($taken_br || $is_jal) ? $br_tgt_pc[31:0] :
                    $is_jalr ? $jalr_tgt_pc[31:0] :
                    $pc + 32'b100;
                    // added logic from branch and jump
   $pc[31:0] = >>1$next_pc;
   
   `READONLY_MEM($pc, $$instr[31:0]);
   
   // Instruction categorizing
   $is_u_instr = $instr[6:2] ==? 5'b0x101;
   $is_i_instr = $instr[6:2] ==? 5'b0000x ||
                 $instr[6:2] ==? 5'b001x0 ||
                 $instr[6:2] == 5'b11001;
   $is_r_instr = $instr[6:2] == 5'b01011 ||
                 $instr[6:2] ==? 5'b011x0 ||
                 $instr[6:2] == 5'b10100;
   $is_s_instr = $instr[6:2] ==? 5'b0100x;
   $is_b_instr = $instr[6:2] == 5'b11000;
   $is_j_instr = $instr[6:2] == 5'b11011;
   
   // Decode Logic: Instruction Fields
   $funct3[2:0] = $instr[14:12];
   $rs1[4:0] = $instr[19:15];
   $rs2[4:0] = $instr[24:20];
   $rd[4:0] = $instr[11:7];
   $opcode[6:0] = $instr[6:0];
   
   $funct3_valid = $is_r_instr || $is_i_instr || $is_s_instr || $is_b_instr;
   $rs1_valid = $is_r_instr || $is_i_instr || $is_s_instr || $is_b_instr;
   $rs2_valid = $is_r_instr || $is_s_instr || $is_b_instr;
   $rd_valid = $is_r_instr || $is_i_instr || $is_u_instr || $is_j_instr;
   $imm_valid =  $is_i_instr || $is_s_instr || $is_b_instr || $is_u_instr || $is_j_instr;
   
   `BOGUS_USE($rd $rd_valid $rs1 $rs1_valid $rs2 $rs2_valid $imm $imm_valid);
   
   $imm[31:0] = $is_i_instr ? {  {21{$instr[31]}},  $instr[30:20]  } :
                $is_s_instr ? {  {21{$instr[31]}},  $instr[30:25],  $instr[11:8],  $instr[7]  } :
                $is_b_instr ? {  {20{$instr[31]}},  $instr[7],  $instr[30:25],  $instr[11:8],  1'b0  } :
                $is_u_instr ? {   $instr[31],  $instr[30:20],  $instr[19:12],  12'b0  } :
                $is_j_instr ? {   {12{$instr[31]}},  $instr[19:12],  $instr[20],  $instr[30:25],  $instr[24:21],  1'b0  } :
                32'b0;  // Default
   
   // Decode Logic: Instruction
   $dec_bits[10:0] = { $instr[30], $funct3, $opcode };
   $is_beq = $dec_bits ==? 11'bx_000_1100011;
   $is_bne = $dec_bits ==? 11'bx_001_1100011;
   $is_blt = $dec_bits ==? 11'bx_100_1100011;
   $is_bge = $dec_bits ==? 11'bx_101_1100011;
   $is_bltu = $dec_bits ==? 11'bx_110_1100011;
   $is_bgeu = $dec_bits ==? 11'bx_111_1100011;
   
   $is_addi = $dec_bits ==? 11'bx_000_0010011;
   
   $is_add = $dec_bits == 11'b0_000_0110011;
   
   // Register File Read/Write
   $rf_write[31:0] = $is_load ? $ld_data[31:0] : $result[31:0];
   m4+rf(32, 32, $reset, $wr_en, $wr_index[4:0], $rf_write[31:0], $rd_en1, $rs1[4:0], $src1_value, $rd_en2, $rs2[4:0], $src2_value)
   
   // Arithmetic Logic Unit
   // SLTU and SLTI (set if less than, unsigned) results:
   $sltu_rslt[31:0] = {31'b0, $src1_value < $src2_value};
   $sltiu_rslt[31:0] = {31'b0, $src1_value < $imm};
   
   // SRA and SRAI (shift right, arithmetic) results:
   // sign-extended src1
   $sext_src1[63:0] = { {32{$src1_value[31]}}, $src1_value };
   // 64-bit sign-extended results, to be truncated
   $sra_rslt[63:0] = $sext_src1 >> $src2_value[4:0];
   $srai_rslt[63:0] = $sext_src1 >> $imm[4:0];
   
   $result[31:0] = $is_addi ? $src1_value + $imm :
                   $is_add  ? $src1_value + $src2_value :
                   $is_load || $is_store ? $src1_value + $imm:
                              32'b0;
   
   // Register File Write
   // Connecting write back to result output 
   // Write enable is allowed only if the destination register is not 0 since
   // x0 (register file index 0) is always 0 in RISC-V
   $wr_en = $wr_index != 16'b0;
   // Test case
   // $wr_index[4:0] = 16'b0;
   
   // Branch Logic
   $taken_br = $is_beq  ? $src1_value == $src2_value :
               $is_bne  ? $src1_value != $src2_value :
               $is_blt  ? ($src1_value < $src2_value) ^ ($src1_value[31] != $src2_value[31]) :
               $is_bge  ? ($src1_value >= $src2_value) ^ ($src1_value[31] != $src2_value[31]) :
               $is_bltu ? $src1_value < $src2_value :
               $is_bgeu ? $src1_value >= $src2_value :
                          1'b0;
   
   $br_tgt_pc[31:0] = $pc + $imm;
   // Update to pc with added logic if its a taken branch
   
   // Additional Decode Logic
   $is_lui = $dec_bits ==? 11'bx_xxx_0110111;
   $is_auipc = $dec_bits ==? 11'bx_xxx_0010111;
   $is_jal = $dec_bits ==? 11'bx_xxx_1101111;
   $is_jalr = $dec_bits ==? 11'bx_000_1100111;
   $is_slti = $dec_bits ==? 11'bx_010_0010011;
   $is_sltiu = $dec_bits ==? 11'bx_011_0010011;
   $is_xori = $dec_bits ==? 11'bx_100_0010011;
   $is_ori = $dec_bits ==? 11'bx_110_0010011;
   $is_andi = $dec_bits ==? 11'bx_111_0010011;
   $is_slli = $dec_bits ==? 11'b0_001_0010011;
   $is_srli = $dec_bits ==? 11'b0_101_0010011;
   $is_srai = $dec_bits ==? 11'b1_101_0010011;
   $is_sub = $dec_bits ==? 11'b1_000_0110011;
   $is_sll = $dec_bits ==? 11'b0_001_0110011;
   $is_slt = $dec_bits ==? 11'b0_010_0110011;
   $is_sltu = $dec_bits ==? 11'b0_011_0110011;
   $is_xor = $dec_bits ==? 11'b0_100_0110011;
   $is_srl = $dec_bits ==? 11'b0_101_0110011;
   $is_sra = $dec_bits ==? 11'b1_101_0110011;
   $is_or = $dec_bits ==? 11'b0_110_0110011;
   $is_and = $dec_bits ==? 11'b0_111_0110011;
   
   $is_load = $opcode == 7'b0000011;
   $is_store = $is_s_instr;
   
   // Jump Logic
   $jalr_tgt_pc[31:0] = $src1_value + $imm;
   // Updare to pc logic to select correct next_pc 
   // for jump and link (JAL, $br_tgt_pc) and jump and link register (JALR, $jalr_tgt_pc)
   
   // Data Memory
   // Added additional logic to get address values from result for load and store instructions.
   // write enable is for stores, read enable is for loads,
   // write address is our result of $src1_value + $imm,
   // src2_value provides us the write data
   // output is the load data, ld_data
   m4+dmem(32, 32, $reset, $result, $is_store, $src2_value, $is_load, $ld_data)
   // Added multiplexer to write ld_data instead of result to register file, if is_load

   
   // Assert these to end simulation (before Makerchip cycle limit).
   m4+tb()
   *failed = *cyc_cnt > M4_MAX_CYC;
   
   m4+cpu_viz()
\SV
   endmodule