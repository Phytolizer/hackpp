# Assembler.py
# Written by Kyle Coffey
# Made for CSCE 312-511, project 6
# UIN: 126007313

import re
from sys import argv, exit


# INSTRUCTION REFERENCE

# 111accccccdddjjj
# ^ determines that this is a c-instruction

# d values:
# d0 d1 d2
# 0  0  0  | no store
# 0  0  1  |   M
# 0  1  0  |  D
# 0  1  1  |  DM
# 1  0  0  | A
# 1  0  1  | A M
# 1  1  0  | AD
# 1  1  1  | ADM

# j values:
# j0 j1 j2
# 0  0  0  | no jump
# 0  0  1  |   G
# 0  1  0  |  E
# 0  1  1  |  EG
# 1  0  0  | L
# 1  0  1  | L G
# 1  1  0  | LE
# 1  1  1  | LEG


def b_to_i(b):
    return 1 if b else 0


def c_instr_for(uo, u1, b1, bo, b2):
    if u1:
        if uo:
            u = f'{uo}{u1}'
            if u == '-1':
                return '111010'
            if u == '!D':
                return '001101'
            if u == '!A' or u == '!M':
                return '110001'
            if u == '-D':
                return '001111'
            if u == '-A' or u == '-M':
                return '110011'
            raise ParsingError(f"Unsupported unary instruction {u}")
    if b1:
        if bo and b2:
            b = f'{b1}{bo}{b2}'
            if b == 'D+1' or b == '1+D':
                return '011111'
            if b == 'A+1' or b == 'M+1' or b == '1+A' or b == '1+M':
                return '110111'
            if b == 'D-1':
                return '001110'
            if b == 'A-1' or b == 'M-1':
                return '110010'
            if b == 'D+A' or b == 'D+M' or b == 'A+D' or b == 'M+D':
                return '000010'
            if b == 'D-A' or b == 'D-M':
                return '010011'
            if b == 'A-D' or b == 'M-D':
                return '000111'
            if b == 'D&A' or b == 'D&M' or b == 'A&D' or b == 'M&D':
                return '000000'
            if b == 'D|A' or b == 'D|M' or b == 'A|D' or b == 'M|D':
                return '010101'
            raise ParsingError(f"Unsupported binary instruction {b}")
        if b1 == '0':
            return '101010'
        if b1 == '1':
            return '111111'
        if b1 == 'D':
            return '001100'
        if b1 == 'A' or b1 == 'M':
            return '110000'
        raise ParsingError(f"Unknown unary operand {b1}")


class ParsingError(Exception):
    pass


