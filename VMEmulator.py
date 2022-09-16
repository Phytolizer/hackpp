import re
from collections import namedtuple
from sys import argv, exit
from textwrap import dedent


class ParsingError(Exception):
    pass


def filter_comments(line):
    match = re.match(r'^(.*?)//.*$', line)
    if match:
        return match.group(1)
    else:
        return line


def tokenize(line):
    return re.findall(r'\S+', line)


def setup_sp():
    Parser.out_buf += """@256
D = A
@SP
M = D
"""


def push(segment, val):
    if val not in Parser.symbols:
        if not re.match(r'\d+', val):
            raise ParsingError(f"Unknown symbol at line {Parser.index}: {val}")
    out = f'@{val}\n'
    if re.match(r'\d+', val):
        out += 'D = A\n'
    else:
        out += 'D = M\n'
    out += """@SP
AM = M + 1
A = A - 1
M = D
"""
    return out


def pop(segment, dest):
    if dest not in Parser.symbols:
        if re.match(r'^\d+$', dest):
            raise ParsingError(f"line {Parser.index}: "
                               f"Cannot pop to numeric literal")
        Parser.symbols.append(dest)
    return f"""@SP
AM = M - 1
D = M
@{dest}
M = D
"""


def inv():
    return """@SP
A = M - 1
M = !M
"""


def add():
    return """@SP
AM = M - 1
D = M
A = A - 1
M = D + M
"""


def sub():
    return """@SP
AM = M - 1
D = M
A = A - 1
M = M - D
"""


def neg():
    return """@SP
A = M - 1
M = -M
"""


def eq():
    Parser.n_eqs += 1
    return f"""@SP
AM = M - 1
D = M
A = A - 1
D = D - M
M = -1
@EQ{Parser.n_eqs}
D;JEQ
@SP
A = M - 1
M = 0
(EQ{Parser.n_eqs})
"""


def gt():
    Parser.n_eqs += 1
    return f"""@SP
AM = M - 1
D = M
A = A - 1
D = M - D
M = -1
@GT{Parser.n_eqs}
D;JGT
@SP
A = M - 1
M = 0
(GT{Parser.n_eqs})
"""


def lt():
    Parser.n_eqs += 1
    return f"""@SP
AM = M - 1
D = M
A = A - 1
D = M - D
M = -1
@LT{Parser.n_eqs}
D;JLT
@SP
A = M - 1
M = 0
(LT{Parser.n_eqs})
"""


def and_of():
    pass


def or_of():
    pass


command = namedtuple('command', ['n_args', 'assigns', 'sub'])


class Parser:
    n_eqs = 0
    index = -1
    verbose = False
    STACK_ADDR = 256
    header = dedent(f"""
        @{STACK_ADDR}
        D = A
        @SP
        M = D
        @main
        0;JMP
    """).strip()
    lines = []
    out_buf = ''

    input_f = None
    output_f = None

    symbols = ['SP', 'LCL', 'ARG', 'THIS', 'THAT', 'SCREEN', 'KBD']
    commands = {'push': command(n_args=2, assigns=False, sub=push),
                'pop': command(n_args=2, assigns=True, sub=pop),
                'not': command(n_args=0, assigns=False, sub=inv),
                'add': command(n_args=0, assigns=False, sub=add),
                'sub': command(n_args=0, assigns=False, sub=sub),
                'neg': command(n_args=0, assigns=False, sub=neg),
                'eq': command(n_args=0, assigns=False, sub=eq),
                'gt': command(n_args=0, assigns=False, sub=gt),
                'lt': command(n_args=0, assigns=False, sub=lt),
                'and': command(n_args=0, assigns=False, sub=and_of),
                'or': command(n_args=0, assigns=False, sub=or_of), }

    @classmethod
    def parse(cls):
        for line in cls.input_f.readlines():
            cls.index += 1
            line = filter_comments(line)
            tokens = tokenize(line)
            if len(tokens) == 0:
                continue
            print(tokens)
            cmd_name = tokens[0]
            if cmd_name not in cls.commands:
                raise ParsingError(
                    f'Unknown command: {cmd_name} (line {cls.index})')
            cmd = cls.commands[cmd_name]
            if len(tokens) - 1 != cmd.n_args:
                raise ParsingError(f'Command {cmd_name}: expected {cmd.n_args} '
                                   f'arguments, found {len(tokens) - 1}')
            cls.out_buf += cmd.sub(*tokens[1:])
        cls.output_f.write(cls.out_buf)


def print_help():
    print(f'Usage: python {argv[0]} INFILE [-o OUTFILE]\n'
          f'Type "python {argv[0]} -h" for more information.')
    exit(1)


if __name__ == '__main__':
    if len(argv) == 1:
        print_help()
    input_fname = ''
    output_fname = 'output.asm'
    skip = False
    for i in range(1, len(argv)):
        if skip:
            skip = False
            continue
        arg = argv[i]
        if arg[0] == '-':
            if arg == '-o':
                try:
                    output_fname = argv[i + 1]
                except IndexError:
                    print_help()
                else:
                    skip = True
        else:
            input_fname = arg
    Parser.input_f = open(input_fname, 'r')
    Parser.output_f = open(output_fname, 'w')
    setup_sp()
    Parser.parse()
    Parser.input_f.close()
    Parser.output_f.close()
