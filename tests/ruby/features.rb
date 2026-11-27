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

work = Dir.mktmpdir("yami-feat"); save = File.join(work, "save"); Dir.mkdir(save)
control = File.join(work, "control.txt")
File.write(File.join(work, "y.cfg"), "mode=play\nrgss=1\nwidescreen=off\nsave_dir=#{save}\ninstant_text=true\nminimap=false\ncontrol_file=#{control}\n")
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
    attr_accessor :map_id, :data, :passages, :priorities, :terrain_tags, :width, :height
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
4.times { |x| 3.times { |y| m.data[x, y, 0] = 384 } }       # floor
m.data[0, 0, 1] = 390; m.passages[390] = 0x0f              # a wall
$game_map = m
$scene = Scene_Map.new

def frames(n) = n.times { Graphics.update }
def control(h) = File.write($control, h.map { |k, v| "#{k}=#{v}\n" }.join)
$control = control
control(instant_text: true, minimap: false, shiny: 0, no_encounters: false, noclip: false, money_seq: 0, heal_seq: 0)
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
control(instant_text: false, minimap: false, shiny: 0, no_encounters: false, noclip: false, money_seq: 0, heal_seq: 0); frames(12)
w3 = Window_AdvancedTextPokemon.new(40); w3.update
check "instant text off: letter by letter again", w3.shown == 1 && w3.skips == 0

# --- shiny odds ---
check "game's odds untouched while off", 200.times.none? { PokeBattle_Pokemon.new(1, 5).shiny? }
before = $Trainer.party.first
control(instant_text: false, minimap: false, shiny: 4, no_encounters: false, noclip: false, money_seq: 0, heal_seq: 0); frames(12)
check "shiny odds 'always': new Pokémon are shiny", 20.times.all? { PokeBattle_Pokemon.new(1, 5).shiny? }
check "Pokémon you already have stay as they were", !before.shiny?
control(instant_text: false, minimap: false, shiny: 2, no_encounters: false, noclip: false, money_seq: 0, heal_seq: 0); frames(12)
n = 6400.times.count { PokeBattle_Pokemon.new(1, 5).shiny? }
check "shiny odds 1 in 64 (#{n} of 6400)", n.between?(50, 160)

# --- encounters, walls ---
control(instant_text: false, minimap: false, shiny: 0, no_encounters: true, noclip: true, money_seq: 0, heal_seq: 0); frames(12)
check "no random encounters", !PokemonEncounters.new.isEncounterPossibleHere? && $game_system.encounter_disabled == true
check "walk through walls", $game_player.through == true
control(instant_text: false, minimap: false, shiny: 0, no_encounters: false, noclip: false, money_seq: 0, heal_seq: 0); frames(12)
check "both back to normal when off", PokemonEncounters.new.isEncounterPossibleHere? && $game_system.encounter_disabled.nil? && $game_player.through == false

# --- one-shot actions ---
control(instant_text: false, minimap: false, shiny: 0, no_encounters: false, noclip: false, money_seq: 1, heal_seq: 1); frames(12)
check "max money (capped by the game)", $Trainer.money == 999_999
check "party healed", $Trainer.party.first.hp == 50
$Trainer.money = 5; frames(24)
check "actions run once per press", $Trainer.money == 5

# --- minimap ---
control(instant_text: false, minimap: true, shiny: 0, no_encounters: false, noclip: false, money_seq: 1, heal_seq: 1); frames(14)
mm = Yami::Minimap
bmp = mm.instance_variable_get(:@bmp)
check "minimap built from the map (raw pixels)", bmp && bmp.raw && bmp.raw.bytesize == 4 * 3 * 4
wall = bmp.raw[0, 4].unpack("C4"); floor = bmp.raw[4, 4].unpack("C4")
check "walls dark, floor lighter", wall[0..2] == [0, 0, 0] && floor[0] > 30
dot = mm.instance_variable_get(:@dot); spr = mm.instance_variable_get(:@sprite)
sc = mm.instance_variable_get(:@scale)
p [dot.x, spr.x, sc, dot.visible]
check "player dot on the player's tile", dot.visible && dot.x >= spr.x + 2 * sc - sc && dot.x <= spr.x + 3 * sc
$scene = Object.new; frames(1)
check "hidden outside the map scene", !spr.visible && !dot.visible

puts($fails.zero? ? "ALL PASS" : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)
