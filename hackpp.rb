# A Hack assembly pre-processor. Provides several macros
# for convenience when writing code.
#
# Author: Kyle Coffey

require 'pathname'

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
@#{param}
D = A
@#{param_index}
M = D
          CALLPARAM
          param_index += 1
        end
      elsif !params.nil?
        call_str << <<-CALLPARAM
@#{params}
D = A
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
    macro_args = line.chomp.split(/\b[,\s]\s*\b/)
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

# Main procedure.
if ARGV.empty?
  puts 'Usage: ruby hackpp.rb <filename>'
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
