# Pokémon Essentials v20/v21 map rendering (as in Essentials 21.1, read from
# its public repository and reproduced here: TilemapRenderer's interface,
# Spriteset_Map / Scene_Map's calls into it, connected maps via $map_factory,
# terrain tags with reflections and bridges, pbDayNightTint changing the
# renderer's tone in place).
#   ruby essentials_v21.rb <plain|modified>
#     plain:    Yami's GPU renderer replaces TilemapRenderer
#     modified: a plugin changed TilemapRenderer -> the game's own is kept
require_relative "es_stubs"
require "tmpdir"
SCRIPTS = File.expand_path("../../app/src/main/assets/yami/scripts", __dir__)
$fails = 0
def check(name, cond); puts "#{cond ? 'PASS' : 'FAIL'} #{name}"; $fails += 1 unless cond; end
variant = ARGV[0] || "plain"

# --- engine details these stubs need ---
class Tone
  attr_reader :red, :green, :blue, :gray
  def initialize(r = 0, g = 0, b = 0, gr = 0); set(r, g, b, gr); end
  def set(r, g, b, gr = 0); @red, @green, @blue, @gray = r, g, b, gr; self; end
  def ==(o); o.is_a?(Tone) && [red, green, blue, gray] == [o.red, o.green, o.blue, o.gray]; end
end
class Table
  def initialize_copy(o); super; @d = o.instance_variable_get(:@d).dup; end
end
class Tilemap
  attr_accessor :tone, :color, :yami_ground_z
  attr_reader :updates
  def update; @updates = (@updates || 0) + 1; end
  def dispose; @disposed = true; end
  def disposed?; !!@disposed; end
end

Graphics.instance_variable_set(:@w, 512)
Graphics.instance_variable_set(:@h, 384)
work = Dir.mktmpdir("yami-v21"); save = File.join(work, "save"); Dir.mkdir(save)
File.write(File.join(work, "y.cfg"), "mode=play\nrgss=1\nwidescreen=off\nsave_dir=#{save}\n")
ENV["YAMI_CFG"] = File.join(work, "y.cfg")
Dir.chdir(work)
%w[yami_runtime.rb yami_ruby18.rb yami_win32.rb].each { |f| load File.join(SCRIPTS, f) }
def section(name, src) = eval(src, TOPLEVEL_BINDING, name)

section("004:Game_Map", <<~RB)
  class Game_Map
    TILE_WIDTH = 32; TILE_HEIGHT = 32; X_SUBPIXELS = 4; Y_SUBPIXELS = 4
    attr_accessor :map_id, :display_x, :display_y, :data, :priorities, :terrain_tags,
                  :tileset_name, :autotile_names, :tileset_id, :width, :height
  end
  module GameData
    class TerrainTag
      attr_reader :shows_reflections, :bridge
      def initialize(r, b); @shows_reflections = r; @bridge = b; end
      DATA = { 6 => new(true, false), 15 => new(false, true) }
      def self.try_get(t); DATA[t]; end
    end
  end
  class PokemonGlobal; attr_accessor :bridge; end
  $PokemonGlobal = PokemonGlobal.new; $PokemonGlobal.bridge = 0
  def pbGetTileset(n) = Bitmap.new(256, 1024)
  def pbGetAutotile(n) = Bitmap.new(96, 128)
RB

section("006:TilemapRenderer", <<~RB)
  class TilemapRenderer
    attr_reader :tilesets, :autotiles, :viewport
    attr_accessor :tone, :color, :ox, :oy, :visible
    ZOOM_X = 1; ZOOM_Y = 1
    EXTRA_AUTOTILES = {}
    class TilesetBitmaps; def initialize; @bitmaps = {}; end; end
    class AutotileBitmaps < TilesetBitmaps; end
    def initialize(viewport)
      @tone = Tone.new(0, 0, 0, 0); @viewport = viewport; @ruby_sprites = 900
    end
    def ruby_renderer?; true; end
    def dispose; end
    def disposed?; false; end
    def add_tileset(f); end
    def remove_tileset(f); end
    def add_autotile(f); end
    def remove_autotile(f); end
    def add_extra_autotiles(i); end
    def remove_extra_autotiles(i); end
    def refresh; end
    def refresh_tile(*); end
    def refresh_tile_bitmap(*); end
    def refresh_tile_z(*); end
    def check_if_screen_moved; end
    def update; end
  end
RB
if variant == "modified"
  section("900:Overworld shadows plugin", <<~RB)
    class TilemapRenderer
      alias plugin_refresh_tile_z refresh_tile_z
      def refresh_tile_z(*a); plugin_refresh_tile_z(*a); end
    end
  RB
