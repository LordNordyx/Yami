# Win32API compatibility: run the patterns older Pokémon Essentials uses.
require_relative "stubs"
require "tmpdir"
require "timeout"
SCRIPTS = File.expand_path("../../app/src/main/assets/yami/scripts", __dir__)
$fails = 0
def check(name, cond); puts "#{cond ? 'PASS' : 'FAIL'} #{name}"; $fails += 1 unless cond; end

Dir.chdir(Dir.mktmpdir("yami-w32"))
File.write("Game.ini", "[Game]\r\nLibrary=RGSS104E.dll\r\nScripts=Data\\Scripts.rxdata\r\nTitle=Pokémon Myth\r\nRTP1=Standard\r\n", mode: "wb")
load "#{SCRIPTS}/yami_win32.rb"

# --- Essentials v16 "Win32API" section (reopens the class, constructs at load) ---
class Win32API
  @@RGSSWINDOW = nil
  @@GetCurrentThreadId = Win32API.new('kernel32', 'GetCurrentThreadId', '%w()', 'l')
  @@GetWindowThreadProcessId = Win32API.new('user32', 'GetWindowThreadProcessId', '%w(l p)', 'l')
  @@FindWindowEx = Win32API.new('user32', 'FindWindowEx', '%w(l l p p)', 'l')
  def Win32API.pbFindRgssWindow
    return @@RGSSWINDOW if @@RGSSWINDOW
    processid = [0].pack('l')
    threadid = @@GetCurrentThreadId.call
    nextwindow = 0
    begin
      nextwindow = @@FindWindowEx.call(0, nextwindow, "RGSS Player", 0)
      if nextwindow != 0
        wndthreadid = @@GetWindowThreadProcessId.call(nextwindow, processid)
        if wndthreadid == threadid
          @@RGSSWINDOW = nextwindow
          return @@RGSSWINDOW
        end
      end
    end until nextwindow == 0
    raise "Can't find RGSS player window"
  end
  def Win32API.SetWindowText(text)
    Win32API.new('user32', 'SetWindowTextA', %w(l p), 'i').call(pbFindRgssWindow, text)
  end
  def Win32API.GetPrivateProfileString(section, key)
    val = "\0" * 256
    gps = Win32API.new('kernel32', 'GetPrivateProfileString', %w(p p p p l p), 'l')
    gps.call(section, key, "", val, 256, ".\\Game.ini")
    val.delete!("\0")
    val
  end
  def Win32API.client_size
    rect = [0, 0, 0, 0].pack('l4')
    Win32API.new('user32', 'GetClientRect', %w(l p), 'i').call(pbFindRgssWindow, rect)
    rect.unpack('l4')[2..3]
  end
end
check "class body with Win32API.new(4 args) loads", true
hwnd = Timeout.timeout(2) { Win32API.pbFindRgssWindow } rescue nil
check "pbFindRgssWindow finds a window (no endless loop)", hwnd && hwnd != 0
check "SetWindowTextA works (A suffix)", Win32API.SetWindowText("Myth") == 1
check "GetPrivateProfileString reads Game.ini", Win32API.GetPrivateProfileString("Game", "Title").force_encoding("UTF-8") == "Pokémon Myth"
check "GetPrivateProfileString missing key → default", Win32API.GetPrivateProfileString("Game", "Nope") == ""
check "GetClientRect gives screen size", Win32API.client_size == [640, 480]

w = Win32API.new('kernel32', 'WritePrivateProfileString', %w(p p p p), 'l')
w.call("Game", "Title", "Changed", ".\\Game.ini")
check "WritePrivateProfileString updates Game.ini", Win32API.GetPrivateProfileString("Game", "Title") == "Changed"
w.call("Yami", "Scale", "2", ".\\Game.ini")
check "WritePrivateProfileString adds a section", Win32API.GetPrivateProfileString("Yami", "Scale") == "2" &&
                                                Win32API.GetPrivateProfileString("Game", "Library") == "RGSS104E.dll"

# --- keyboard via GetAsyncKeyState (Essentials' own Input module) ---
gaks = Win32API.new("user32", "GetAsyncKeyState", "i", "i")
getstate = ->(vk) { (gaks.call(vk) & 0x8000) > 0 }
check "nothing pressed", !getstate.(0x20) && !getstate.(0x58)
Input.keys[44] = true   # SDL space (Yami's C button)
Input.keys[27] = true   # SDL X (Yami's B button)
Input.keys[82] = true   # SDL up
Input.keys[225] = true  # SDL left shift (Yami's A button)
check "device condition: raw_key_states stale (game replaced Input.update)", Input.raw_key_states[44] == false
check "VK_SPACE ← C button", getstate.(0x20)
check "VK 'X' ← B button", getstate.(0x58)
check "VK_UP ← up", getstate.(0x26) && !getstate.(0x28)
check "VK_SHIFT and VK_LSHIFT ← shift", getstate.(0x10) && getstate.(0xA0) && !getstate.(0xA1)
kb = "\0" * 256
Win32API.new("user32", "GetKeyboardState", "p", "i").call(kb)
check "GetKeyboardState fills 256 bytes", kb.bytesize == 256 && kb.getbyte(0x20) == 0x80 && kb.getbyte(0x41) == 0
Input.keys.fill(false)
check "release clears state", !getstate.(0x20)

