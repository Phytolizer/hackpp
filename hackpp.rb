# frozen_string_literal: true

# VMEmulator.rb
# Written by Kyle Coffey (UIN: 126007313)
# Class: CSCE 312, section 511 (Tyagi)
# Ruby string literal directive below. Forces strings assigned with string literals to be immutable, as this
# is how future Ruby versions will do it.
# frozen_string_literal: true

class ParsingError < RuntimeError
end

def parse_cli_args
  skip = false
  # need to keep track of index to use the -o flag properly
  ARGV.each_with_index do |arg, i|
    if skip
      skip = false
      next
    end
    if arg.start_with?('-')
      # this argument is a flag or set of flags (e.g. -vo, or "verbose, specify output file")
      flags = arg[1..-1]
      flags.each_char do |f|
        case f
        when 'o'
          Options.out_f = ARGV[i + 1]
          skip = true
        when 'v'
          puts 'Running in verbose mode.'
          Options.verbose = true
        when 'h'
          print_help(long: true)
        else
          raise ParsingError, %(Invalid option "#{ARGV[i]}")
        end
      end
    else
      # print help if you try to pass in two input files, as that probably
      # indicates you missed a hyphen or something similar
      print_help unless Options.in_f.nil?
      Options.in_f = arg
    end
  end
  # input file is the only required argument
  print_help if Options.in_f.nil?
end

def print_help(long: false)
  if long
    puts <<~LONGHELP
      ruby #{$PROGRAM_NAME} -- Converts Hack VM code into Hack ASM. Written by Kyle Coffey.
      Usage: ruby #{$PROGRAM_NAME} [-v] filename [-o outputfile]
      Options:
        -h   Print this help message.
        -v   Enable verbose output.
        -o outputfile   Store output in outputfile. Default: output.asm
    LONGHELP
  else
    puts <<~HELP
      Usage: ruby #{$PROGRAM_NAME} [-v] filename [-o outputfile]
      Type "ruby #{$PROGRAM_NAME} -h" for more information.
    HELP
  end
  exit(0)
end

# Command-line options, stored in a class
class Options
  class << self
    attr_accessor :verbose, :in_f, :out_f
  end

  # flag to enable verbose output
  @verbose = false
  # the name of the input file
  @in_f = nil
  @out_f = 'output.asm'
end

# pseudo-alias for Kernel#puts, but only works if the verbose flag was set
def vputs(*args)
  puts(*args) if Options.verbose
end

# same as vputs, but for Kernel#p
def vp(*args)
  p(*args) if Options.verbose
end

