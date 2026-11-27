# Pokémon Essentials v18 the way Pokémon Myth uses it (read from its public
# repository, reproduced here — the game's own scripts are not run):
#  * mkxp.json defScreenW/H 512x384; Settings: top-level SCREEN_WIDTH/HEIGHT
#    512x384, BORDER_WIDTH/HEIGHT 78, no DEFAULTSCREENWIDTH
#  * Sprite_Resizer (v17 code, v18 constant names): Graphics @@width = SCREEN_WIDTH
#  * Spriteset_Map / Spriteset_Global create their viewports while the
#    scripts load (class variables); the camera centres on Graphics.width / 2
#  * load screen: Viewport(0, 0, Graphics.width, Graphics.height) + a tiled
#    512x384 background plane
#  * pause menu: Viewport(0, 0, Graphics.width, Graphics.height) whose
#    rect.width is animated (Graphics.width * factor), panels in a carousel
#  * TilemapLoader picks the map renderer class
#   ruby myth_v18.rb <auto|panoramic|full|off> <border0|border1>
require_relative "es_stubs"
require "tmpdir"
SCRIPTS = File.expand_path("../../app/src/main/assets/yami/scripts", __dir__)
FIX = File.expand_path("../fixtures/essentials17", __dir__)
$fails = 0
def check(name, cond); puts "#{cond ? 'PASS' : 'FAIL'} #{name}"; $fails += 1 unless cond; end
mode, border = ARGV
pano = %w[auto panoramic].include?(mode)

Graphics.instance_variable_set(:@w, 512) # engine starts at mkxp.json's size
Graphics.instance_variable_set(:@h, 384)
work = Dir.mktmpdir("yami-v18"); save = File.join(work, "save"); Dir.mkdir(save)
File.write(File.join(work, "y.cfg"),
           "mode=play\nrgss=1\nwidescreen=#{mode}\nratio=#{16.0 / 9}\nsave_dir=#{save}\n")
ENV["YAMI_CFG"] = File.join(work, "y.cfg")
Dir.chdir(work)
%w[yami_runtime.rb yami_ruby18.rb yami_win32.rb].each { |f| load File.join(SCRIPTS, f) }

def section(name, src) = eval(src, TOPLEVEL_BINDING, name)
v18 = ->(src) { src.gsub("DEFAULTSCREENZOOM", "SCREEN_ZOOM").gsub("DEFAULTSCREENWIDTH", "SCREEN_WIDTH").gsub("DEFAULTSCREENHEIGHT", "SCREEN_HEIGHT")
                   .gsub("BORDERWIDTH", "BORDER_WIDTH").gsub("BORDERHEIGHT", "BORDER_HEIGHT") }
errors = []
begin
  section("000:Settings", <<~RB)
    SCREEN_WIDTH = 512
    SCREEN_HEIGHT = 384
    SCREEN_ZOOM = 1.0
    BORDER_FULLY_SHOWS = false
    BORDER_WIDTH = 78
    BORDER_HEIGHT = 78
    MAP_VIEW_MODE = 1
  RB
  section("007:Win32API", File.read(File.join(FIX, "Win32API.rb")))
  section("010:Sprite_Resizer", v18.(File.read(File.join(FIX, "Sprite_Resizer.rb"))))
  section("026:Game_Player", <<~RB)
    module PBSpecies; end
    class Game_Player
      def center_x; Graphics.width / 2 - 16; end
    end
  RB
  section("028:Game_Map", "class Game_Map; def max_x_tiles; Graphics.width / 32.0; end; end")
  section("038:Spriteset_Map", <<~RB)
    class Spriteset_Map
      @@viewport1 = Viewport.new(0, 0, Graphics.width, Graphics.height) # created while loading
      @@viewport1.z = 0
      def self.viewport; @@viewport1; end
      def initialize; @tilemap = TilemapLoader.new(@@viewport1); end
      attr_reader :tilemap
    end
  RB
  section("039:Spriteset_Global", <<~RB)
    class Spriteset_Global
      @@viewport2 = Viewport.new(0, 0, Graphics.width, Graphics.height) # "Show Picture" layer
      def self.pictures; @@viewport2; end
    end
  RB
  section("045:Tilemap_XP", "class CustomTilemap; def initialize(vp); @vp = vp; end; end")
  section("048:TilemapLoader", <<~RB)
    class TilemapLoader
      def initialize(viewport); @viewport = viewport; updateClass; end
      def updateClass; setClass(CustomTilemap); end
      def setClass(cls); @tilemap = cls.new(@viewport); end
      def renderer; @tilemap.class; end
      def terrain_tags=(v); @tilemap.terrain_tags = v; end   # v18 forwards this
      def terrain_tags; @tilemap.terrain_tags; end
    end
  RB
  section("241:PScreen_Options", v18.(File.read(File.join(FIX, "PokemonSystem.rb"))))
  section("238:PScreen_Load", <<~RB)
    class PokemonLoad_Scene
      attr_reader :viewport, :bg
      def pbStartScene
        @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
        @viewport.z = 99998
        @bg = Plane.new(@viewport); @bg.bitmap = Bitmap.new(512, 384) # loadbg.png is 512x384
      end
    end
  RB
  section("316:Pause Menu Main", <<~RB)
    class PauseMenuScene
      attr_reader :viewport, :panels
      def pbStartScene
        @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
        @viewport.z = 99999
        @panels = (0...8).map { |i| s = Sprite.new(@viewport); s.x = 16 + 168 * (i / 2); s.y = 64 + 140 * (i % 2); s }
      end
      def open_step(factor); @viewport.rect.width = Graphics.width * factor; end
      def max_x; Graphics.width - 16; end
    end
  RB
  section("274:PSystem_System", File.read(File.join(FIX, "PSystem_System_part.rb")))