end
section("003:Scene_Map", <<~RB)
  class Scene_Map
    attr_reader :map_renderer
    def initialize; @map_renderer = TilemapRenderer.new(Viewport.new(0, 0, 512, 384)); end
  end
RB

def make_map(id, w, h, tileset, refl: false, bridge: false)
  m = Game_Map.new
  m.map_id = id; m.width = w; m.height = h; m.display_x = 0; m.display_y = 0
  m.data = Table.new(w, h, 3)
  m.priorities = Table.new(400); m.terrain_tags = Table.new(400)
  m.tileset_name = tileset; m.autotile_names = ["Water", "", "", "", "", "", ""]; m.tileset_id = id
  w.times { |x| h.times { |y| m.data[x, y, 0] = 385 } }        # grass
  if refl
    m.terrain_tags[48] = 6                                        # water autotile: reflective
    m.data[1, 1, 0] = 48
  end
  if bridge
    m.terrain_tags[390] = 15; m.priorities[390] = 1                # bridge tile
    m.data[2, 2, 1] = 390
  end
  m
end

Graphics.update; Graphics.update   # Yami installs once the classes exist
$scene = Scene_Map.new
r = $scene.map_renderer
if variant == "modified"
  check "plugin-modified TilemapRenderer kept (game's own renderer)", r.respond_to?(:ruby_renderer?) && r.class == TilemapRenderer
  puts($fails.zero? ? "ALL PASS" : "#{$fails} FAILED"); exit($fails.zero? ? 0 : 1)
end
check "TilemapRenderer.new gives the GPU renderer", r.is_a?(TilemapRenderer) && r.class != TilemapRenderer

a = make_map(1, 20, 15, "Outside", refl: true, bridge: true)
b = make_map(2, 10, 15, "Outside")
$map_factory = Object.new
maps = [a, b]
$map_factory.define_singleton_method(:maps) { maps }
[a, b].each do |m|
  r.add_tileset(m.tileset_name)
  m.autotile_names.each { |f| r.add_autotile(f) }
  r.add_extra_autotiles(m.tileset_id)
end
a.display_x = 4 * 100; a.display_y = 4 * 37
b.display_x = -4 * 640; b.display_y = 4 * 37    # connected map to the right
r.update
ea = r.instance_variable_get(:@yami_maps)[1]; eb = r.instance_variable_get(:@yami_maps)[2]
check "one engine tilemap per map (two for a map with reflective water)", ea[:tilemaps].size == 2 && eb[:tilemaps].size == 1
main, refl = ea[:main], ea[:tilemaps].first
check "tilemaps follow each map's display position", main.ox == 100 && main.oy == 37 && eb[:main].ox == -640
check "reflective tiles drawn below reflections (ground z -100)", refl.yami_ground_z == -100 && main.yami_ground_z.nil?
check "water only in the reflective tilemap", refl.map_data[1, 1, 0] == 48 && main.map_data[1, 1, 0] == 0 && main.map_data[0, 0, 0] == 385 && refl.map_data[0, 0, 0] == 0
check "tileset and autotiles are the original images", main.tileset.is_a?(Bitmap) && main.tileset.height == 1024 && main.autotiles[0].is_a?(Bitmap) && main.autotiles[0].width == 96
check "priorities from the map", main.priorities[390] == 1
$PokemonGlobal.bridge = 1; r.update
check "on a bridge: bridge tiles drawn at ground level", main.priorities[390] == 0 && a.priorities[390] == 1
$PokemonGlobal.bridge = 0; r.update
check "off the bridge: normal priorities again", main.priorities[390] == 1
r.tone.set(-40, -40, 10, 0); r.update      # pbDayNightTint
check "day/night tone reaches every tilemap", [main, refl, eb[:main]].all? { |t| t.tone == Tone.new(-40, -40, 10, 0) }
a.data[3, 3, 0] = 48
check "map edits while playing reach the split copies", refl.map_data[3, 3, 0] == 48 && main.map_data[3, 3, 0] == 0
a.data[3, 3, 0] = 386
check "...both ways", refl.map_data[3, 3, 0] == 0 && main.map_data[3, 3, 0] == 386
check "autotile animation ticks", main.updates.to_i >= 3
maps = [a]
r.update
check "map leaving the factory: its tilemap disposed", eb[:main].disposed? && !r.instance_variable_get(:@yami_maps).key?(2)
r.remove_tileset("Outside"); r.remove_tileset("Outside")
check "tileset bitmap freed after the last map lets go", r.instance_variable_get(:@yami_ts).empty?
r.dispose
check "dispose frees every tilemap", main.disposed? && refl.disposed? && r.disposed?
puts($fails.zero? ? "ALL PASS" : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)
