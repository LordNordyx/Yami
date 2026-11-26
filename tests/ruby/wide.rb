require "fileutils"
require_relative "stubs"
require "tmpdir"
WORK = ENV.fetch("WORK") { Dir.mktmpdir("yami") }
SCRIPTS = File.expand_path("../../app/src/main/assets/yami/scripts", __dir__)
$fails = 0
def check(name, cond); puts "#{cond ? 'PASS' : 'FAIL'} #{name}"; $fails += 1 unless cond; end
mode, kind = ARGV
File.write(WORK + "/w.cfg", "mode=play\nwidescreen=#{mode}\nratio=#{16.0/9}\n"); ENV["YAMI_CFG"] = WORK + "/w.cfg"
Dir.chdir(WORK)
load "#{SCRIPTS}/yami_runtime.rb"
if kind == "xp"
  check "XP default widened to 16:9 at 480p", Graphics.width == 852 && Graphics.height == 480
  class Game_Map; attr_accessor :display_x, :display_y; def width; 100; end; def height; 100; end
    def scroll_right(d); @display_x = [@display_x + d, (width - 20) * 128].min; end; end
  class Game_Player; CENTER_X = (320 - 16) * 4; CENTER_Y = (240 - 16) * 4; def center(x, y); end; end
  $game_map = Game_Map.new; $game_map.display_x = 0; $game_map.display_y = 0
  Graphics.update
  check "CENTER_X recomputed for 852 px", Game_Player::CENTER_X == (426 - 16) * 4
  $game_map.display_x = 0; $game_map.scroll_right(1_000_000)
  check "scroll clamp uses real width", $game_map.display_x == 100 * 128 - 852 * 4
  Game_Player.new.center(99, 99)
  check "center clamps to map edge", $game_map.display_x == 100 * 128 - 852 * 4
  v = Viewport.new(0, 0, 640, 480)
  check "stock 640x480 map viewport spans full width", v.rect == [0, 0, 852, 480]
else # essentials
  module Settings; SCREEN_WIDTH = 512; SCREEN_HEIGHT = 384; end
  Graphics.resize_screen(512, 384)
  check "resize_screen(512,384) widened", Graphics.yami_width == 684 && Graphics.height == 384
  class Game_Map; TILE_WIDTH = 32; X_SUBPIXELS = 4; def update; Graphics.width; end; end
  class Game_Player; SCREEN_CENTER_X = 999; end
  class Spriteset_Map; def initialize; @vp = Viewport.new(0, 0, Graphics.width, Graphics.height); end; attr_reader :vp; end
  Graphics.update
  check "Game_Player::SCREEN_CENTER_X uses real width", Game_Player::SCREEN_CENTER_X == ((684 / 2) - 16) * 4
  if mode == "full"
    check "Settings::SCREEN_WIDTH updated", Settings::SCREEN_WIDTH == 684
    check "Graphics.width is real width", Graphics.width == 684
  else
    check "Settings::SCREEN_WIDTH kept for UI", Settings::SCREEN_WIDTH == 512
    check "UI sees base width", Graphics.width == 512
    check "map code sees full width", Game_Map.new.update == 684
    check "map viewport full width", Spriteset_Map.new.vp.rect == [0, 0, 684, 384]
    check "UI viewport centered", Viewport.new(0, 0, 512, 384).rect == [86, 0, 512, 384]
    s = Sprite.new; s.x = 10
    check "nil-viewport sprite offset, logical x preserved", s.x == 10 && s.instance_variable_get(:@x) == 96
    w = Window.new; w.x = 0
    check "window offset", w.instance_variable_get(:@x) == 86 && w.x == 0
    s2 = Sprite.new(Viewport.new(0, 0, 10, 10)); s2.x = 5
    check "sprite inside viewport not double-offset", s2.instance_variable_get(:@x) == 5
  end
end
check "runtime never opens message boxes (print/p)", $msgboxes == 0
puts($fails.zero? ? "ALL PASS" : "#{$fails} FAILED")

exit($fails.zero? ? 0 : 1)
