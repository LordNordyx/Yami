# =============================================================================
#  Yami Ruby 1.8 compatibility
#
#  RPG Maker XP shipped Ruby 1.8; the engine runs Ruby 3.1. Two parts:
#
#  1. Yami.fix_script(source, name, message) — called by the engine only when
#     a game script fails to compile. It rewrites the 1.8 constructs that are
#     syntax errors today and returns the result if it compiles (otherwise nil,
#     and the original error is shown). Scripts that compile are never touched.
#
#  2. Methods 1.8 had and modern Ruby removed, added only when missing.
#
#  NOTE: never use print/p here (RGSS shows a message box).
# =============================================================================

module Yami
  module Ruby18
    module_function

    def log(msg)
      if Yami.respond_to?(:log) then Yami.log(msg)
      else (STDERR.write("[yami] #{msg}\n") rescue nil)
      end
    end

    # --- \xHH escapes ≥ 0x80 inside regexp literals --------------------------
    # 1.8 regexps were byte-based; in a UTF-8 regexp "\x9f" is an invalid
    # multibyte escape. Use the code point instead (what the authors meant for
    # control/Latin-1 ranges); a range ending at \xff means "any non-ASCII".
    HIGH_ESC = /\\x([89a-fA-F][0-9a-fA-F])/

    def fix_regexp_body(body)
      body = body.gsub(/\\x([0-7][0-9a-fA-F])-\\x[fF][fF]/) { "\\x#{$1}-\\u{10FFFF}" }
      body = body.gsub(/\\x([89a-fA-F][0-9a-fA-F])-\\x[fF][fF]/) { "\\u00#{$1.upcase}-\\u{10FFFF}" }
      body.gsub(HIGH_ESC) { "\\u00#{$1.upcase}" }
    end

    # Regexp literal: a '/' where an operand is expected (after an operator,
    # '(' ',' or a keyword), up to the next unescaped '/' on the same line.
    REGEXP_LITERAL = %r{
      (?<pre>(?:^|[=~(,!|&\{\[;?:]|\b(?:when|if|elsif|unless|while|until|and|or|not|return|split|scan|sub!?|gsub!?|match|index|slice!?|grep|=~))\s*)
      /(?<body>(?:\\.|\[(?:\\.|[^\]\\\n])*\]|[^/\\\n\[])+)/(?<flags>[imxounse]*)
    }x

    def fix_regexps(src)
      src.gsub(REGEXP_LITERAL) do
        m = Regexp.last_match
        body = m[:body]
        if body =~ HIGH_ESC && !m[:flags].include?("n")
          "#{m[:pre]}/#{fix_regexp_body(body)}/#{m[:flags]}"
        else
          m[0]
        end
      end
    end

    # --- `when x: stmt` → `when x then stmt` ---------------------------------
    WHEN_COLON = /^(\s*when\s+(?:[^:'"\n#]|::|'[^'\n]*'|"[^"\n]*")+?)\s*:(?=\s|$)(?!:)/

    def fix_when_colon(src)
      src.gsub(WHEN_COLON) { "#{$1} then" }
    end

    # --- `if x: stmt` / `unless x: stmt` (1.8) → `then` ------------------------
    IF_COLON = /^(\s*(?:if|elsif|unless)\s+(?:[^:?'"\n#]|::|'[^'\n]*'|"[^"\n]*")+?)\s*:(?=\s+\S)(?!:)/

    def fix_if_colon(src)
      src.gsub(IF_COLON) { "#{$1} then" }
    end

    RULES = %i[fix_regexps fix_when_colon fix_if_colon].freeze

    def translate(src)
      RULES.reduce(src) { |s, rule| send(rule, s) }
    end

    def compiles?(src, name)
      RubyVM::InstructionSequence.compile(src, name.to_s)
      true
    rescue SyntaxError
      false
    end
  end

  def self.fix_script(src, name, message)
    first = message.to_s.lines.first.to_s.strip
    fixed = Ruby18.translate(src.dup.force_encoding(Encoding::UTF_8))
    if fixed == src
      Ruby18.log("script #{name}: no Ruby 1.8 fix for: #{first}")
      return nil
    end
    unless Ruby18.compiles?(fixed, name)
      Ruby18.log("script #{name}: Ruby 1.8 rewrite still doesn't compile (#{first})")
      return nil
    end
    Ruby18.log("script #{name}: applied Ruby 1.8 compatibility (#{first})")
    fixed
  rescue StandardError => e
    Ruby18.log("script #{name}: fix_script failed: #{e.class}: #{e.message}")
    nil
  end
end

# ---------------------------------------------------------------------------
#  Removed-in-1.9+ methods that old RGSS scripts call. Only methods whose
#  absence can't be relied on by working code (no Object#id/#type,
#  String#each/#to_a: those would change respond_to? and Kernel#Array).
# ---------------------------------------------------------------------------
class Hash
  unless method_defined?(:index)
    def index(value) # 1.8 Hash#index(value) → key
      key(value)
    end
  end
end

class Array
  unless method_defined?(:nitems)
    def nitems
      count { |x| !x.nil? }
    end
  end
  unless method_defined?(:choice)
    def choice
      sample
    end
  end
end

unless defined?(Fixnum)
  Fixnum = Integer
  Bignum = Integer
end
