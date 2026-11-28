# Player features driven by the control file: instant text, cheats, minimap.
# Essentials v18 shapes (as in Pokémon Myth): PokeBattle_Pokemon#shiny? from
# @shinyflag, PokemonEncounters#isEncounterPossibleHere?, $Trainer.money /
# party, Window_AdvancedTextPokemon#skipAhead.
require_relative "es_stubs"
require "tmpdir"
SCRIPTS = File.expand_path("../../app/src/main/assets/yami/scripts", __dir__)
$fails = 0
def check(name, cond); puts "#{cond ? 'PASS' : 'FAIL'} #{name}"; $fails += 1 unless cond; end

class Bitmap
  attr_reader :raw
  def raw_data=(s); @raw = s; end
end
class Sprite
  attr_accessor :zoom_x, :zoom_y, :opacity, :z
end
# the engine's live Look controls, recorded
module Graphics
  class << self
    attr_reader :look_log
    def smooth_scaling=(v); (@look_log ||= []) << [:scaling, v]; end
    def integer_scaling=(v); (@look_log ||= []) << [:integer, v]; end
    def yami_post_shader(path, i); (@look_log ||= []) << [:shader, path, i]; end
  end
end
# tiles with known colours: stretch_blt copies the source's colour into the strip
class Bitmap
  attr_accessor :colour
  def stretch_blt(dr, src, sr)
    @px ||= {}
    (dr.x...(dr.x + dr.width)).each { |x| (dr.y...(dr.y + dr.height)).each { |y| @px[[x, y]] = src.colour_at(sr) } }
  end
  def colour_at(_r) = @colour || [0, 0, 0, 0]
  def raw_data
    (0...height).flat_map { |y| (0...width).map { |x| (@px || {})[[x, y]] || [0, 0, 0, 0] } }.flatten.pack("C*")
  end
end
class RefBitmap < Bitmap
  attr_reader :refs
  def addRef; end
  def dispose; @released = true; end
  def released? = @released
end
module RPG
  module Cache
    TS = RefBitmap.new(256, 64)
    def TS.colour_at(r) = r.y >= 32 ? [120, 90, 60, 255] : [60, 160, 80, 255]   # row 1 brown wall, row 0 green floor
    AT = RefBitmap.new(96, 128); AT.colour = [40, 90, 200, 255]
    def self.tileset(_n) = TS
    def self.autotile(n) = n.to_s.empty? ? nil : AT
  end
end

work = Dir.mktmpdir("yami-feat"); save = File.join(work, "save"); Dir.mkdir(save)
control = File.join(work, "control.txt")
File.write(File.join(work, "y.cfg"), "mode=play\nrgss=1\nwidescreen=off\nsave_dir=#{save}\ninstant_text=true\nminimap=false\nshiny_odds=128\ncontrol_file=#{control}\n")
ENV["YAMI_CFG"] = File.join(work, "y.cfg")
Dir.chdir(work)
%w[yami_runtime.rb yami_ruby18.rb yami_win32.rb].each { |f| load File.join(SCRIPTS, f) }
def section(name, src) = eval(src, TOPLEVEL_BINDING, name)

section("100:Essentials", <<~RB)
  class PokeBattle_Pokemon
    attr_accessor :hp, :totalhp
    def initialize(sp, lv); @hp = 1; @totalhp = 50; end
    def shiny?; return @shinyflag if @shinyflag != nil; false; end
    def heal; @hp = @totalhp; end
  end
  class PokeBattle_Trainer
    attr_reader :money, :party
    def initialize; @money = 100; @party = [PokeBattle_Pokemon.new(1, 5)]; end
    def money=(v); @money = [[v, 999_999].min, 0].max; end
  end
  class PokemonEncounters
    def isEncounterPossibleHere?; true; end
  end
  class Game_System; attr_accessor :encounter_disabled; end
  class Game_Player; attr_accessor :x, :y, :through; end
  class Game_Map
    attr_accessor :map_id, :data, :passages, :priorities, :terrain_tags, :width, :height, :tileset_name, :autotile_names
  end
  class Scene_Map; end
  class Window_AdvancedTextPokemon
    attr_accessor :letterbyletter, :shown, :skips
    def initialize(len); @len = len; @shown = 0; @letterbyletter = true; @skips = 0; @pause_at = nil; end
    def pause_at(n); @pause_at = n; end
    def busy?; @shown < @len; end
    def pausing?; @pause_at && @shown == @pause_at; end
    def update; @shown += 1 if busy? && !pausing?; end
    def skipAhead; @skips += 1; @shown = @pause_at && @shown < @pause_at ? @pause_at : @len; end
  end
RB

