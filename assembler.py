import sys
import os
import re

# Register mapping
REG_MAP = {
    'zero': 0, 'ra': 1, 'sp': 2, 'gp': 3, 'tp': 4, 't0': 5, 't1': 6, 't2': 7,
    's0': 8, 'fp': 8, 's1': 9, 'a0': 10, 'a1': 11, 'a2': 12, 'a3': 13, 'a4': 14,
    'a5': 15, 'a6': 16, 'a7': 17, 's2': 18, 's3': 19, 's4': 20, 's5': 21,
    's6': 22, 's7': 23, 's8': 24, 's9': 25, 's10': 26, 's11': 27, 't3': 28,
    't4': 29, 't5': 30, 't6': 31
}
for i in range(32): 
    REG_MAP[f'x{i}'] = i

def to_bin(val, bits):
    """Convert value to binary string with fixed width."""
    return format(val & ((1 << bits) - 1), f'0{bits}b')

def assemble():
    if len(sys.argv) < 3:
        return
    
    base_path = sys.argv[1]
    asm_filename = sys.argv[2]
    full_path = os.path.join(base_path, asm_filename)
    
    if not os.path.exists(full_path):
        return
    
    # First pass: collect labels
    labels = {}
    data_labels = {}
    instructions = []
    pc = 0
    data_addr = 0
    in_data = False
    
    with open(full_path, 'r') as f:
        for line in f:
            # Remove comments
            line = line.split('#')[0].strip()
            if not line:
                continue
            
            # Check for section directives
            if '.data' in line:
                in_data = True
                continue
            elif '.text' in line:
                in_data = False
                pc = 0
                continue
            elif '.globl' in line or '.global' in line:
                continue
            
            # Handle labels
            if ':' in line:
                label_name, rest = line.split(':', 1)
                label_name = label_name.strip()
                
                if in_data:
                    data_labels[label_name] = data_addr
                else:
                    labels[label_name] = pc
                
                line = rest.strip()
            
            # Process data section
            if in_data:
                if '.word' in line:
                    data_addr += 4
                continue
            
            # Process text section
            if line and not in_data:
                instructions.append((pc, line))
                pc += 4
    
    # Second pass: encode instructions
    bin_res = []
    hex_res = []
    
    for curr_pc, inst_str in instructions:
        # Replace %hi and %lo
        for var_name, var_addr in data_labels.items():
            inst_str = inst_str.replace(f'%hi({var_name})', str((var_addr >> 12) & 0xFFFFF))
            inst_str = inst_str.replace(f'%lo({var_name})', str(var_addr & 0xFFF))
        
        # Parse instruction
        tokens = [t for t in re.split(r'[,\s()]+', inst_str) if t]
        if not tokens:
            continue
        
        opcode = tokens[0].lower()
        machine_code = 0
        
        # R-type instructions
        if opcode in ['add', 'sub', 'sll', 'slt', 'sltu', 'xor', 'srl', 'sra', 'or', 'and']:
            rd = REG_MAP[tokens[1]]
            rs1 = REG_MAP[tokens[2]]
            rs2 = REG_MAP[tokens[3]]
            
            funct3_map = {'add': 0, 'sub': 0, 'sll': 1, 'slt': 2, 'sltu': 3, 
                         'xor': 4, 'srl': 5, 'sra': 5, 'or': 6, 'and': 7}
            funct7_map = {'add': 0, 'sub': 0x20, 'sll': 0, 'slt': 0, 'sltu': 0,
                         'xor': 0, 'srl': 0, 'sra': 0x20, 'or': 0, 'and': 0}
            
            funct3 = funct3_map[opcode]
            funct7 = funct7_map[opcode]
            
            binary = to_bin(funct7, 7) + to_bin(rs2, 5) + to_bin(rs1, 5) + to_bin(funct3, 3) + to_bin(rd, 5) + "0110011"
        
        # I-type instructions
        elif opcode in ['addi', 'slti', 'sltiu', 'xori', 'ori', 'andi', 'slli', 'srli', 'srai']:
            rd = REG_MAP[tokens[1]]
            rs1 = REG_MAP[tokens[2]]
            imm = int(tokens[3], 0)
            
            funct3_map = {'addi': 0, 'slti': 2, 'sltiu': 3, 'xori': 4, 'ori': 6, 'andi': 7,
                         'slli': 1, 'srli': 5, 'srai': 5}
            funct3 = funct3_map[opcode]
            
            if opcode in ['slli', 'srli', 'srai']:
                shamt = imm & 0x1F
                funct7 = 0 if opcode != 'srai' else 0x20
                binary = to_bin(funct7, 7) + to_bin(shamt, 5) + to_bin(rs1, 5) + to_bin(funct3, 3) + to_bin(rd, 5) + "0010011"
            else:
                binary = to_bin(imm, 12) + to_bin(rs1, 5) + to_bin(funct3, 3) + to_bin(rd, 5) + "0010011"
        
        # Load instructions
        elif opcode in ['lb', 'lh', 'lw', 'lbu', 'lhu']:
            rd = REG_MAP[tokens[1]]
            imm = int(tokens[2], 0)
            rs1 = REG_MAP[tokens[3]]
            
            funct3_map = {'lb': 0, 'lh': 1, 'lw': 2, 'lbu': 4, 'lhu': 5}
            funct3 = funct3_map[opcode]
            
            binary = to_bin(imm, 12) + to_bin(rs1, 5) + to_bin(funct3, 3) + to_bin(rd, 5) + "0000011"
        
        # S-type instructions
        elif opcode in ['sb', 'sh', 'sw']:
            rs2 = REG_MAP[tokens[1]]
            imm = int(tokens[2], 0)
            rs1 = REG_MAP[tokens[3]]
            
            funct3_map = {'sb': 0, 'sh': 1, 'sw': 2}
            funct3 = funct3_map[opcode]
            
            imm_bits = to_bin(imm, 12)
            binary = imm_bits[:7] + to_bin(rs2, 5) + to_bin(rs1, 5) + to_bin(funct3, 3) + imm_bits[7:] + "0100011"
        
        # B-type instructions
        elif opcode in ['beq', 'bne', 'blt', 'bge', 'bltu', 'bgeu']:
            rs1 = REG_MAP[tokens[1]]
            rs2 = REG_MAP[tokens[2]]
            
            if tokens[3] in labels:
                offset = labels[tokens[3]] - curr_pc
            else:
                offset = int(tokens[3], 0)
            
            funct3_map = {'beq': 0, 'bne': 1, 'blt': 4, 'bge': 5, 'bltu': 6, 'bgeu': 7}
            funct3 = funct3_map[opcode]
            
            offset_bits = to_bin(offset, 13)
            # B-type: imm[12|10:5] rs2 rs1 funct3 imm[4:1|11] opcode
            binary = offset_bits[0] + offset_bits[2:8] + to_bin(rs2, 5) + to_bin(rs1, 5) + to_bin(funct3, 3) + offset_bits[8:12] + offset_bits[1] + "1100011"
        
        # U-type instructions
        elif opcode in ['lui', 'auipc']:
            rd = REG_MAP[tokens[1]]
            imm = int(tokens[2], 0)
            
            opcode_map = {'lui': "0110111", 'auipc': "0010111"}
            binary = to_bin(imm, 20) + to_bin(rd, 5) + opcode_map[opcode]
        
        # J-type instructions
        elif opcode == 'jal':
            rd = REG_MAP[tokens[1]]
            
            if tokens[2] in labels:
                offset = labels[tokens[2]] - curr_pc
            else:
                offset = int(tokens[2], 0)
            
            offset_bits = to_bin(offset, 21)
            # J-type: imm[20|10:1|11|19:12] rd opcode
            binary = offset_bits[0] + offset_bits[10:20] + offset_bits[9] + offset_bits[1:9] + to_bin(rd, 5) + "1101111"
        
        # JALR instruction
        elif opcode == 'jalr':
            rd = REG_MAP[tokens[1]]
            imm = int(tokens[2], 0)
            rs1 = REG_MAP[tokens[3]]
            
            binary = to_bin(imm, 12) + to_bin(rs1, 5) + "000" + to_bin(rd, 5) + "1100111"
        
        else:
            continue
        
        if binary:
            bin_res.append(binary)
            hex_res.append(f"0x{int(binary, 2):08x}")
    
    # Write output files
    out_base = asm_filename.replace('.s', '')
    bin_path = os.path.join(base_path, f"{out_base}.bin")
    hex_path = os.path.join(base_path, f"{out_base}.hex.txt")
    
    # Write binary file
    with open(bin_path, "wb") as f:
        for binary in bin_res:
            value = int(binary, 2)
            f.write(value.to_bytes(4, byteorder="little"))
    
    # Write hex file
    with open(hex_path, "w", encoding='utf-8', newline='\n') as f:
        f.write("\n".join(hex_res) + "\n")
        f.flush()
        os.fsync(f.fileno())

if __name__ == "__main__":
    assemble()
