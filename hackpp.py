import re
import sys
from sys import exit

tMacro = 0
tAddress = 1
tLiteral = 2

LABEL_PATTERN = re.compile(r'^\s*\(([a-zA-Z]+)\)')
TOKENIZING_PATTERN = re.compile(r'\s+')
ENDDEF_PATTERN = re.compile(r'^\s*#ENDDEF\s*$')
LINES = []
N_RETS = 0


class InvalidTokenPrefixError(Exception):
    def __init__(self, value):
        self.message = f"Token {value} is invalid (must start with '#', '@', or ':')"


class MismatchedEndError(Exception):
    def __init__(self):
        self.message = 'END found outside of block'


class InvalidTokenValueError(Exception):
    def __init__(self, value):
        self.message = f"Token {value} is invalid (needs a value)"


class InvalidMacroError(Exception):
    def __init__(self, macro):
        self.message = f"Macro is not defined: {macro}"


class LabelNotFoundError(Exception):
    def __init__(self, label):
        self.message = f"Label could not be found: {label}"


class NestedFunctionError(Exception):
    def __init__(self, function):
        self.message = f"Nested definitions are not allowed, did you forget #ENDDEF? ({function})"


class NotTerminatedError(Exception):
    def __init__(self, where):
        self.message = f"Block was not terminated: {where}"


class NotDefinedError(Exception):
    def __init__(self, what):
        self.message = f"Function is not defined: {what}"


class BadBreakError(Exception):
    def __init__(self):
        self.message = 'Break while not in loop'


class Token:
    def __init__(self, value):
        self.type = token_type(value)
        if self.type is None:
            raise InvalidTokenPrefixError(value)
        self.value = value[1:]
        if len(self.value) == 0:
            raise InvalidTokenValueError(value)


def sub_goto(label):
    # look for corresponding label
    for line in LINES:
        dest_label = LABEL_PATTERN.match(line)
        if dest_label is not None and dest_label.group(1) == label.value:
            LINES[Parser.idx] = f"@{label.value}\n0;JMP\n"
            return
    raise LabelNotFoundError(label.value)


def sub_def(name):
    # look for enddef
    i = Parser.idx + 1
    for line in LINES[Parser.idx + 1:]:
        nested_def = re.match(r'^\s*#DEF\s+(\S+)', line)
        if nested_def is not None:
            raise NestedFunctionError(nested_def.group(1))
        end = ENDDEF_PATTERN.match(line)
        if end is not None:
            LINES[i] = "@ret\nA = M\n0;JMP\n"
            LINES[Parser.idx] = f"({name.value})\n"
            return
        i += 1
    raise NotTerminatedError(f"Function {name.value}")


def sub_call(name):
    i = Parser.idx - 1
    for line in LINES[Parser.idx - 1::-1]:
        func = re.match(r'^\s*\((\S+)\)', line)
        if func is not None and func.group(1) == name.value:
            Parser.n_rets += 1
            LINES[Parser.idx] = f"@ret{Parser.n_rets}\nD=A\n@ret\nM=D\n@{name.value}\n0;JMP\n(ret{Parser.n_rets})\n"
            return
    raise NotDefinedError(name.value)


def sub_uncond_loop():
    Parser.n_loops += 1
    LINES[Parser.idx] = f"(loop{Parser.n_loops})"


def inverse_of(cond):
    inv = { 'LT': 'GE', 'LE': 'GT', 'EQ': 'NE', 'GE': 'LT', 'GT': 'LE', 'NE': 'EQ' }
    return inv[cond]


def sub_cond_loop(op1, op2):
    Parser.n_loops += 1
    cond = re.match(r'^\s*#LOOP(LT|LE|EQ|GE|GT|NE)', LINES[Parser.idx]).group(1)
    out = f"(loop{Parser.n_loops})\n"
    # check condition
    out += load_to_d(op1)
    out += load_to_a(op2)
    out += f"D = D - {'A' if op2.type == tLiteral else 'M'}\n"
    out += f"@endloop{Parser.n_loops}\n"
    out += f"D;J{inverse_of(cond)}\n"
    LINES[Parser.idx] = out


def sub_break_loop():
    # find the loop you are in
    depth = 0
    for line in LINES[Parser.idx - 1::-1]:
        if re.match(r'^\s*\(endloop', line) is not None:
            depth += 1
        loop = re.match(r'^\s*\(loop(\d+)\)', line)
        if loop is not None:
            if depth == 0:
                LINES[Parser.idx] = f"@endloop{loop.group(1)}\n0;JMP"
                return
            else:
                depth -= 1
    raise BadBreakError()


def sub_end_loop():
    # find the loop you are in
    depth = 0
    for line in LINES[Parser.idx - 1::-1]:
        if re.match(r'^\s*#ENDLOOP', line) is not None:
            depth += 1
        loop = re.match(r'^\s*\(loop(\d+)\)', line)
        if loop is not None:
            if depth == 0:
                LINES[Parser.idx] = f'@loop{loop.group(1)}\n0;JMP\n(endloop{loop.group(1)})'
                return
    raise MismatchedEndError()


def sub_add(dest, amt):
    out = load_to_d(amt)
    out += load_to_a(dest)
    out += "M = M + D"
    LINES[Parser.idx] = out


def sub_subtract(dest, amt):
    out = load_to_d(amt)
    out += load_to_a(dest)
    out += "M = M - D"
    LINES[Parser.idx] = out


