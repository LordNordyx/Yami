require "fileutils"
require_relative "stubs"
require "tmpdir"
WORK = ENV.fetch("WORK") { Dir.mktmpdir("yami") }
load ENV.fetch("RPG1", File.join(__dir__, "rpg1.rb"))
SCRIPTS = File.expand_path("../../app/src/main/assets/yami/scripts", __dir__)
$fails = 0
def check(name, cond); puts "#{cond ? 'PASS' : 'FAIL'} #{name}"; $fails += 1 unless cond; end

game = WORK + "/game"; FileUtils.rm_rf(game); FileUtils.mkdir_p(["#{game}/Data", "#{game}/Graphics/Tilesets", "#{game}/.yami"])
Bitmap::DIMS["Big"] = [256, 8000]; Bitmap::DIMS["Small"] = [256, 1024]
FileUtils.touch(["#{game}/Graphics/Tilesets/Big.png", "#{game}/Graphics/Tilesets/Small.png"])
ts = [nil]
[["Big", 1], ["Small", 2]].each do |n, id|
  t = RPG::Tileset.new; t.id = id; t.name = n; t.tileset_name = n
  t.passages = Table.new(384 + 2000); t.priorities = Table.new(384 + 2000); t.terrain_tags = Table.new(384 + 2000)
  (0...(384 + 2000)).each { |i| t.passages[i] = i % 16; t.priorities[i] = i % 6; t.terrain_tags[i] = i % 8 }
  ts << t
end
save_data(ts, "#{game}/Data/Tilesets.rxdata")
def mkmap(tid, ids, ev_tile)
  m = RPG::Map.new(20, 15); m.tileset_id = tid
  ids.each_with_index { |id, i| m.data[i % 20, i / 20, i % 3] = id }
  m.data[5, 5, 0] = 12 # autotile id, must stay
  e = RPG::Event.new(1, 1); e.pages[0].graphic.tile_id = ev_tile; m.events[1] = e
  m
end
save_data(mkmap(1, [384, 400, 684, 400], 384 + 999), "#{game}/Data/Map001.rxdata")
save_data(mkmap(1, [400, 684, 384], 384 + 999), "#{game}/Data/Map002.rxdata") # same set → shared variant
save_data(mkmap(1, [390], 0), "#{game}/Data/Map003.rxdata")
save_data(mkmap(2, [500], 0), "#{game}/Data/Map004.rxdata")                  # small tileset → untouched
File.write("#{game}/.yami/maps.txt", Dir["#{game}/Data/Map*"].sort.map { |f| "Data/#{File.basename(f)}\t#{File.size(f)}" }.join("\n"))

cfg = WORK + "/session.cfg"
Dir.chdir(game)

# ---------- optimizer ----------
File.write(cfg, "mode=optimize\nwidescreen=off\n"); ENV["YAMI_CFG"] = cfg
begin
  load "#{SCRIPTS}/yami_optimizer.rb"
rescue SystemExit
  puts "(optimizer exited)"
end
res = File.readlines(".yami/opt/result.txt").map { |l| l.chomp.split("=", 2) }.to_h
puts res.inspect
check "1 oversized tileset", res["tilesets"] == "1"
check "2 variants (maps 1+2 shared, map 3 own)", res["variants"] == "2"
check "3 maps optimized", res["maps"] == "3"
check "map004 not optimized", !File.exist?(".yami/opt/Data/Map004.rxdata")
atlas = Marshal.load(File.binread("Graphics/Tilesets/_yami/Big_0.png"))
check "atlas 0 holds 4 tiles in 1 row", atlas[0] == 256 && atlas[1] == 32 && atlas[2].size == 4
check "atlas tile 2 copied from id 684 source rect", atlas[2][2] == [64, 0, (684 - 384) % 8 * 32, (684 - 384) / 8 * 32]

