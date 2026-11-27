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
#  Ruby 1.8 core methods that 1.9+ removed. RPG Maker XP and VX ran Ruby 1.8,
#  so every script in those games was written expecting them; restoring them
#  matches what the code was tested against. VX Ace (Ruby 1.9) is left alone.
#  Each is defined only if missing.
# ---------------------------------------------------------------------------
module Yami
  module Ruby18
    def self.rgss
      v = (defined?(Yami) && Yami.respond_to?(:cfg)) ? Yami.cfg("rgss").to_i : 0
      v = ENV["YAMI_RGSS"].to_i if v == 0
      v == 0 ? 1 : v
    end

    def self.define_missing(klass, name, &body)
      return if klass.method_defined?(name) || klass.private_method_defined?(name)
      klass.send(:define_method, name, &body)
    end

    def self.define_missing_singleton(klass, name, &body)
      return if klass.respond_to?(name, true)
      klass.define_singleton_method(name, &body)
    end

    def self.install_core_shims
      # Thread.critical= was 1.8's "don't switch threads" flag; with the GVL and a
      # single game thread a no-op is equivalent.
      define_missing_singleton(Thread, :critical) { @yami_critical || false }
      define_missing_singleton(Thread, :critical=) { |v| @yami_critical = v ? true : false }
      define_missing_singleton(Thread, :exclusive) { |&b| b.call }

      define_missing(Hash, :index) { |value| key(value) }
      define_missing(Hash, :indexes) { |*keys| values_at(*keys) }
      define_missing(Hash, :indices) { |*keys| values_at(*keys) }
      define_missing(Array, :nitems) { count { |x| !x.nil? } }
      define_missing(Array, :choice) { sample }
      define_missing(Array, :indexes) { |*i| values_at(*i) }
      define_missing(Array, :indices) { |*i| values_at(*i) }
      define_missing(String, :each) { |*a, &b| each_line(*a, &b) }
      define_missing(Object, :id) { object_id }
      define_missing(Object, :type) { self.class }
      define_missing(Object, :to_a) { [self] }
      install_proc18
    end

    # Ruby 1.8's Kernel#proc made a lambda: `return` inside it returned from the
    # proc. Since 1.9 it is a plain Proc, whose `return` tries to leave the
    # method that created it; if that method has finished (handlers defined at
    # script load and called later, as custom pause menus do), Ruby raises
    # LocalJumpError "unexpected return". This turns that case back into the
    # 1.8 result: the proc returns the value. Arity/parameters are preserved
    # (Essentials' events dispatch on callback.arity); lambda and Proc.new
    # are untouched.
    def self.install_proc18
      return if Kernel.private_method_defined?(:yami_proc19)
      Kernel.module_eval do
        alias_method :yami_proc19, :proc
        private :yami_proc19
        def proc(&body)
          return yami_proc19 unless body # raises as Ruby 3 does without a block
          return body if body.lambda?
          wrapped = ::Proc.new do |*a, &blk|
            begin
              body.call(*a, &blk)
            rescue LocalJumpError => e
              raise unless e.reason == :return
              e.exit_value
            end
          end
          wrapped.define_singleton_method(:arity) { body.arity }
          wrapped.define_singleton_method(:parameters) { body.parameters }
          wrapped.define_singleton_method(:source_location) { body.source_location }
          wrapped
        end
        private :proc
      end
    end
  end
end

Yami::Ruby18.install_core_shims if Yami::Ruby18.rgss <= 2

unless defined?(Fixnum)
  Fixnum = Integer
  Bignum = Integer
end
