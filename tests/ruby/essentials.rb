# Runs Yami's runtime together with REAL Pokémon Essentials v17 script
# sections (tests/fixtures/essentials17) in the game's load order, then
# replays its startup, title screen and Options-menu screen changes.
#   ruby essentials.rb <full|panoramic|off> <window|border|fullscreen>
require_relative "es_stubs"
require "tmpdir"
SCRIPTS = File.expand_path("../../app/src/main/assets/yami/scripts", __dir__)
FIX = File.expand_path("../fixtures/essentials17", __dir__)
$fails = 0
def check(name, cond); puts "#{cond ? 'PASS' : 'FAIL'} #{name}"; $fails += 1 unless cond; end

mode, start = ARGV
cfg_mode = mode
mode = "panoramic" if mode == "auto" # Essentials -> panoramic
work = Dir.mktmpdir("yami-ess")
save = File.join(work, "save"); Dir.mkdir(save)
File.write(File.join(work, "y.cfg"),
           "mode=play\nrgss=1\nwidescreen=#{cfg_mode}\nratio=#{16.0 / 9}\nsave_dir=#{save}\n")
ENV["YAMI_CFG"] = File.join(work, "y.cfg")
ENV.delete("TEMP"); ENV.delete("TMP")
Dir.chdir(work)

# The engine's preloads, in order.
%w[yami_runtime.rb yami_ruby18.rb yami_win32.rb].each { |f| load File.join(SCRIPTS, f) }

# The game's scripts, in Essentials' order (wrapped like RGSS runs them).
def game_script(name)
  eval(File.read(File.join(FIX, name)), TOPLEVEL_BINDING, name)
end
errors = []
begin
  game_script("Settings.rb")
  game_script("Win32API.rb")
  eval(<<~RB, TOPLEVEL_BINDING, "Game_Map")
    class Game_Map; attr_accessor :display_x, :display_y; def scroll_right(d); :essentials_own; end; end
    class Game_Player; def center(x, y); :essentials_own; end; end
    module PBSpecies; end
  RB
  game_script("Sprite_Resizer.rb")
  game_script("PokemonSystem.rb")
  game_script("PSystem_System_part.rb")
rescue Exception => e
  errors << "load: #{e.class}: #{e.message} @ #{e.backtrace.first}"
end
check "game scripts load without errors", errors.empty?
puts errors

# --- startup (pbSetUpSystem + mainFunctionDebug) ---
begin
  $PokemonSystem = PokemonSystem.new
  $PokemonSystem.screensize = { "window" => 1, "border" => 1, "fullscreen" => 3 }.fetch(start)
  $PokemonSystem.instance_variable_set(:@border, start == "border" ? 1 : 0)
  pbSetResizeFactor([$PokemonSystem.screensize, 3].min)
  setScreenBorderName("border")
  Graphics.update
  Graphics.update
rescue Exception => e
  errors << "startup: #{e.class}: #{e.message} @ #{e.backtrace.first(3).join(' < ')}"
end
check "startup runs without errors", errors.empty?
puts errors

nw = mode == "off" ? 640 : 852
check "engine screen is #{nw}x480", [Graphics.yami_native_width, Graphics.yami_native_height] == [nw, 480]
gw = mode == "full" ? 852 : 640
check "the game sees a #{gw}x480 screen", [Graphics.width, Graphics.height] == [gw, 480]
check "no border offsets, factor 1", $ResizeOffsetX == 0 && $ResizeOffsetY == 0 && $ResizeFactor == 1.0

# --- title screen ---
vp = Viewport.new(0, 0, Graphics.width, Graphics.height)
want = { "full" => [0, 0, 852, 480], "panoramic" => [106, 0, 640, 480], "off" => [0, 0, 640, 480] }[mode]
check "title viewport drawn at #{want.inspect}", vp.native_rect == want
check "game still reads back its own rect", vp.rect.width == Graphics.width
ui = Viewport.new(0, 0, 640, 480)
check "640x480 UI viewport drawn at #{want.inspect}", ui.native_rect == want
fade = Graphics.class_variable_get(:@@fadeoutvp)
check "fade-to-black viewport covers the whole screen", fade.native_rect == [0, 0, nw, 480]
s = Sprite.new; s.x = 10; s.y = 20
sx = mode == "panoramic" ? 116 : 10
check "sprite without viewport placed at x=#{sx}", s.native_pos == [sx, 20]
s2 = Sprite.new(vp); s2.x = 10
check "sprite inside a viewport not offset", s2.native_pos[0] == 10
check "screenshots use the engine", Graphics.snap_to_bitmap == :native_snap

# --- the map (camera, tilemap and map viewports read Graphics.width) ---
class Spriteset_Map
  attr_reader :vp, :seen_w
  def initialize; @seen_w = Graphics.width; @vp = Viewport.new(0, 0, Graphics.width, Graphics.height); end
end
# Defined after the first viewport existed, as in Essentials; map context
# comes from Yami's own wrappers.
Graphics.update
sm = Spriteset_Map.new
check "map code sees the full #{nw}-pixel width", sm.seen_w == nw
check "map viewport spans the display", sm.vp.native_rect == [0, 0, nw, 480]
check "menus still see the game's width afterwards", Graphics.width == gw

# --- image loader's Windows temp folder ---
ok = begin; Dir.chdir(ENV["TEMP"]) { File.write("t.png", "x") }; true; rescue StandardError => e; puts e.message; false; end
check "ENV['TEMP'] is a usable folder", ok

# --- Options menu: screen size changes ---
begin
  [3, 0, 2, 1].each do |v|
    $PokemonSystem.screensize = v
    pbSetResizeFactor($PokemonSystem.screensize)
    Graphics.update
  end
  $PokemonSystem.instance_variable_set(:@border, 1)
  pbSetResizeFactor(1)
  Graphics.update
  Graphics.resize_screen(640, 480)
  Graphics.update
rescue Exception => e
  errors << "options: #{e.class}: #{e.message} @ #{e.backtrace.first(3).join(' < ')}"
end
check "Options screen-size/border changes run without errors", errors.empty?
puts errors
check "...and the screen stays #{nw}x480", [Graphics.yami_native_width, Graphics.yami_native_height] == [nw, 480]
check "...offsets/factor still neutral", $ResizeOffsetX == 0 && $ResizeOffsetY == 0 && $ResizeFactor == 1.0
check "...existing title viewport unchanged", vp.native_rect == want
check "engine never asked for a bordered size", Graphics.resizes.none? { |w, h| h > 480 }
check "no message boxes", $msgboxes == 0
puts($fails.zero? ? "ALL PASS" : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)