class Assembler:
    input_f = None
    input = None
    output_f = None
    index = 1
    output_index = 1
    next_variable_addr = 16
    verbose = False
    numeric_pattern = re.compile(r'^\s*R?(\d+)\s*$')
    empty_line_pattern = re.compile(r'^\s*$')
    labels = {}
    symbols = {'SCREEN': 16384, 'KBD': 24576, 'SP': 0, 'LCL': 1, 'ARG': 2,
               'THIS': 3, 'THAT': 4}
    # instruction spec: Each one is a regex
    # The regex will store important information in its capture groups
    instructions = {'a_ld': re.compile(r'^\s*@(\S+)'),
                    'instr': re.compile(r'^\s*(?:([AMD]{1,3})\s*=\s*)?'
                                        #          ^ destination
                                        r'(?:([-!])([01AMD])|'
                                        #     ^ unary  ^ operand
                                        r'([01AMD])(?:\s*([+\-&|])\s*([01AMD]))?)'
                                        #   ^ op1          ^ operation     ^ op2
                                        r'(?:\s*;\s*(?:J(LT|LE|EQ|GE|GT|NE|MP))?)?\s*'
                                        #               ^ jump instruction
                                        r'(?://.*)?$'),
                    'comment': re.compile(r'^\s*//.*$'),
                    'label': re.compile(r'^\s*\((\S+)\)')}

    @classmethod
    def binary_of(cls, val):
        numeric_match = cls.numeric_pattern.match(val)
        if numeric_match:
            rhs = bin(int(numeric_match.group(1)))[2:]
        else:
            if val in cls.labels.keys():
                if cls.verbose:
                    print(f"{val} is a known label")
                line_no = cls.labels[val]
                rhs = bin(line_no)[2:]
            elif val in cls.symbols.keys():
                if cls.verbose:
                    print(f"{val} is a known variable")
                addr = cls.symbols[val]
                rhs = bin(addr)[2:]
            else:
                if cls.verbose:
                    print(f"{val} is unknown, assuming it is a new variable")
                cls.symbols[val] = cls.next_variable_addr
                rhs = bin(cls.next_variable_addr)[2:]
                cls.next_variable_addr += 1
        return rhs.zfill(16)

    @classmethod
    def load_input_file(cls):
        cls.input = cls.input_f.readlines()

    @classmethod
    def index_labels(cls):
        n_instrs = 0
        for line in cls.input:
            label_match = cls.instructions['label'].match(line)
            instr_match = cls.instructions['a_ld'].match(line) or \
                          cls.instructions['instr'].match(line)
            if label_match:
                label = label_match.group(1)
                if label in cls.labels.keys():
                    raise ParsingError(f"two different labels named {label}")
                if cls.verbose:
                    print(
                        f"Label {label} should correspond to output line {n_instrs}")
                cls.labels[label] = n_instrs
            elif instr_match:
                n_instrs += 1

    @classmethod
    def parse(cls):
        for line in cls.input:
            a_instr = cls.instructions['a_ld'].match(line)
            c_instr = cls.instructions['instr'].match(line)
            comment = cls.instructions['comment'].match(line) is not None
            label = cls.instructions['label'].match(line)
            empty_line = cls.empty_line_pattern.match(line)
            if a_instr is not None:
                val = a_instr.group(1)
                if cls.verbose:
                    print("a-instruction")
                    print(f"loading to a: {val}")
                a_out = cls.binary_of(val)
                if cls.verbose:
                    print(a_out)
                cls.output_f.write(a_out + '\n')
            elif c_instr is not None:
                d = c_instr.group(1)
                unary_op = c_instr.group(2)
                unary_operand = c_instr.group(3)
                bin_op1 = c_instr.group(4)
                bin_op = c_instr.group(5)
                bin_op2 = c_instr.group(6)
                j = c_instr.group(7)
                if cls.verbose:
                    print("c-instruction")
                    print(f"d: {d}, "
                          f"unary: {unary_op}{unary_operand}, "
                          f"op1: {bin_op1}, "
                          f"op: {bin_op}, "
                          f"op2: {bin_op2}, "
                          f"j: {j}")
                if bin_op1 == 'A' and bin_op2 == 'M' or bin_op1 == 'M' and bin_op2 == 'A':
                    raise ParsingError(
                        f"line {cls.index}: 'A' and 'M' in binary operation is not allowed")
                a = '1' if 'M' in (bin_op1, bin_op2, unary_operand) else '0'
                c_all = c_instr_for(unary_op, unary_operand, bin_op1, bin_op,
                                    bin_op2)
                d1 = 'A' in d if d else False
                d2 = 'D' in d if d else False
                d3 = 'M' in d if d else False
                d_all = ''.join(map(str, map(b_to_i, (d1, d2, d3))))
                j1 = j in ('LT', 'NE', 'LE', 'MP')
                j2 = j in ('EQ', 'GE', 'LE', 'MP')
                j3 = j in ('GT', 'GE', 'NE', 'MP')
                j_all = ''.join(map(str, map(b_to_i, (j1, j2, j3))))
                if cls.verbose:
                    print(f'111{a}{c_all}{d_all}{j_all}')
                cls.output_f.write(f'111{a}{c_all}{d_all}{j_all}\n')
            elif not (label or comment or empty_line):
                raise ParsingError(f"Cannot parse line {cls.index}:\n{line}")
        cls.index += 1
        cls.output_index += 1


def print_help():
    print(f"Usage: python {argv[0]} <filename>\nType 'python "
          f"{argv[0]} -h' for more information.")
    exit(1)


if __name__ == '__main__':
    output_file_name = None
    input_file_name = None
    skip_iter = False
    for i in range(1, len(argv)):
        if skip_iter:
            skip_iter = False
            continue
        arg = argv[i]
        if arg == '-h':
            print(f"""{argv[0]} -- \
Converts Hack ASM into Hack machine code. Written by Kyle Coffey.
Usage: python {argv[0]} <filename> [options]
Options:
  -h           Print this help message.
  -o OUTFILE   Place output in OUTFILE. If this argument is not supplied, \
output goes to '<filename>.hack'
  -v           Print semantic information about every line as it is parsed.
            """)
            exit(0)
        elif arg == '-o':
            if i + 1 < len(argv):
                output_file_name = argv[i + 1]
                skip_iter = True
        elif arg == '-v':
            Assembler.verbose = True
        else:
            input_file_name = arg
    if input_file_name is None:
        print_help()
    if output_file_name is None:
        output_file_name = re.match(r'^(.+?)(\.asm)?$', input_file_name).group(
            1) + '.hack'
    Assembler.input_f = open(input_file_name)
    print(f'Assembling {input_file_name}')
    Assembler.output_f = open(output_file_name, 'w')
    print(f'Output will be in {output_file_name}')
    Assembler.load_input_file()
    Assembler.index_labels()
    Assembler.parse()
    Assembler.input_f.close()
    Assembler.output_f.close()
