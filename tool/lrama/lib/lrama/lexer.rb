require "strscan"
require "lrama/lexer/token"

module Lrama
  class Lexer
    attr_reader :head_line, :head_column
    attr_accessor :status
    attr_accessor :end_symbol

    SYMBOLS = %w(%{ %} %% { } \[ \] : \| ;)
    PERCENT_TOKENS = %w(
      %union
      %token
      %type
      %left
      %right
      %nonassoc
      %expect
      %define
      %require
      %printer
      %lex-param
      %parse-param
      %initial-action
      %precedence
      %prec
      %error-token
      %empty
      %code
    )

    def initialize(text)
      @scanner = StringScanner.new(text)
      @head = @scanner.pos
      @line = 1
      @status = :initial
      @end_symbol = nil
    end

    def next_token
      case @status
      when :initial
        lex_token
      when :c_declaration
        lex_c_code
      end
    end

    def line
      @line
    end

    def column
      @scanner.pos - @head
    end

    def lex_token
      while !@scanner.eos? do
        case
        when @scanner.scan(/\n/)
          newline
        when @scanner.scan(/\s+/)
          # noop
        when @scanner.scan(/\/\*/)
          lex_comment
        when @scanner.scan(/\/\//)
          @scanner.scan_until(/\n/)
          newline
        else
          break
        end
      end

      @head_line = line
      @head_column = column

      case
      when @scanner.eos?
        return
      when @scanner.scan(/#{SYMBOLS.join('|')}/)
        return [@scanner.matched, @scanner.matched]
      when @scanner.scan(/#{PERCENT_TOKENS.join('|')}/)
        return [@scanner.matched, @scanner.matched]
      when @scanner.scan(/[\?\+\*]/)
        return [@scanner.matched, @scanner.matched]
      when @scanner.scan(/<\w+>/)
        return [:TAG, setup_token(Lrama::Lexer::Token::Tag.new(s_value: @scanner.matched))]
      when @scanner.scan(/'.'/)
        return [:CHARACTER, setup_token(Lrama::Lexer::Token::Char.new(s_value: @scanner.matched))]
      when @scanner.scan(/'\\\\'|'\\b'|'\\t'|'\\f'|'\\r'|'\\n'|'\\v'|'\\13'/)
        return [:CHARACTER, setup_token(Lrama::Lexer::Token::Char.new(s_value: @scanner.matched))]
      when @scanner.scan(/"/)
        return [:STRING, %Q("#{@scanner.scan_until(/"/)})]
      when @scanner.scan(/\d+/)
        return [:INTEGER, Integer(@scanner.matched)]
      when @scanner.scan(/([a-zA-Z_.][-a-zA-Z0-9_.]*)/)
        token = setup_token(Lrama::Lexer::Token::Ident.new(s_value: @scanner.matched))
        type =
          if @scanner.check(/\s*(\[\s*[a-zA-Z_.][-a-zA-Z0-9_.]*\s*\])?\s*:/)
            :IDENT_COLON
          else
            :IDENTIFIER
          end
        return [type, token]
      else
        raise ParseError, "Unexpected token: #{@scanner.peek(10).chomp}."
      end
    end

    def lex_c_code
      nested = 0
      code = ''
      while !@scanner.eos? do
        case
        when @scanner.scan(/{/)
          code += @scanner.matched
          nested += 1
        when @scanner.scan(/}/)
          if nested == 0 && @end_symbol == '}'
            @scanner.unscan
            return [:C_DECLARATION, setup_token(Lrama::Lexer::Token::UserCode.new(s_value: code))]
          else
            code += @scanner.matched
            nested -= 1
          end
        when @scanner.check(/#{@end_symbol}/)
          return [:C_DECLARATION, setup_token(Lrama::Lexer::Token::UserCode.new(s_value: code))]
        when @scanner.scan(/\n/)
          code += @scanner.matched
          newline
        when @scanner.scan(/"/)
          matched = @scanner.scan_until(/"/)
          code += %Q("#{matched})
          @line += matched.count("\n")
        when @scanner.scan(/'/)
          matched = @scanner.scan_until(/'/)
          code += %Q('#{matched})
        else
          code += @scanner.getch
        end
      end
      raise ParseError, "Unexpected code: #{code}."
    end

    private

    def lex_comment
      while !@scanner.eos? do
        case
        when @scanner.scan(/\n/)
          @line += 1
          @head = @scanner.pos + 1
        when @scanner.scan(/\*\//)
          return
        else
          @scanner.getch
        end
      end
    end

    def setup_token(token)
      token.line = @head_line
      token.column = @head_column

      token
    end

    def newline
      @line += 1
      @head = @scanner.pos + 1
    end
  end
end