# Contains methods for all transformations involved
# when parsing Hack VM code as well as some helper methods to
# validate syntax.
module COMMANDS
  # Object#freeze: makes an object immutable for efficiency's sake
  COMMAND_PATTERN = /[\w\-\h]+/.freeze
  TOKENIZER = /(\S+)\h*/.freeze

  # Convert a string into an array of its space-separated "tokens".
  def self.tokenize(command:, linum:)
    unless COMMAND_PATTERN.match?(command)
      # this %() symbol denotes a string literal that allows both interpolation (the #{} construct)
      # and using unescaped double quotes. Single-quoted strings in Ruby are like raw strings in Python, so
      # I cannot use those.
      raise ParsingError, %(line #{linum}: Invalid syntax: "#{command.chomp}")
    end

    # String#scan will return an array with all regexp matches in the string, since the regexp uses
    # capture groups I have to also flatten the array (it is initially structured like [[match1],[match2],...])
    command.scan(TOKENIZER).flatten
  end

  # all of the valid Hack VM commands combined with the ASM substitutions as lambdas
  def self.all
    [arithmetic, logical, mem_access, branching, function] \
      .flatten.reduce(&:merge).freeze
  end

  def self.arithmetic
    {
      add: lambda do
        vputs 'Adding x to y'
        # Multi-line string literal. Indentation is removed by the Ruby interpreter.
        <<~ADD
          @SP
          AM = M - 1
          D = M
          A = A - 1
          M = D + M
        ADD
      end,
      sub: lambda do
             vputs 'Subtracting y from x'
             <<~SUB
               @SP
               AM = M - 1
               D = M
               A = A - 1
               M = M - D
             SUB
           end,
      neg: lambda do
             vputs 'Negating x'
             <<~NEG
               @SP
               A = M - 1
               M = -M
             NEG
           end
    }
  end

  def self.logical
    {
      eq: lambda do
        vputs 'x == y?'
        Parser.n_cmps += 1
        <<~EQ
          @SP
          AM = M - 1
          D = M
          A = A - 1
          D = D - M
          M = -1
          @EQ#{Parser.n_cmps}
          D;JEQ
          @SP
          A = M - 1
          M = 0
          (EQ#{Parser.n_cmps})
        EQ
      end,
      gt: lambda do
            vputs 'x > y?'
            Parser.n_cmps += 1
            <<~GT
              @SP
              AM = M - 1
              D = M
              A = A - 1
              D = D - M
              M = -1
              @GT#{Parser.n_cmps}
              D;JGT
              @SP
              A = M - 1
              M = 0
              (GT#{Parser.n_cmps})
            GT
          end,
      lt: lambda do
            vputs 'x < y?'
            Parser.n_cmps += 1
            <<~LT
              @SP
              AM = M - 1
              D = M
              A = A - 1
              D = D - M
              M = -1
              @LT#{Parser.n_cmps}
              D;JLT
              @SP
              A = M - 1
              M = 0
              (LT#{Parser.n_cmps})
            LT
          end,
      and: lambda do
             vputs 'x & y'
             <<~AND
               @SP
               AM = M - 1
               D = M
               A = A - 1
               M = D & M
             AND
           end,
      or: lambda do
            vputs 'x | y'
            <<~OR
              @SP
              AM = M - 1
              D = M
              A = A - 1
              M = D | M
            OR
          end,
      not: lambda do
             vputs '!x'
             <<~NOT
               @SP
               A = M - 1
               M = !M
             NOT
           end
    }
  end

  def self.mem_access
    {
      pop: lambda do |segment, i|
        vputs "Popping to #{segment}: #{i}"
        # check the segment
        raise ParsingError, "line #{Parser.line_num}: Invalid segment #{segment}" unless %w[local argument this that temp pointer static].include?(segment)
        # check ptr index if necessary
        raise ParsingError, "line #{Parser.line_num}: Invalid pointer #{i}" if segment == 'pointer' && i != '0' && i != '1'

        # convert to Hack's specific alias for the segment
        # a little trick here is to set temp to start at R5, as that is the temp storage space
        seg = { local: 'LCL', argument: 'ARG', this: 'THIS', that: 'THAT', temp: 'R5',
                static: (16 + i.to_i).to_s }[segment.to_sym]
        i = (i.to_i + 5).to_s if segment == 'temp'
        out = +''
        if segment == 'pointer'
          out << if i == '0'
                   "@THIS\n"
                 else
                   "@THAT\n"
                 end
          out << "D = A\n"
          # D stores address of THIS/THAT
        else
          out << <<~NPTRPOP
            @#{seg}
            D = M
            @#{i}
            D = D + A
          NPTRPOP
          # D stores address of (*segment) + i
        end
        return out << <<~POPFIN
          @R13
          M = D
          @SP
          AM = M - 1
          D = M
          @R13
          A = M
          M = D
        POPFIN
      end,
      push: lambda do |segment, i|
        # this is similar to pop, pretty much all that differs is the assembly
        # besides the fact that you can push but not pop constants
        vputs "Pushing #{segment}: #{i}"
        raise ParsingError, "line #{Parser.line_num}: Invalid segment #{segment}" unless %w[constant local argument this that temp pointer static].include?(segment)
        raise ParsingError, "line #{Parser.line_num}: Invalid pointer #{i}" if segment == 'pointer' && i != '0' && i != '1'

        seg = { local: 'LCL', argument: 'ARG', this: 'THIS', that: 'THAT', temp: 'R5',
                static: (16 + i.to_i).to_s }[segment.to_sym]
        if segment == 'constant'
          return <<~PUSHCONST
            @#{i}
            D = A
            @SP
            AM = M + 1
            A = A - 1
            M = D
          PUSHCONST
        end

        i = (i.to_i + 5).to_s if segment == 'temp'
        # using +'' rather than '' makes the string mutable since it's built over time
        out = +if segment == 'pointer'
                 if i == '0'
                   "@THIS\n"
                 else
                   "@THAT\n"
                 end
               else
                 "@#{seg}\n"
               end
        out << "D = M\n"
        if segment != 'pointer'
          out << <<~NPTRPUSH
            @#{i}
            A = A + D
            D = M
          NPTRPUSH
        end
        return out << <<~PUSHFIN
          @SP
          AM = M + 1
          A = A - 1
          M = D
        PUSHFIN
      end
    }
  end

  # this is project 8 stuff
  def self.branching
    {
      label: lambda do |label|
        vputs "Defining label #{label}"
        <<~LABEL
          (#{label})
        LABEL
      end,
      goto: lambda do |label|
        vputs "going to #{label}"
        <<~GOTO
          @#{label}
          0;JMP
        GOTO
      end,
    # have to use old Ruby hash-rocket syntax because if-goto contains a hyphen
      'if-goto'.to_sym => lambda do |label|
        vputs "going to #{label} conditionally"
        <<~IFGOTO
          @SP
          A = M - 1
          D = M
          @#{label}
          D;JLT
        IFGOTO
      end
    }
  end

  # also project 8
  def self.function
    {
      function: lambda do |name, nvars|
        vputs "Defining function #{name} with #{nvars} vars"
        out = +<<~FUNC
          (#{name})
        FUNC
        nvars.to_i.times do
          out << <<~PUSHLCL
            @SP
            AM = M + 1
            A = A - 1
            M = 0
          PUSHLCL
        end
        out
      end,
      call: lambda do |function, nargs|
        vputs "Calling function #{function} with #{nargs} args"
        # Set ARG to (sp - nArgs)
        # Push ret-addr, LCL, ARG, THIS, THAT to stack
        # Jump
        Parser.n_calls[function] += 1
        out = +''
        (["#{function}$ret.#{Parser.n_calls[function]}"] <<
          %w[LCL ARG THIS THAT]).each do |save|
          out << <<~SAVE
            @#{save}
            D = A
            @SP
            AM = M + 1
            A = A - 1
            M = D
          SAVE
        end
        out << <<~CALL
          @SP
          D = M
          @#{nargs}
          D = D - A
          @5
          D = D - A
          @ARG
          M = D
          @SP
          D = M
          @LCL
          M = D
          @#{function}
          0;JMP
          (ret#{Parser.n_calls})
        CALL
      end,
      return: lambda do
        vputs 'Returning from function'
        <<~RETURN
          @SP
          AM = M - 1
          D = M
          @ARG
          A = M
          M = D
          D = A
          @SP
          M = D + 1
          @LCL
          D = M - 1
          @R13
          AM = D
          D = M
          @THAT
          M = D
          @R13
          AM = M - 1
          D = M
          @THIS
          M = D
          @R13
          AM = M - 1
          D = M
          @ARG
          M = D
          @R13
          AM = M - 1
          D = M
          @LCL
          M = D
          @R13
          A = M - 1
          A = M
          0;JMP
        RETURN
      end
    }
  end
end

# The main parser for Hack VM.
class Parser
  class << self
    attr_accessor :str, :line_num, :n_cmps, :n_calls

    def parse(file:)
      file.each do |line|
        vputs line
        # this line could throw an exception, but any ParsingError is
        # fatal anyway
        translate(command: line, linum: @line_num)
        vp @str
        @line_num += 1
      end
    end

    def reset
      @str = ''
      @line_num = 1
      @n_cmps = 0
      @n_calls = Hash.new(0)
    end
  end
  # the output of the parser
  @str = +''
  # MEM_MAP = {
  #   SP:      0,
  #   LCL:     1,
  #   ARG:     2,
  #   THIS:    3,
  #   THAT:    4,
  #   TEMP:    5..12,
  #   GENERAL: 13...16,
  #   STATIC:  16...256,
  #   STACK:   256...2048
  # }

  # the current input line number (useful for error messages)
  @line_num = 1
  # the number of comparisons done in the VM file so far to ensure labels are always unique
  @n_cmps = 0
  @n_calls = Hash.new(0)
end

def translate(command:, linum: 0)
  # first, check for comments
  # any comment is stored in the "comment" variable so it can be preserved
  comment_i = command.index %r{//.*}
  comment = ''
  if comment_i
    comment = command[comment_i..-1]
    command = command[0...comment_i]
  end
  # return early if there is no code to parse
  return comment if /^\s+$/.match?(command)

  # leave a comment with the original VM command above each ASM chunk
  Parser.str << "// #{command}"
  tokens = COMMANDS.tokenize(command: command, linum: linum)
  # take first token as "command", the rest are arguments
  command = tokens.shift
  # look up in command hash
  translation = COMMANDS.all[command.to_sym]
  raise ParsingError, %(line #{linum}: Command not found: "#{command}") if translation.nil?

  begin
    translation = translation.call(*tokens)
  rescue ArgumentError
    raise ParsingError, +%(line #{linum}: in call to "#{command}": ) <<
                        %(Invalid number of arguments ) <<
                        %[(#{tokens.size}, expected #{translation.parameters.size})]
  end
  # implicit return, leave comments intact
  str << translation << comment
end

### Below is the main routine. ###

parse_cli_args
# sets the output file to file_basename.asm iff the input file ends in .vm
Options.out_f = Options.in_f.gsub(/\.vm$/, '.asm') if Options.in_f =~ /\.vm$/ && Options.out_f == 'output.asm'
puts
puts %(Reading from "#{Options.in_f}")
puts %(Output will be in "#{Options.out_f}")
puts

# Read the whole file in one pass
lines = IO.readlines(Options.in_f)
Parser.parse(file: lines)
# Parser stores its output in a member variable @str
vputs Parser.str
# write this string to output file
File.open(Options.out_f, 'w') { |f| f.write(Parser.str) }
