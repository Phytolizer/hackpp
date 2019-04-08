# frozen_string_literal: true

class ParsingError < RuntimeError
end

def parse_cli_args
  skip = false
  ARGV.each_with_index do |arg, i|
    if skip
      skip = false
      next
    end
    if arg.start_with?('-')
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
      print_help unless Options.in_f.nil?
      Options.in_f = arg
    end
  end
  print_help if Options.in_f.nil?
end

def print_help(long: false)
  if long
    puts %(ruby #{$PROGRAM_NAME} -- Converts Hack VM code into Hack ASM.
Written by Kyle Coffey.
Usage: ruby #{$PROGRAM_NAME} [-v] filename [-o outputfile]
Options:
  -h   Print this help message.
  -v   Enable verbose output.
  -o outputfile   Store output in outputfile. Default: output.asm
    )
  else
    puts %(Usage: ruby #{$PROGRAM_NAME} [-v] filename [-o outputfile]
Type "ruby #{$PROGRAM_NAME} -h" for more information.)
  end
  exit(0)
end

# Command-line options
class Options
  class << self
    attr_accessor :verbose, :in_f, :out_f
  end

  @verbose = false
  @in_f = nil
  @out_f = 'output.asm'
end

def vputs(*args)
  puts(*args) if Options.verbose
end

def vp(*args)
  p(*args) if Options.verbose
end

# Contains methods for all transformations involved
# when parsing Hack VM code as well as some helper methods to
# validate syntax.
module COMMANDS
  COMMAND_PATTERN = /[\w\-\h]+/.freeze
  TOKENIZER = /([\w\-]+)\h*/.freeze

  def self.tokenize(command:, linum:)
    (command !~ COMMAND_PATTERN) &&
      (raise ParsingError, %(line #{linum}: Invalid syntax: "#{command.chomp}"))

    command.scan(TOKENIZER).flatten
  end

  def self.all
    [arithmetic, logical, mem_access, branching, function] \
      .flatten.reduce(&:merge).freeze
  end

  def self.arithmetic
    {
      add: lambda do
        vputs 'Adding x to y'
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
        vputs 'Equality test: x == 0'
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
        raise ParsingError, "line #{Parser.line_num}: Invalid segment #{segment}" unless
          %w[local argument this that temp pointer static].include?(segment)
        raise ParsingError, "line #{Parser.line_num}: Invalid pointer #{i}" if
          segment == 'pointer' && i != '0' && i != '1'

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
        else
          out << <<~NPTRPOP
            @#{seg}
            D = M
            @#{i}
            D = D + A
          NPTRPOP
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
        vputs "Pushing #{segment}: #{i}"
        raise ParsingError, "line #{Parser.line_num}: Invalid segment #{segment}" unless
          %w[constant local argument this that temp pointer static].include?(segment)
        raise ParsingError, "line #{Parser.line_num}: Invalid pointer #{i}" if
          segment == 'pointer' && i != '0' && i != '1'

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
        out = +''
        out << if segment == 'pointer'
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

  def self.branching
    {
      label: lambda do |label|
        vputs "Defining label #{label}"
      end,
      goto: lambda do |label|
        vputs "going to #{label}"
      end,
      'if-goto' => lambda do |label|
        vputs "going to #{label} conditionally"
      end
    }
  end

  def self.function
    {
      function: lambda do |name, nargs|
        vputs "Defining function #{name} with #{nargs} args"
      end,
      call: lambda do |function, nargs|
        vputs "Calling function #{function} with #{nargs} args"
      end,
      return: lambda do
        vputs 'Returning from function'
      end
    }
  end
end

# The main parser for Hack VM.
class Parser
  class << self
    attr_accessor :str, :line_num, :n_cmps

    def parse(file:)
      file.each do |line|
        vputs line
        begin
          if !%r{^//.*$}.match?(line)
            translate(command: line, linum: @line_num)
          else
            @str << line
          end
        rescue ParsingError => e
          puts e
          exit(1)
        end
        vp @str
        @line_num += 1
      end
    end

    def reset
      @str = ''
      @line_num = 1
      @n_cmps = 0
    end
  end
  @str = +''
  MEM_MAP = {
    SP: 0,
    LCL: 1,
    ARG: 2,
    THIS: 3,
    THAT: 4,
    TEMP: 5..12,
    GENERAL: 13...16,
    STATIC: 16...256,
    STACK: 256...2048
  }.freeze
  @line_num = 1
  @n_cmps = 0
end

def translate(command:, linum: 0)
  # TODO
  comment_i = command.index %r{//.*}
  comment = ''
  if comment_i
    comment = command[comment_i..-1]
    command = command[0...comment_i]
  end
  return comment if /^\s+$/.match?(command)

  Parser.str << "// #{command}"
  tokens = COMMANDS.tokenize(command: command, linum: linum)
  command = tokens.shift
  translation = COMMANDS.all[command.to_sym]
  raise ParsingError, %(line #{linum}: Command not found: "#{command}") if
    translation.nil?

  begin
    translation = translation.call(*tokens)
  rescue ArgumentError
    raise ParsingError, +%(line #{linum}: in call to "#{command}": ) <<
                        %(Invalid number of arguments ) <<
                        %[(#{tokens.size}, expected #{translation.parameters.size})]
  end
  str << translation << comment unless translation.nil?
end

parse_cli_args
Options.out_f = Options.in_f.gsub(/\.vm$/, '.asm') if Options.in_f =~ /\.vm$/ && Options.out_f == 'output.asm'
puts
puts %(Reading from "#{Options.in_f}")
puts %(Output will be in "#{Options.out_f}")
puts

file = Options.in_f
lines = IO.readlines(file)
Parser.parse(file: lines)
puts Parser.str
File.open(Options.out_f, 'w') { |f| f.write(Parser.str) }
