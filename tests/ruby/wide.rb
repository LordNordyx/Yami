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
elsif kind == "oldess"
  # Older Essentials (v15-v18): constants + its own Graphics.width, own camera.
  DEFAULTSCREENWIDTH = 640
  DEFAULTSCREENHEIGHT = 480
  module PBSpecies; end
  module Graphics; @@w = DEFAULTSCREENWIDTH; def self.width; @@w; end; def self.height; DEFAULTSCREENHEIGHT; end; end
  class Game_Map; def scroll_right(d); :essentials_own; end; end
  class Game_Player; def center(x, y); :essentials_own; end; end
  # Title screen is built before the first Graphics.update:
  vp = Viewport.new(0, 0, 640, 480)
  check "native screen widened to 852x480", Graphics.yami_width == 852 && Graphics.yami_height == 480
  check "DEFAULTSCREENWIDTH updated before the title is built", DEFAULTSCREENWIDTH == 852
  check "game's own Graphics.width now reports the real width", Graphics.width == 852 && Graphics.height == 480
  check "title viewport spans the full width", vp.rect == [0, 0, 852, 480]
  check "Essentials' own camera left alone", Game_Map.new.scroll_right(1) == :essentials_own && Game_Player.new.center(0, 0) == :essentials_own
  # Re-entrancy: a one-shot hook whose body creates a viewport, and game code
  # that creates viewports inside viewport constructors (stack overflow before).
  calls = 0
  pending_before = Yami.once_pending
  Yami.once_when(-> { true }) { calls += 1; Viewport.new(0, 0, 10, 10) }
  class NestVp < Viewport
    def initialize(n); super(0, 0, 640, 480); NestVp.new(n - 1) if n > 0; end
  end
  ok = begin; NestVp.new(200); true; rescue SystemStackError; false; end
  check "nested viewport creation doesn't recurse into hooks", ok
  check "one-shot hook ran exactly once and was removed", calls == 1 && Yami.once_pending == pending_before
  # Game subclass that hands a Rect to super (old Essentials helpers do this):
  # the hook must not re-dispatch to the subclass's initialize.
  class RectVp < Viewport
    def initialize(*args); args.size == 4 ? super(Rect.new(*args)) : super(*args); end
  end
  ok = begin; v = RectVp.new(0, 0, 640, 480); true; rescue SystemStackError; false; end
  check "Viewport subclass passing a Rect to super doesn't recurse", ok
  check "...and still gets the widescreen rect", ok && v.rect == [0, 0, 852, 480]
elsif kind == "resizer"
  # Older Essentials with Sprite_Resizer and the screen border turned on, as
  # in Pokemon Myth: the game asked for 800x600 and drew 640x480 in a corner.
  DEFAULTSCREENWIDTH = 640
  DEFAULTSCREENHEIGHT = 480
  BORDERWIDTH = 80
  BORDERHEIGHT = 60
  module PBSpecies; end
  class PokemonSystem; attr_accessor :screensize; def border; @border || 1; end; end
  $PokemonSystem = PokemonSystem.new
  $ResizeFactor = 1.0; $ResizeFactorMul = 100; $ResizeOffsetX = 0; $ResizeOffsetY = 0
  $refreshed = 0
  def pbRefreshResizeFactor; $refreshed += 1; end
  def pbSetResizeFactor2(factor, norecalc = false)
    if $ResizeFactor != factor
      $ResizeFactor = factor; $ResizeFactorMul = (factor * 100).to_i; pbRefreshResizeFactor
    end
    Graphics.oldresizescreen((Graphics.width + $ResizeOffsetX * 2) * factor,
                             (Graphics.height + $ResizeOffsetY * 2) * factor)
  end
  def pbConfigureWindowedScreen(value)
    if $PokemonSystem.border == 1
      $ResizeOffsetX = BORDERWIDTH; $ResizeOffsetY = BORDERHEIGHT
    else
      $ResizeOffsetX = 0; $ResizeOffsetY = 0
    end
    pbSetResizeFactor2(value, true)
  end
  def pbConfigureFullScreen; pbSetResizeFactor2(1.0); end
  def pbSetResizeFactor(factor = 1, norecalc = false)
    factor = [0.5, 1.0, 1.5, 2.0, -1][factor]
    (factor < 0) ? pbConfigureFullScreen : pbConfigureWindowedScreen(factor) unless norecalc
  end
  module Graphics
    @@width = DEFAULTSCREENWIDTH
    @@height = DEFAULTSCREENHEIGHT
    class << self
      alias oldresizescreen resize_screen
      def width; @@width.to_i; end
      def height; @@height.to_i; end
      def resize_screen(w, h); @@width = w; @@height = h; pbSetResizeFactor($ResizeFactor, true); end
      def snap_to_bitmap; raise "rubyscreen.dll"; end
    end
  end
  class Game_Map; def scroll_right(d); :essentials_own; end; end
  class Game_Player; def center(x, y); :essentials_own; end; end
  pbSetResizeFactor(1) # the game's startup call
  check "precondition: border made the screen 800x600-ish", Graphics.yami_native_height == 600
  Graphics.update
  if mode == "off"
    check "screen is exactly the game's 640x480", Graphics.yami_native_width == 640 && Graphics.yami_native_height == 480
  elsif mode == "panoramic"
    check "screen is 640x480 widened to 852x480", Graphics.yami_native_width == 852 && Graphics.yami_native_height == 480
    check "UI still sees 640", Graphics.width == 640
    check "UI viewport centred", Viewport.new(0, 0, 640, 480).rect == [106, 0, 640, 480]
  else
    check "screen is 640x480 widened to 852x480", Graphics.yami_native_width == 852 && Graphics.yami_native_height == 480
    check "game's Graphics.width reports the real width", Graphics.width == 852 && Graphics.height == 480
    v = Viewport.new(0, 0, 640, 480)
    check "640x480 viewport spans the full width", v.rect == [0, 0, 852, 480]
  end
  check "border offsets gone", $ResizeOffsetX == 0 && $ResizeOffsetY == 0 && BORDERWIDTH == 0
  check "border option off", $PokemonSystem.border == 0
  check "screenshot uses the engine, not the DLL", (Graphics.snap_to_bitmap rescue :dll) == :native_snap
  # Changing "Screen size" in the Options menu must not break it again.
  pbSetResizeFactor(3)
  pbSetResizeFactor(1)
  Graphics.resize_screen(640, 480)
  want = mode == "off" ? [640, 480] : [852, 480]
  check "options menu / resize_screen keep the right size", [Graphics.yami_native_width, Graphics.yami_native_height] == want
  check "factor stays 1", $ResizeFactor == 1.0
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