def sub_set(var, val):
    out = load_to_d(val)
    out += load_to_a(var)
    out += 'M = D'
    LINES[Parser.idx] = out


def sub_if(op1, op2):
    Parser.n_ifs += 1
    cond = re.match(r'^\s*#IF(LT|LE|EQ|GE|GT|NE)', LINES[Parser.idx]).group(1)
    # perform a lookahead substitution
    # is there an else branch?
    has_else = False
    matched_end = False
    depth = 0
    i = Parser.idx + 1
    for line in LINES[Parser.idx + 1:]:
        # nested if
        if re.match(r'^\s*#IF(LT|LE|EQ|GE|GT|NE)', line) is not None:
            depth += 1
        # else
        if re.match(r'^\s*#ELSE', line) is not None:
            if depth == 0:
                LINES[i] = f"@endif{Parser.n_ifs}\n0;JMP\n(else{Parser.n_ifs})"
                has_else = True
        # endif
        if re.match(r'^\s*#ENDIF', line) is not None:
            if depth == 0:
                LINES[i] = f"(endif{Parser.n_ifs})\n"
                matched_end = True
            else:
                depth -= 1
        i += 1
    if matched_end:
        out = load_to_d(op2)
        out += load_to_a(op1)
        out += f"D = D - {'A' if op1.type == tLiteral else 'M'}\n"
        if has_else:
            out += f"@else{Parser.n_ifs}\n"
        else:
            out += f"@endif{Parser.n_ifs}\n"
        out += f"D;J{inverse_of(cond)}\n"
        LINES[Parser.idx] = out
    else:
        raise MismatchedEndError()


class Macro:
    def __init__(self, n_args, substitution, paired=False):
        self.n_args = n_args
        self.substitute = substitution
        self.paired = paired


class Macros:
    defined_macros = { '#GOTO': Macro(1, sub_goto), '#DEF': Macro(1, sub_def), '#CALL': Macro(1, sub_call),
                       '#LOOP': Macro(0, sub_uncond_loop), '#BREAK': Macro(0, sub_break_loop),
                       '#ENDLOOP': Macro(0, sub_end_loop), '#ADD': Macro(2, sub_add), '#SUB': Macro(2, sub_subtract),
                       '#SET': Macro(2, sub_set) }
    regex_macros = { re.compile('#LOOP(LT|LE|EQ|GE|GT|NE)'): Macro(2, sub_cond_loop),
                     re.compile('#IF(LT|LE|EQ|GE|GT|NE)'): Macro(2, sub_if) }


class ArgumentError(Exception):
    def __init__(self, macro):
        super(f"Incorrect number of arguments to macro {macro}")


class Parser:
    output_file = 'result.asm'
    call_stack = []
    idx = 0
    n_rets = 0
    n_loops = 0
    n_ifs = 0

    def __init__(self, file):
        self.file = file

    def parse(self):
        for line in LINES:
            if line[0] == '#':
                tokens = TOKENIZING_PATTERN.split(line)
                print(tokens)
                macro = None
                if tokens[0] not in Macros.defined_macros:
                    matches_a_regex = False
                    for regex in Macros.regex_macros.keys():
                        if regex.match(tokens[0]):
                            matches_a_regex = True
                            macro = Macros.regex_macros[regex]
                            break
                    if not matches_a_regex:
                        raise InvalidMacroError(tokens[0])
                else:
                    macro = Macros.defined_macros[tokens[0]]
                if len(tokens[1:]) != macro.n_args:
                    raise ArgumentError(tokens[0])
                token_objs = list(map(Token, tokens[1:]))
                macro.substitute(*token_objs)
                print(LINES[Parser.idx])
            else:
                print(line)
            self.file.write(LINES[Parser.idx] + '\n')
            Parser.idx += 1


def token_type(value):
    prefix = value[0]
    if prefix == '#':
        return tMacro
    elif prefix == '@':
        return tAddress
    elif prefix == ':':
        return tLiteral
    else:
        return None


def load_to_d(token):
    return f"@{token.value}\nD = {'A' if token.type == tLiteral else 'M'}\n"


def load_to_a(token):
    return f"@{token.value}\n"


class InvalidArgument(Exception):
    def __init__(self):
        super("Invalid argument")


def print_help():
    print(f"Usage: {sys.argv[0]} <filename> [-o outputfile]")


def parse_command_line_args():
    _data = { }
    skip = False
    for i in range(1, len(sys.argv)):
        if skip:
            skip = False
            continue
        arg = sys.argv[i]
        if arg[0] == '-':
            if arg[1] == 'o':
                _data['ofname'] = sys.argv[i + 1]
                skip = True
            else:
                raise InvalidArgument()
        else:
            _data['ifname'] = arg
    return _data


if __name__ == "__main__":
    data = parse_command_line_args()
    if 'ifname' not in data:
        print_help()
        exit(0)
    input_file = data['ifname']
    output_file = data['ofname'] if 'ofname' in data else 'output.asm'
    with open(input_file) as inf:
        LINES = inf.readlines()
        LINES = map(lambda x: x.rstrip('\r\n'), LINES)
        LINES = filter(lambda x: x != '', LINES)
        LINES = list(LINES)
    with open(output_file, 'w') as outf:
        Parser(outf).parse()
