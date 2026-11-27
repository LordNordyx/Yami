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
# BitmapCache in Pokémon Essentials:  Thread.critical = true ... Thread.critical = false
Thread.critical = true
check "Thread.critical= / Thread.critical (1.8)", Thread.critical == true
Thread.critical = false
check "Thread.critical resets", Thread.critical == false
check "Thread.exclusive runs the block", Thread.exclusive { 7 } == 7
check "Hash#indexes", ({ a: 1, b: 2 }.indexes(:b, :a) == [2, 1])
check "Array#indexes", [10, 20, 30].indexes(2, 0) == [30, 10]
lines = []; "a\nb\n".each { |l| lines << l }
check "String#each iterates lines", lines == ["a\n", "b\n"]
o = Object.new
check "Object#id → object_id", o.id == o.object_id
check "Object#type → class", o.type == Object
check "Object#to_a → [self]", o.to_a == [o] && Array(o) == [o] && [*o] == [o]
check "attribute ids win over Object#id", Struct.new(:id).new(5).id == 5
skipped = `#{RbConfig.ruby} -e 'ENV["YAMI_RGSS"]="3"; def print(*); end; load ARGV[0]; puts Thread.respond_to?(:critical=)' #{SCRIPTS}/yami_ruby18.rb 2>/dev/null`.strip
check "VX Ace (RGSS3) keeps modern Ruby (no shims)", skipped == "false"
# --- Kernel#proc: 1.8 return semantics (crash: 'Pause Menu' unexpected return) ---
# Handlers built by a script and called later, after their creator returned
# (mkxp-z runs sections from C: a `return` there raises LocalJumpError).
MENU_CMDS = eval(<<~RB, TOPLEVEL_BINDING, "120:Pause Menu")
  def yami_t_menu_cmds; [proc { |m| return :bag if m == 1; :other }, proc { return 5 }]; end
  yami_t_menu_cmds
RB
r = begin; [MENU_CMDS[0].call(1), MENU_CMDS[0].call(2), MENU_CMDS[1].call]; rescue LocalJumpError => e; e; end
check "proc { return } defined at load, called later: returns its value (1.8)", r == [:bag, :other, 5]
h = proc { |sender, a, b| [sender, a, b] }
check "arity preserved (Essentials' events dispatch on it)", h.arity == 3 && proc { |x| }.arity == 1 && proc {}.arity == 0
check "lenient arguments kept", h.call(1) == [1, nil, nil] && proc { |a, b| [a, b] }.call([1, 2]) == [1, 2]
check "lambda untouched", lambda { |x| x }.lambda? && (begin; lambda { |x| }.call; false; rescue ArgumentError; true; end)
check "Proc.new untouched", Proc.new { 1 }.call == 1
def yami_t_block_arg; proc { |x| x * 2 }; end
check "proc with block value", yami_t_block_arg.call(4) == 8
def yami_t_dead; proc { return :from_dead_home }; end
check "return after the defining method finished (the crash)", yami_t_dead.call == :from_dead_home
unwrapped = `#{RbConfig.ruby} -e 'def m; proc { return 1 }; end; begin; m.call; rescue LocalJumpError; puts :lje; end'`.strip
check "precondition: plain Ruby 3 raises LocalJumpError here", unwrapped == "lje"
check "next / break-free results", [1, 2, 3].map(&proc { |x| next x + 1 }) == [2, 3, 4]
def yami_t_nested; proc { [1, 2].each { |x| return x * 10 if x == 2 }; :none }; end
check "return from nested block inside a proc", yami_t_nested.call == 20
def yami_t_live; p2 = proc { return :inner }; v = p2.call; [:after, v]; end
check "return while the defining method is still running behaves like Ruby 3 (no crash)", yami_t_live == :inner
check "proc without a block still raises", (begin; proc; false; rescue ArgumentError; true; end)
check "no message boxes", $msgboxes == 0
puts($fails.zero? ? "ALL PASS" : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)
