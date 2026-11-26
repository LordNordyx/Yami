# Ruby 1.8 compatibility: translate scripts that only fail because of 1.8 syntax.
require_relative "stubs"
SCRIPTS = File.expand_path("../../app/src/main/assets/yami/scripts", __dir__)
$fails = 0
def check(name, cond); puts "#{cond ? 'PASS' : 'FAIL'} #{name}"; $fails += 1 unless cond; end
load "#{SCRIPTS}/yami_ruby18.rb"

def compile_error(src)
  RubyVM::InstructionSequence.compile(src, "t")
  nil
rescue SyntaxError => e
  e.message
end

# --- the failing line from Pokémon Essentials' PSystem_Utilities (JSON decoder) ---
json = <<'RUBY'
module MiniJSON
  def self.decode_string(str)
    if str[/\A"[^"\\\n\r\x00-\x1f\x7f-\x9f]*"/]
      return $~[0][1..-2]
    end
    nil
  end
  def self.binary?(s)
    s =~ /[\x80-\xff]/ ? true : false
  end
end
RUBY
err = compile_error(json)
check "original fails like on the device", err.to_s.include?("invalid multibyte escape")
fixed = Yami.fix_script(json, "277:PSystem_Utilities", err)
check "translated script compiles", fixed && compile_error(fixed).nil?
eval(fixed)
check "JSON string regexp still matches", MiniJSON.decode_string('"hello" rest') == "hello"
check "control chars still excluded", MiniJSON.decode_string("\"a\x01b\"").nil?
check "\\x80-\\xff → any non-ASCII", MiniJSON.binary?("Pokémon") && !MiniJSON.binary?("Pokemon")

# --- when x: / if x: ---
old_case = <<'RUBY'
def kind(x)
  case x
  when 1: "one"
  when 2, 3: "few"
  when "a:b": "str"
  when :sym then "sym"
  when Math::PI: "pi"
  else "other"
  end
end
def t(x)
  if x > 1: "big"
  else "small"
  end
end
RUBY
err = compile_error(old_case)
check "when-colon fails today", !err.nil?
fixed = Yami.fix_script(old_case, "010:Old", err)
check "when/if-colon translated + compiles", fixed && compile_error(fixed).nil?
eval(fixed)
check "when semantics", kind(Math::PI) == "pi" && kind(1) == "one" && kind(3) == "few" && kind("a:b") == "str" && kind(:sym) == "sym" && kind(9) == "other"
check "if semantics", t(5) == "big" && t(0) == "small"

# --- things that must not change ---
safe = <<'RUBY'
a = 10 / 2 / 5
b = x ? 1 : 2 rescue 0
h = { :a => 1, b: 2 }
s = "x:y"
r = /a:b/
c = Foo::Bar rescue nil
RUBY
check "valid code is left alone by translate", Yami::Ruby18.translate(safe) == safe

# --- unrelated syntax errors keep the original error ---
broken = "def x(\n  1 +\n"
check "unfixable script → nil (original error shown)", Yami.fix_script(broken, "099:Broken", compile_error(broken)).nil?

# --- shims ---
check "Hash#index (1.8)", ({ a: 1, b: 2 }.index(2) == :b)
check "Array#nitems", [1, nil, 2].nitems == 2
check "Fixnum constant", 5.is_a?(Fixnum)
check "no message boxes", $msgboxes == 0
puts($fails.zero? ? "ALL PASS" : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)
