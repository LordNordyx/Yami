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
check "GPU map renderer (engine Tilemap) by default", $scene.tilemap.renderer <= Tilemap
tags = [0, 1, 2]
ok = begin; $scene.tilemap.terrain_tags = tags; $scene.tilemap.terrain_tags.equal?(tags); rescue NoMethodError; false; end
check "v18 terrain_tags accepted by the native renderer", ok

# --- huge tileset (Myth_Outdoor is 256x26000): compact per-map tileset ---
tm = $scene.tilemap.instance_variable_get(:@tilemap)
raw = ->(m) { Tilemap.instance_method(m).bind(tm).call }
$blts = []
Bitmap.class_eval { define_method(:blt) { |*a| $blts << [a[0], a[1], a[3].to_a] } }
big = Bitmap.new(256, 26000)
md = Table.new(4, 4, 3)
md[0, 0, 0] = 385; md[1, 0, 0] = 384 + 8 * 500 + 3; md[2, 0, 1] = 50
pr = Table.new(384 + 8 * 813); pr[384 + 8 * 500 + 3] = 2; pr[50] = 1
tm.tileset = big
check "huge tileset not handed over before the map", raw.(:tileset).nil?
tm.map_data = md; tm.priorities = pr
cts = raw.(:tileset); cmd = raw.(:map_data); cpr = raw.(:priorities)
check "engine gets a compact tileset (2 rows)", cts && cts.height == 64 && $blts.map(&:last) == [[0, 0, 256, 32], [0, 16000, 256, 32]]
check "game still sees its own tileset/map/priorities", tm.tileset.equal?(big) && tm.map_data.equal?(md) && tm.priorities.equal?(pr)
check "drawn map remapped (tiles, autotiles)", cmd[0, 0, 0] == 385 && cmd[1, 0, 0] == 384 + 8 + 3 && cmd[2, 0, 1] == 50
check "priorities remapped", cpr[384 + 8 + 3] == 2 && cpr[50] == 1
md[0, 1, 0] = 386
check "runtime tile change mirrored", raw.(:map_data)[0, 1, 0] == 386
md[3, 3, 0] = 384 + 8 * 700 + 1
check "runtime change to a new tile row rebuilds", raw.(:tileset).height == 96 && raw.(:map_data)[3, 3, 0] == 384 + 16 + 1 && cts.disposed?
small = Bitmap.new(256, 2000)
tm.tileset = small
check "normal tilesets handed over as they are", raw.(:tileset).equal?(small) && raw.(:map_data).equal?(md)

# --- game scripts wrapping methods after Yami (Anil's Sprite_DynamicShadows) ---
section("072:Sprite_DynamicShadows", <<~RB)
  class Spriteset_Map
    alias shadow_initialize initialize
    def initialize(*a); shadow_initialize(*a); @shadows = true; end
  end
  class Table
    alias shadow_set []=
    def []=(*a); shadow_set(*a); end
  end
RB
ok = begin
  sm2 = Spriteset_Map.new
  t2 = Table.new(2, 2, 1); t2[1, 1, 0] = 5
  sm2.instance_variable_get(:@shadows) && t2[1, 1, 0] == 5
rescue SystemStackError
  false
end
check "game aliasing Spriteset_Map#initialize / Table#[]= after Yami: no endless loop", ok

# --- a failing tick hook: logged once, switched off after 100 frames ---
logs = []
Yami.singleton_class.send(:alias_method, :t_log, :log)
Yami.define_singleton_method(:log) { |m| logs << m; t_log(m) }
fails = 0; after = 0
Yami.on_tick { fails += 1; nil.instance_variable_set(:@x, 1) }
Yami.on_tick { after += 1 }
120.times { Graphics.update }
check "failing hook logged once, switched off after 100 failures", logs.count { |m| m.start_with?("tick hook: FrozenError") } == 1 && fails == 100 && logs.any? { |m| m.include?("switched off") }
check "hooks after it keep running every frame", after == 120
Yami.singleton_class.send(:alias_method, :log, :t_log)

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
if ENV["YAMI_BENCH"]
  $scene = Scene_Map.new rescue nil
  sm = Spriteset_Map.new
  n = 2000
  GC.start; a0 = GC.stat(:total_allocated_objects)
  t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  n.times { Graphics.update }
  t = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t
  hooks = Yami.instance_variable_get(:@tick_hooks)
  hooks.each do |h|
    t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    500.times { h.call rescue nil }
    STDERR.puts format("BENCH hook %s: %.1f us", h.source_location.inspect, (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t1) / 500 * 1e6)
  end
  STDERR.puts format("BENCH tick: %.1f us/frame, %d objs/frame", t / n * 1e6, (GC.stat(:total_allocated_objects) - a0) / n)
  t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  20000.times { Game_Player.new.center_x }
  t = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t
  STDERR.puts format("BENCH Graphics.width (map code): %.2f us/call", t / 20000 * 1e6)
end
puts($fails.zero? ? "ALL PASS" : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)
