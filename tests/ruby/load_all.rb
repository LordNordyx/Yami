# Loads every script section of a complete Essentials project, in order,
# through Yami's preloads, like mkxp-z does (SyntaxError -> Yami.fix_script).
#   ruby load_all.rb <dir with "[NNN] Name.rb" files> [rpg1.rb]
require_relative "es_stubs"
require "tmpdir"
require "zlib"
SCRIPTS = File.expand_path("../../app/src/main/assets/yami/scripts", __dir__)
dir, rpg1 = ARGV
work = Dir.mktmpdir("yami-all"); save = File.join(work, "save"); Dir.mkdir(save)
File.write(File.join(work, "y.cfg"), "mode=play\nrgss=1\nwidescreen=full\nratio=#{16.0 / 9}\nsave_dir=#{save}\n")
ENV["YAMI_CFG"] = File.join(work, "y.cfg")
ENV.delete("TEMP")
Dir.chdir(work)
File.write("Game.ini", "[Game]\r\nTitle=Test\r\n")
eval(File.read(rpg1), TOPLEVEL_BINDING, "rpg1") if rpg1 && File.exist?(rpg1)
%w[yami_runtime.rb yami_ruby18.rb yami_win32.rb].each { |f| load File.join(SCRIPTS, f) }

files = Dir.children(dir).select { |f| f =~ /\A\[(\d+)\] .*\.rb\z/ }.sort_by { |f| f[/\d+/].to_i }
files.reject! { |f| f =~ /\] Main\.rb\z/ } # runs the game loop
errors = []
fixed = 0
files.each do |f|
  src = File.read(File.join(dir, f), encoding: "UTF-8")
  name = f.sub(/\.rb\z/, "")
  begin
    begin
      RubyVM::InstructionSequence.compile(src, name)
    rescue SyntaxError => e
      fix = Yami.fix_script(src, name, e.message)
      raise e unless fix
      src = fix; fixed += 1
    end
    eval(src, TOPLEVEL_BINDING, name)
  rescue Exception => e
    errors << "#{name}: #{e.class}: #{e.message.lines.first.chomp} @ #{e.backtrace&.first}"
  end
end
puts "scripts: #{files.size}, Ruby 1.8 fixes: #{fixed}, errors: #{errors.size}"
puts errors
puts "message boxes: #{$msgboxes}"
exit(errors.empty? && $msgboxes.zero? ? 0 : 1)