# ---------- runtime ----------
File.write(cfg, "mode=play\nmap_cache=true\nmap_cache_mb=64\noptimized_maps=true\nwidescreen=off\nturbo_mode=hybrid\nturbo_speed=3\nturbo_toggle=true\nturbo_scancode=67\nredirect_saves=true\nsave_dir=#{WORK}/saves\nstatus_file=#{WORK}/status.txt\n")
FileUtils.mkdir_p(WORK + "/saves")
load "#{SCRIPTS}/yami_runtime.rb"
180.times { Graphics.update }; sleep 0.3 # cache starts after boot frames
orig1 = Marshal.load(File.binread("Data/Map001.rxdata"))
m1 = load_data("Data/Map001.rxdata")
tsets = load_data("Data/Tilesets.rxdata")
check "tileset list extended with variants", tsets.size == 5 && tsets[3].tileset_name == "_yami/Big_0"
check "map001 points at variant", m1.tileset_id == 3
check "autotile untouched", m1.data[5, 5, 0] == 12
ok = true
(0...20).each { |x| (0...15).each { |y| (0...3).each { |z|
  o = orig1.data[x, y, z]; n = m1.data[x, y, z]
  ok &&= (o < 384 ? n == o : tsets[1].passages[o] == tsets[3].passages[n] && tsets[1].priorities[o] == tsets[3].priorities[n] && tsets[1].terrain_tags[o] == tsets[3].terrain_tags[n])
} } }
check "passages/priorities/terrain tags follow every remapped tile", ok
check "event tile graphic remapped", tsets[3].passages[m1.events[1].pages[0].graphic.tile_id] == tsets[1].passages[384 + 999]
m4 = load_data("Data/Map004.rxdata")
check "unoptimized map served (from cache) intact", m4.tileset_id == 2 && m4.data[0, 0, 0] == 500
check "path normalisation (backslash/case)", load_data("data\\MAP001.rxdata").tileset_id == 3

# stale map → fallback to original
sleep 1.1; File.utime(Time.now, Time.now + 5, "Data/Map003.rxdata")
check "stale optimized map falls back to original", load_data("Data/Map003.rxdata").tileset_id == 1

# turbo
Graphics.update
check "turbo off at start", !Yami.turbo? && Graphics.frame_rate == 40
Input.keys[67] = true; Graphics.update
check "F10 toggles turbo on (rate x3, frameskip)", Yami.turbo? && Graphics.frame_rate == 120 && Graphics.frameskip == true
Graphics.update
check "holding key doesn't re-toggle", Yami.turbo?
Graphics.frame_rate = 60
check "game changes rate during turbo → scaled", Graphics.frame_rate == 180
Input.keys[67] = false; Graphics.update; Input.keys[67] = true; Graphics.update
check "toggle off restores game's new base", !Yami.turbo? && Graphics.frame_rate == 60 && Graphics.frameskip == false
check "status file written", File.read(WORK + "/status.txt").include?("turbo=0")
Graphics.kirin_disable_turbo!
Input.keys[67] = false; Graphics.update; Input.keys[67] = true; Graphics.update
check "kirin_disable_turbo! honoured", !Yami.turbo?

# saves
File.open("Save1.rxdata", "wb") { |f| f.write("x") }
check "Save1 written to Yami save dir", File.exist?(WORK + "/saves/Save1.rxdata") && !File.yami_exist?("#{game}/Save1.rxdata")
check "FileTest.exist? sees redirected save", FileTest.exist?("Save1.rxdata")
File.yami_open("#{game}/Save2.rxdata", "wb") { |f| f.write("legacy") }
check "legacy save in game folder still loads", File.open("Save2.rxdata", "rb") { |f| f.read } == "legacy"
check "non-save files untouched", File.exist?("Data/Map001.rxdata")
check "runtime never opens message boxes (print/p)", $msgboxes == 0
puts($fails.zero? ? "ALL PASS" : "#{$fails} FAILED")