# --- strings ---
mb = Win32API.new("kernel32", "MultiByteToWideChar", "ilpipi", "i")
n = mb.call(65001, 0, "Pokémon\0", -1, nil, 0)
wbuf = "\0" * (n * 2)
mb.call(65001, 0, "Pokémon\0", -1, wbuf, n)
check "MultiByteToWideChar size + UTF-16LE", n == 8 && wbuf.force_encoding("UTF-16LE").encode("UTF-8") == "Pokémon\0"
wc = Win32API.new("kernel32", "WideCharToMultiByte", "ilpipipp", "i")
need = wc.call(65001, 0, wbuf, -1, nil, 0, nil, nil)
out = "\0" * need
wc.call(65001, 0, wbuf, -1, out, need, nil, nil)
check "WideCharToMultiByte round-trips", out.force_encoding("UTF-8") == "Pokémon\0"

# --- misc ---
check "unknown function → 0", Win32API.new("foo32", "DoSomethingWeird", "", "i").call(1, 2) == 0
check "GetTickCount increases", (a = Win32API.new("kernel32", "GetTickCount", "", "l").call) >= 0 &&
                                Win32API.new("kernel32", "GetTickCount", "", "l").call >= a
path = "\0" * 260
check "SHGetFolderPath returns S_OK + a path", Win32API.new("shell32", "SHGetFolderPath", "lllll", "l").call(0, 0x1C, 0, 0, path) == 0 && path.delete("\0").length > 0
# --- Essentials FileTests reading a folder (empty graphic name) ---
Dir.mkdir("Graphics") rescue nil; Dir.mkdir("Graphics/Characters") rescue nil
File.binwrite("Graphics/Characters/hero.png", "\x89PNG")
def pbGetFileChar(file)
  begin
    File.open(file, "rb") { |f| return f.read(1) }
  rescue Errno::ENOENT, Errno::EINVAL, Errno::EACCES
    return nil
  end
end
r = begin; pbGetFileChar("Graphics/Characters/"); rescue => e; e; end
check "reading a folder → nil like Windows, not EISDIR", r.nil?
check "...also catchable as Errno::EISDIR", (begin; File.read("Graphics/Characters"); false; rescue Errno::EISDIR; true; end)
check "normal file reads untouched", pbGetFileChar("Graphics/Characters/hero.png") == "\x89" .b &&
  File.binread("Graphics/Characters/hero.png") == "\x89PNG".b && File.open("Graphics/Characters/hero.png", "rb", &:read).bytesize == 4
check "File.open with keywords still works", File.open("Graphics/Characters/hero.png", mode: "rb") { |f| f.read(1) } == "\x89".b
# --- Windows file system semantics ---
Dir.mkdir("Graphics/Pictures") rescue nil
File.binwrite("Graphics/Pictures/Title.PNG", "T")
check "case-insensitive exist?", File.exist?("graphics/pictures/title.png") && FileTest.exist?("GRAPHICS/Pictures/title.png")
check "case-insensitive open (safeExists? pattern)", (r = false; File.open("Graphics/pictures/title.png", "rb") { r = true } rescue nil; r)
check "backslash paths", File.read("Graphics\\Pictures\\Title.PNG") == "T" && File.file?(".\\graphics\\pictures\\TITLE.png")
check "missing file still missing", !File.exist?("Graphics/Pictures/nope.png") && !File.exist?("Nope/Pictures/x.png")
check "missing file raises ENOENT as usual", (begin; File.read("Graphics/Pictures/nope.png"); false; rescue Errno::ENOENT; true; end)
Dir.mkdir("Saves\\Slot1") rescue Dir.mkdir("Saves") && Dir.mkdir("Saves\\Slot1")
File.open("Saves\\Slot1\\Game.rxdata", "wb") { |f| f.write("S") }
check "write with backslashes lands in the real folder", File.binread("Saves/Slot1/Game.rxdata") == "S"
check "new file visible right after writing (cache refresh)", File.exist?("saves/slot1/game.rxdata")
File.open("saves/slot1/GAME.rxdata", "wb") { |f| f.write("S2") }
check "writing in another case overwrites the existing file, like Windows", Dir.children("Saves/Slot1") == ["Game.rxdata"] && File.binread("Saves/Slot1/Game.rxdata") == "S2"
File.rename("saves/slot1/game.rxdata", "Saves/Slot1/Backup.rxdata")
check "rename resolves case", File.exist?("Saves/Slot1/Backup.rxdata") && !File.exist?("Saves/Slot1/Game.rxdata")
File.delete("SAVES/SLOT1/backup.rxdata")
check "delete resolves case", Dir.children("Saves/Slot1").empty?
check "File.basename/extname understand backslashes", File.basename("Graphics\\Pictures\\Title.png", ".png") == "Title" && File.extname("a\\b.png") == ".png"
check "Dir.chdir resolves case", Dir.chdir("graphics/PICTURES") { File.exist?("Title.PNG") }
check "Dir.entries resolves case", Dir.entries("GRAPHICS/pictures").include?("Title.PNG")
check "non-UTF-8 name doesn't crash", (File.exist?("Graphics/Pok\xE9mon.png".b) rescue :err) == false
Dir.mkdir("Other") rescue nil; File.binwrite("Other/title.png", "O")
check "lookups follow the current folder", File.read("graphics/pictures/title.png") == "T" &&
  Dir.chdir("Other") { File.read("TITLE.png") } == "O" && File.read("graphics/pictures/title.png") == "T"
File.binwrite("Graphics/Pictures/New.png", "N")
check "file created after a cached miss is found", File.exist?("graphics/pictures/new.png")
check "File.open with block returns block value", File.open("Graphics/Pictures/title.png", "rb") { |f| f.read } == "T"
check "MiniFFI alias", MiniFFI == Win32API
check "no message boxes", $msgboxes == 0
puts($fails.zero? ? "ALL PASS" : "#{$fails} FAILED")

exit($fails.zero? ? 0 : 1)