$Trainer = PokeBattle_Trainer.new
$game_system = Game_System.new
$game_player = Game_Player.new; $game_player.x = 2; $game_player.y = 1; $game_player.through = false
m = Game_Map.new
m.map_id = 5; m.width = 4; m.height = 3
m.data = Table.new(4, 3, 3); m.passages = Table.new(400); m.priorities = Table.new(400); m.terrain_tags = Table.new(400)
4.times { |x| 3.times { |y| m.data[x, y, 0] = 384 } }       # floor (green)
m.data[0, 0, 1] = 392; m.passages[392] = 0x0f              # a wall (brown)
m.data[3, 2, 0] = 48                                       # water autotile (blue)
m.tileset_name = "Outside"; m.autotile_names = ["Water", "", "", "", "", "", ""]
$game_map = m
$scene = Scene_Map.new

def frames(n) = n.times { Graphics.update }
def control(h) = File.write($control, h.map { |k, v| "#{k}=#{v}\n" }.join)
$control = control
LOOK0 = { look_scaling: 1, look_integer: false, look_shader: "", look_intensity: 1.0 }
control({ instant_text: true, minimap: false }.merge(LOOK0))
frames(12)

# --- instant text ---
w = Window_AdvancedTextPokemon.new(40)
w.update
check "instant text: a message appears at once", !w.busy? && w.skips == 1
w2 = Window_AdvancedTextPokemon.new(40); w2.pause_at(10)
w2.update
check "instant text: stops at a pause inside the message", w2.shown == 10 && w2.busy?
w2.update
check "instant text: waits at the pause for the button", w2.shown == 10
control({ instant_text: false, minimap: false }.merge(LOOK0)); frames(12)
w3 = Window_AdvancedTextPokemon.new(40); w3.update
check "instant text off: letter by letter again", w3.shown == 1 && w3.skips == 0

# --- shiny odds (game setting 1 in 128) ---
before = $Trainer.party.first
n = 12800.times.count { PokeBattle_Pokemon.new(1, 5).shiny? }
check "shiny odds 1 in 128 for new Pokémon (#{n} of 12800)", n.between?(60, 145)
check "Pokémon you already have stay as they were", !before.shiny?

# --- no cheats any more ---
check "cheats are gone", !defined?(Yami::Cheats) && !Yami::Features::STATE.key?("noclip")

# --- Look changed in the in-game menu, live ---
check "the launch Look isn't re-applied", Graphics.look_log.nil?
control({ instant_text: false, minimap: false }.merge(LOOK0).merge(look_scaling: 0, look_integer: true, look_shader: "/rt/shaders/lcd3x.frag")); frames(12)
log = Graphics.look_log || []
check "Look applied live: sharp pixels, pixel perfect, LCD3x", log.include?([:scaling, 0]) && log.include?([:integer, true]) && log.include?([:shader, "/rt/shaders/lcd3x.frag", 1.0])

# --- minimap ---
control({ instant_text: false, minimap: true }.merge(LOOK0).merge(look_scaling: 0, look_integer: true, look_shader: "/rt/shaders/lcd3x.frag")); frames(20)
mm = Yami::Minimap
bmp = mm.instance_variable_get(:@bmp)
T = mm.instance_variable_get(:@t)
check "minimap drawn 1:1 as pixel art, 8 px a tile", T == 8 && bmp && bmp.raw && bmp.raw.bytesize == (4 * T) * (3 * T) * 4
px = ->(x, y) { bmp.raw[(y * 4 * T + x) * 4, 4].unpack("C4") }
mid = ->(cx, cy) { px.(cx * T + T / 2, cy * T + T / 2) }
wall = mid.(0, 0); floor = mid.(1, 1); water = mid.(3, 2)
check "minimap in the map's own colours: green floor", floor[1] > floor[0] && floor[1] > floor[2] && floor[1] > 150
check "...a darker brown wall", wall[0] > wall[2] && wall[0] < 120
check "...blue water", water[2] > water[0] && water[2] > 150
check "ink line where the floor meets the wall", px.(T, T / 2)[0, 3] == [16, 12, 24]
check "...and a shadow under it", px.(T / 2, T)[0, 3] == [16, 12, 24] && px.(T / 2, T + 1)[1] < floor[1] * 0.7
check "borrowed tileset and autotile given back", RPG::Cache::TS.released? && RPG::Cache::AT.released?
frame = mm.instance_variable_get(:@frame); spr = mm.instance_variable_get(:@sprite); over = mm.instance_variable_get(:@over)
v = 13 * T
check "window always the same size (13 x 13 tiles), square", frame.bitmap.width == v + 4 && frame.bitmap.height == v + 4
# player at (2,1): the window is centred on them, so the map starts left/above the window's middle
r = spr.src_rect
check "map slides under the window, player in the middle", spr.visible && r.x == 0 && r.y == 0 &&
  spr.x - (frame.x + 2) == (v / 2.0 - 2.5 * T).round && spr.y - (frame.y + 2) == (v / 2.0 - 1.5 * T).round
check "marks layer on top", over.visible && over.z > spr.z
dot = over; sc = T
$scene = Object.new; frames(1)
check "hidden outside the map scene", !spr.visible && !over.visible && !frame.visible

puts($fails.zero? ? "ALL PASS" : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)
