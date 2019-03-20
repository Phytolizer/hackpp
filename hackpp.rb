# A Hack assembly pre-processor. Provides several macros
# for convenience when writing code.
#
# Author: Kyle Coffey

require 'pathname'

# check properties of a token
def macro? x
  x[0] == '!'
end

def literal? x
  x[0] == '$'
end

def address? x
  x[0] == '@'
end


def load_to_d(val)
  get_value(val) << "\nD = #{a_m(val)}"
end

def get_value(val)
  "#{address?(val) ? '' : '@'}#{literal?(val) ? val[1..-1] : val}"
end

def a_m(val)
  "#{literal?(val) ? 'A' : 'M'}"
end

# The file name to output to
$output_file = 'result.asm'

# A list of all defined functions
$functions = []

# Whether the current line is inside a function definition
$defining_function = false

# The number of function calls, help with unique labels
$n_calls = 0

# The number of unique infinite loops. Will probably stay at 1 in practice.
$n_loops = 0

# A list of all defined macros. The parser will check all macros in this list
# by their :trigger attribute.
MACROS = [
  {
    name: 'function-define',
    trigger: '!DEF',
    args: ['function-name', 'parameters'],

    action: -> name, params {
      $functions << {
        name: name,
        parameters: params
      }
      # check for double-define, not supported
      if $defining_function
        puts 'ERROR: No support for nested functions'
        exit 9
      end
      $defining_function = true

      return <<-FNHEADER
(#{name})
      FNHEADER
    }
  },
  {
    name: 'function-end-definition',
    trigger: '!ENDDEF',
    args: [],

    action: -> {
      $defining_function = false
      <<-EXITPT
@ret
A = M
0;JMP
      EXITPT
    }
  },
  {
    name: 'function-call',
    trigger: '!CALL',
    args: ['function-name', 'parameters'],
    action: -> name, params {
      func_found = false
      $functions.each do |f|
        next unless f[:name] == name

        if f[:parameters].length < params.length
          puts "ERROR: in call to function #{f[:name]}:"
          puts '    incorrect number of parameters ' \
               "(#{params.length}, expected #{f[:parameters].length})"
          exit 7
        end
        func_found = true
      end
      unless func_found
        puts "ERROR: Undefined function: #{name}"
        exit 8
      end
      $n_calls += 1
      call_str = <<-CALLSTART
@RET#{$n_calls}
D = A
@ret
M = D
      CALLSTART
      param_index = 0
      if params.respond_to? :each
        params.each do |p|
          call_str << <<-CALLPARAM
#{load_to_d(p)}
@#{param_index}
M = D
          CALLPARAM
          param_index += 1
        end
      elsif !params.nil?
        call_str << <<-CALLPARAM
#{load_to_d(params)}
@#{param_index}
M = D
        CALLPARAM
      end
      call_str << <<-CALLEND
@#{name}
0;JMP
(RET#{$n_calls})
      CALLEND
      return call_str
    }
  },
  {
    name: 'infinite-loop',
    trigger: '!LOOP',
    args: [],
    
    action: -> {
      $n_loops += 1
      return <<-LOOP
(LOOP#{$n_loops})
@LOOP#{$n_loops}
0;JMP
      LOOP
    }
  },
  {
    name: 'set-identifier',
    trigger: '!SET',
    args: ['ident', 'value'],

    action: -> i, v {
      if literal?(i) || macro?(i)
        puts 'ERROR: Cannot assign to literals/macros'
        exit 10
      end
      if macro? v
        puts 'ERROR: Cannot assign from macros'
        exit 11
      end
      output = ''
      # load v into D
      output << load_to_d(v) << "\n"
      # load i from D
      output << get_value(i) << "\nM = D\n"
      return output
    }
  },
  {
    name: 'goto',
    trigger: '!GOTO',
    args: ['location'],

    action: -> loc {
      return <<-GOTO
@#{loc}
0;JMP
      GOTO
    }
  },
  {
    name: 'add',
    trigger: '!ADD',
    args: ['destination', 'amount'],

    action: -> dest, amt {
      if literal?(dest) || macro?(dest)
        puts 'ERROR: Cannot assign to literals/macros'
        exit 10
      end
      if macro?(amt)
        puts 'ERROR: Cannot assign from macros'
        exit 11
      end
      return load_to_d(amt) << "\n" << get_value(dest) << "\nM = M + D\n"
    }
  },
  {
    name: 'subtract',
    trigger: '!SUB',
    args: ['destination', 'amount'],

    action: -> dest, amt {
      if literal?(dest) || macro?(dest)
        puts 'ERROR: Cannot assign to literals/macros'
        exit 10
      end
      if macro?(amt)
        puts 'ERROR: Cannot assign from macros'
        exit 11
      end
      return load_to_d(amt) << "\n" << get_value(dest) << "\nM = M - D\n"
    }
  },
  {
    name: 'loop-while-nonzero',
    trigger: '!WHILENZ',
    args: ['value'],

    action: -> v {
      if macro?(v)
        puts 'ERROR: Macros cannot have values'
        exit 12
      elsif literal?(v)
        puts 'ERROR: While-loops don\'t take literals; consider using !LOOP'
        exit 13
      end
      output = ''
      $n_loops += 1
      return <<-WHILEHEAD
(WHILE#{$n_loops})
#{get_value(v)}
D = M
@ENDWHILE#{$n_loops}
D;JEQ
      WHILEHEAD
    }
  },
  {
    name: 'loop-while-zero',
    trigger: '!WHILEZR',
    args: ['value'],

    action: -> v {
      if macro?(v)
        puts 'ERROR: Macros cannot have values'
        exit 12
      elsif literal?(v)
        puts 'ERROR: While-loops don\'t take literals; consider using !LOOP'
        exit 13
      end
      output = ''
      $n_loops += 1
      return <<-WHILEHEAD
(WHILE#{$n_loops})
#{get_value(v)}
D = M
@ENDWHILE#{$n_loops}
D;JNE
      WHILEHEAD
    }
  },
  {
    name: 'while-less-than',
    trigger: '!WHILELT',
    args: ['x', 'y'],

    action: -> x, y {
      # y - x;JLE
      if macro?(y) || macro?(x)
        puts 'ERROR: Macros cannot have values'
        exit 12
      end
      $n_loops += 1
      return <<-WHILELT
(WHILE#{$n_loops})
#{load_to_d(x)}
#{get_value(y)}
D = D - #{a_m(y)}
@ENDWHILE#{$n_loops}
D;JGE
      WHILELT
    }
  },
  {
    name: 'while-less-than-or-equal',
    trigger: '!WHILELE',
    args: ['x', 'y'],

    action: -> x, y {
      if macro?(y) || macro?(x)
        puts 'ERROR: Macros cannot have values'
        exit 12
      end
      $n_loops += 1
      return <<-WHILELE
(WHILE#{$n_loops})
#{load_to_d(x)}
#{get_value(y)}
D = D - #{a_m(y)}
@ENDWHILE#{$n_loops}
D;JGT
      WHILELE
    }
  },
  {
    name: 'while-equal',
    trigger: '!WHILEEQ',
    args: ['x', 'y'],

    action: -> x, y {
      if macro?(y) || macro?(x)
        puts 'ERROR: Macros cannot have values'
        exit 12
      end
      $n_loops += 1
      return <<-WHILEEQ
(WHILE#{$n_loops})
#{load_to_d(x)}
#{get_value(y)}
D = D - #{a_m(y)}
@ENDWHILE#{$n_loops}
D;JNE
      WHILEEQ
    }
  },
  {
    name: 'while-greater-than-or-equal',
    trigger: '!WHILEGE',
    args: ['x', 'y'],

    action: -> x, y {
      if macro?(y) || macro?(x)
        puts 'ERROR: Macros cannot have values'
        exit 12
      end
      $n_loops += 1
      return <<-WHILEGE
(WHILE#{$n_loops})
#{load_to_d(x)}
#{get_value(y)}
D = D - #{a_m(y)}
@ENDWHILE#{$n_loops}
D;JLT
      WHILEGE
    }
  },
  {
    name: 'while-greater-than',
    trigger: '!WHILEGT',
    args: ['x', 'y'],

    action: -> x, y {
      if macro?(y) || macro?(x)
        puts 'ERROR: Macros cannot have values'
        exit 12
      end
      $n_loops += 1
      return <<-WHILEGT
(WHILE#{$n_loops})
#{load_to_d(x)}
#{get_value(y)}
D = D - #{a_m(y)}
@ENDWHILE#{$n_loops}
D;JLE
      WHILEGT
    }
  },
  {
    name: 'while-not-equal',
    trigger: '!WHILENE',
    args: ['x', 'y'],

    action: -> x, y {
      if macro?(y) || macro?(x)
        puts 'ERROR: Macros cannot have values'
        exit 12
      end
      $n_loops += 1
      return <<-WHILENE
(WHILE#{$n_loops})
#{load_to_d(x)}
#{get_value(y)}
D = D - #{a_m(y)}
@ENDWHILE#{$n_loops}
D;JEQ
      WHILENE
    }
  },
  {
    name: 'end-while',
    trigger: '!ENDWHILE',
    args: [],

    action: -> {
      <<-ENDWHILE
@WHILE#{$n_loops}
0;JMP
(ENDWHILE#{$n_loops})
      ENDWHILE
    }
  }
].freeze

ARGUMENTS = [
  {
    name: 'output-file',
    trigger: '-o',
    has_argument: true,
    action: -> f {
      $output_file = f
    }
  }
].freeze

def parse(line)
  if line[0] == '!'
    # Found a macro
    macro_trigger = line.match(/\S+/).to_s
    # Check which macro this is
    macro = nil
    MACROS.each do |m|
      macro = m if m[:trigger] == macro_trigger
    end
    if macro.nil?
      # This trigger doesn't match any macro
      puts "ERROR: Undefined macro: #{macro_trigger}"
      exit 3
    end
    puts "Found macro '#{macro[:name]}'"
    macro_args = line.chomp.split(/(?<=[\S^])[,\s]\s*(?=[\S$])/)
    macro_args = macro_args[1...macro_args.length]
    # if macro_args.length < macro[:args].length
      # puts 'Not enough arguments to macro, missing ' <<
           # macro[:args][macro_args.length]
      # exit 6
    # elsif macro_args.length > macro[:args].length
    if macro_args.length > macro[:args].length
      temp = macro_args[0...macro[:args].length - 1]
      temp << macro_args[macro[:args].length - 1...macro_args.length]
      macro_args = temp
    end
    puts "Arguments: #{macro_args}"
    $output.write(macro[:action].call(*macro_args))
  else
    puts line
    $output.write(line)
  end
end

# Main procedure
if ARGV.empty?
  puts 'Usage: ./hackpp <filename>'
  exit 0
end

# ensure input file is readable
unless File.exist?(ARGV[0])
  puts "File not found: #{ARGV[0]}"
  exit 1
end

unless File.readable?(ARGV[0])
  puts "Unable to read #{ARGV[0]}: Permission denied"
  exit 2
end

# check other optional args
(1...ARGV.length).each do |i|
  arg = ARGV[i]
  next unless arg[0] == '-'

  argument = nil
  ARGUMENTS.each do |a|
    argument = a if a[:trigger] == arg
  end
  if argument.nil?
    puts "Invalid argument: #{arg}"
    exit 4
  end
  if argument[:has_argument]
    i += 1
    argument[:action].call(ARGV[i])
  else
    argument[:action].call
  end
end

# open output file
unless File.exist?($output_file) && File.writable?($output_file) ||
       !File.exist?($output_file) && Pathname.new('.').writable?
  puts "Unable to write to #{$output_file}: Permission denied"
  exit 5
end
$output = File.open($output_file, 'w')

# read input file
input = File.open(ARGV[0]).read
# correct line endings in case DOS endings are there
input.gsub!(/\r\n?/, '\n')
input.each_line do |line|
  parse line
end
