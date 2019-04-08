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

def print_help
  %(Usage: #{ARGV[0]} [-v] filename [-o outputfile]
Type "#{ARGV[0]} -h" for more information.)
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

# Contains methods for all transformations involved
# when parsing Hack VM code as well as some helper methods to
# validate syntax.
module COMMANDS
  COMMAND_PATTERN = /[\w\-\h]+/.freeze
  TOKENIZER = /([\w\-]+)\h*/.freeze

  def self.tokenize(command)
    (command !~ COMMAND_PATTERN) &&
      (raise ParsingError, %(Invalid syntax: "#{command.chomp}"))

    command.scan(TOKENIZER).flatten
  end

  def self.get(command)
    result = all[command.to_sym]
    raise ParsingError, %(Unknown command "#{command}") if result.nil?

    result
  end

  def self.all
    [arithmetic, logical, mem_access, branching, function].flatten.reduce(&:merge).freeze
  end

  def self.arithmetic
    {
      add: lambda do
        vputs 'Adding x to y'
      end,
      sub: lambda do
        vputs 'Subtracting y from x'
      end,
      neg: lambda do
        vputs 'Negating x'
      end
    }
  end

  def self.logical
    {
      eq: lambda do
        vputs 'Equality test: x == 0'
      end,
      gt: lambda do
        vputs 'x > y?'
      end,
      lt: lambda do
        vputs 'x < y?'
      end,
      and: lambda do
        vputs 'x && y?'
      end,
      or: lambda do
        vputs 'x || y?'
      end,
      not: lambda do
        vputs '!x?'
      end

    }
  end

  def self.mem_access
    {
      pop: lambda do |segment, i|
        vputs "Popping to #{segment}: #{i}"
      end,
      push: lambda do |segment, i|
        vputs "Pushing #{segment}: #{i}"
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
        puts line
        begin
          translate(str: @str, command: line, linum: @line_num)
        rescue ParsingError => e
          puts e
        end
        @line_num += 1
      end
    end

    def reset
      @str = ''
      @line_num = 1
      @n_cmps = 0
    end
  end
  @str = ''
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

def translate(str:, command:, linum: 0)
  # TODO
  str << "// #{command}\n"
  tokens = COMMANDS.tokenize(command)
  command = tokens.shift
  translation = COMMANDS.all[command.to_sym]
  raise ParsingError, %(Command not found: "#{command}") if translation.nil?

  begin
    translation = translation.call(*tokens)
  rescue ArgumentError
    raise ParsingError, %(line #{linum}: in call to "#{command}": ) <<
                        %(Invalid number of arguments ) <<
                        %[(#{tokens.size}, expected #{translation.parameters.size})]
  end
  puts translation
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