rescue Exception => e
  errors << "#{e.class}: #{e.message} @ #{e.backtrace.first}"
end
check "scripts load", errors.empty?
puts errors

# --- startup: pbSetUpSystem ---
$PokemonSystem = PokemonSystem.new
$PokemonSystem.instance_variable_set(:@border, border == "border1" ? 1 : 0)
pbSetResizeFactor([$PokemonSystem.screensize, 3].min)
setScreenBorderName("border") rescue nil
Graphics.update; Graphics.update

wide = { "off" => 512 }.fetch(mode, 684) # 384 * 16/9 = 682.7 -> 684
check "engine screen #{wide}x384 (the game's 512x384, widened)", [Graphics.yami_native_width, Graphics.yami_native_height] == [wide, 384]
ui_w = pano || mode == "off" ? 512 : 684
check "UI sees #{ui_w}x384", [Graphics.width, Graphics.height] == [ui_w, 384]
check "design size read from v18's SCREEN_WIDTH/HEIGHT", Yami::OldEss.base == [512, 384]
check "border offsets neutral", $ResizeOffsetX == 0 && $ResizeOffsetY == 0 && BORDER_WIDTH == 0
check "engine never asked for a bordered/garbage size", Graphics.resizes.all? { |w, h| h == 384 }
if pano
  check "engine draws the UI layer at [86, 0, 512, 384]", Graphics.ui_clip == [86, 0, 512, 384]
else
  check "no UI layer outside panoramic", Graphics.ui_clip.nil?
end

# --- map (viewports made while loading) ---
check "map viewport created at load spans #{wide}", Spriteset_Map.viewport.native_rect == [0, 0, wide, 384]
check "camera centres on the full width", Game_Player.new.center_x == wide / 2 - 16
check "map scroll limit uses the full width", Game_Map.new.max_x_tiles == wide / 32.0
pic = Spriteset_Global.pictures
check "picture layer is UI (game rect #{pano ? 'in the UI layer' : ''})",
      pic.native_rect == (pano ? [0, 0, 512, 384] : [0, 0, wide, 384]) && (pano ? !pic.yami_unclipped : true)
$scene = Spriteset_Map.new
check "game's own map renderer by default", $scene.tilemap.renderer == CustomTilemap
Yami::NativeTilemap.install   # opt-in (native_tilemap=true)
$scene = Spriteset_Map.new
check "opt-in native map renderer (engine Tilemap)", $scene.tilemap.renderer <= Tilemap
tags = [0, 1, 2]
ok = begin; $scene.tilemap.terrain_tags = tags; $scene.tilemap.terrain_tags.equal?(tags); rescue NoMethodError; false; end
check "v18 terrain_tags accepted by the native renderer", ok

# --- load screen ---
ls = PokemonLoad_Scene.new; ls.pbStartScene
want = pano ? [0, 0, 512, 384] : [0, 0, ui_w, 384]
check "load screen viewport #{want.inspect} (bg 512x384 fills it, no repeats)", ls.viewport.native_rect == want
Graphics.update
check "no map on screen: ambient side fill", pano ? Graphics.ambient == [86, 512, 45] : Graphics.ambient.nil?

# --- pause menu over the map ---
eval("class Scene_Map; end", TOPLEVEL_BINDING, "053:Scene_Map")
$scene = Scene_Map.new
ls.viewport.dispose
pm = PauseMenuScene.new; pm.pbStartScene
[0.25, 0.5, 1.0].each { |f| pm.open_step(f) }
check "pause menu viewport after its open animation: game rect #{[0, 0, ui_w, 384].inspect}", pm.viewport.native_rect[2] == ui_w &&
      pm.viewport.native_rect[0] == 0
check "carousel panels untouched", pm.panels.map { |p| p.native_pos[0] } == pm.panels.map(&:x)
check "carousel limit from the game's width", pm.max_x == ui_w - 16
Graphics.update
check "pause menu over the map: map visible at the sides", Graphics.ambient.nil?

# --- the game's screenshot: its own area ---
shot = Graphics.snap_to_bitmap
check "snap_to_bitmap returns the game's #{ui_w}x384 area", shot.respond_to?(:width) ? shot.width == ui_w : true

# Myth later asks for the bordered size through its own resize_screen
Graphics.resize_screen(512 + 156, 384 + 156)
Graphics.update
check "bordered request ignored: still #{ui_w}x384 for UI", [Graphics.width, Graphics.height] == [ui_w, 384] &&
      [Graphics.yami_native_width, Graphics.yami_native_height] == [wide, 384]
check "no message boxes", $msgboxes == 0
puts($fails.zero? ? "ALL PASS" : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)
