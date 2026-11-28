# =============================================================================
#  Yami Win32API compatibility layer
#
#  RPG Maker XP games (older Pokémon Essentials above all) call Windows DLLs
#  through Win32API — while their scripts load, and for keyboard input. There
#  are no Windows DLLs on Android, so this emulates the calls these games
#  actually make and answers everything else with a harmless 0.
#
#  Keyboard state comes from the engine (Input.raw_key_states), so touch,
#  controller and real keyboards all reach games that poll GetAsyncKeyState.
#  NOTE: never use print/p for logging here (RGSS shows a message box).
# =============================================================================

module YamiWin32
  HWND = 0x5A11 # any non-zero handle; games only pass it back to us

  # Windows virtual-key code → SDL scancode
  VK = {}
  ("A".."Z").each_with_index { |c, i| VK[c.ord] = 4 + i }            # SDL_SCANCODE_A = 4
  (1..9).each { |d| VK[0x30 + d] = 29 + d }                           # 1..9 → 30..38
  VK[0x30] = 39                                                       # 0
  (0..11).each { |i| VK[0x70 + i] = 58 + i }                          # F1..F12
  (1..9).each { |d| VK[0x60 + d] = 88 + d }                           # numpad 1..9
  VK.merge!(
    0x60 => 98,  0x6E => 99,  0x6A => 85, 0x6B => 87, 0x6D => 86, 0x6F => 84, # numpad 0 . * + - /
    0x08 => 42,  0x09 => 43,  0x0D => 40, 0x1B => 41, 0x20 => 44,     # back tab enter esc space
    0x21 => 75,  0x22 => 78,  0x23 => 77, 0x24 => 74,                 # pgup pgdn end home
    0x25 => 80,  0x26 => 82,  0x27 => 79, 0x28 => 81,                 # left up right down
    0x2D => 73,  0x2E => 76,                                          # insert delete
    0xA0 => 225, 0xA1 => 229, 0xA2 => 224, 0xA3 => 228, 0xA4 => 226, 0xA5 => 230,
    0xBA => 51,  0xBB => 46,  0xBC => 54, 0xBD => 45, 0xBE => 55, 0xBF => 56, # ; = , - . /
    0xC0 => 53,  0xDB => 47,  0xDC => 49, 0xDD => 48, 0xDE => 52,     # ` [ \ ] '
  )
  # generic modifiers match either side
  VK_PAIRS = { 0x10 => [225, 229], 0x11 => [224, 228], 0x12 => [226, 230] }.freeze

  KNOWN = %w[
    clienttoscreen copymemory createdirectory findwindow findwindowex getactivewindow
    getasynckeystate getclientrect getcomputername getcurrentprocessid getcurrentthreadid getcursorpos
    getdevicecaps getfileattributes getforegroundwindow getkeyboardlayout getkeyboardstate getkeystate
    getmodulefilename getprivateprofileint getprivateprofilestring getsystemdefaultlangid getsystemmetrics getsystempowerstatus
    gettickcount getuserdefaultlangid getuserdefaultuilanguage getusername getwindowlong getwindowlongptr
    getwindowrect getwindowtext getwindowthreadprocessid keybd_event lstrcpy lstrcpya
    lstrlen lstrlena mapvirtualkey mapvirtualkeyex messagebox messageboxa
    messageboxw movewindow multibytetowidechar queryperformancecounter queryperformancefrequency rtlmovememory
    screentoclient sendinput setforegroundwindow setwindowlong setwindowlongptr setwindowpos
    shgetfolderpath shgetspecialfolderpath showcursor showwindow timegettime toascii
    tounicode tounicodeex updatewindow widechartomultibyte writeprivateprofilestring
    getdesktopwindow getfocus getparent getmodulehandle loadlibrary setwindowtext
    setcursorpos systemparametersinfo setfocus
    shellexecute winexec createprocess
  ].freeze

  module_function

  # Live keyboard state: a 512-byte String from the engine (one byte per SDL
  # scancode). Input.raw_key_states only refreshes inside the engine's own
  # Input.update, which games that replace Input never call; it is only the
  # fallback.
  def raw_states
    Yami.respond_to?(:key_states) ? Yami.key_states : ((Input.yami_live_key_states rescue nil) || [])
  end

  def pressed?(states, sc)
    states.is_a?(String) ? states.getbyte(sc).to_i != 0 : !!states[sc]
  end

  def key_down?(vk, states = raw_states)
    vk = vk.to_i & 0xFF
    if (pair = VK_PAIRS[vk])
      return pair.any? { |sc| pressed?(states, sc) }
    end
    if vk == 0x01 || vk == 0x02 || vk == 0x04 # mouse buttons
      return (Input.press?(Input.const_get([nil, :MOUSELEFT, :MOUSERIGHT, nil, :MOUSEMIDDLE][vk])) rescue false)
    end
    sc = VK[vk]
    sc ? pressed?(states, sc) : false
  end

  # Write bytes into a caller-provided buffer string, in place.
  def fill(buf, bytes)
    return unless buf.is_a?(String)
    bytes = bytes.b
    if buf.bytesize > 0
      data = bytes.byteslice(0, buf.bytesize)
      buf.force_encoding(Encoding::BINARY)
      buf[0, data.bytesize] = data
    else
      buf.replace(bytes)
    end
  end

  def cstr(s)
    return "" unless s.is_a?(String)
    s.b.split("\0", 2).first.to_s
  end

  def ini_path(file)
    f = cstr(file).tr("\\", "/").sub(%r{\A\./}, "")
    f = "Game.ini" if f.empty?
    return f if File.exist?(f)
    Dir.glob("*").find { |x| x.downcase == File.basename(f).downcase } || f
  end

  def ini_read(file, section, key)
    path = ini_path(file)
    return nil unless File.exist?(path)
    cur = nil
    File.foreach(path, mode: "rb") do |line|
      line = line.chomp.strip
      if line =~ /\A\[(.+)\]\z/
        cur = $1
      elsif cur && cur.casecmp?(cstr(section)) && line.include?("=")
        k, v = line.split("=", 2)
        return v.strip if k.strip.casecmp?(cstr(key))
      end
    end
    nil
  rescue StandardError
    nil
  end

  def ini_write(file, section, key, value)
    path = ini_path(file)
    lines = File.exist?(path) ? File.read(path, mode: "rb").split(/\r?\n/) : []
    sec = cstr(section); k = cstr(key)
    idx = lines.index { |l| l.strip =~ /\A\[(.+)\]\z/ && $1.casecmp?(sec) }
    if idx.nil?
      lines << "[#{sec}]" << "#{k}=#{cstr(value)}"
    else
      j = idx + 1
      j += 1 while j < lines.size && lines[j] !~ /\A\s*\[/ && !(lines[j].include?("=") && lines[j].split("=", 2)[0].strip.casecmp?(k))
      if j < lines.size && lines[j].include?("=") && lines[j] !~ /\A\s*\[/
        lines[j] = "#{k}=#{cstr(value)}"
      else
        lines.insert(j, "#{k}=#{cstr(value)}")
      end
    end
    File.write(path, lines.join("\r\n") + "\r\n", mode: "wb")
    1
  rescue StandardError
    0
  end

  def screen_size
    [(Graphics.width rescue 640), (Graphics.height rescue 480)]
  end

  def save_dir
    d = (Yami.cfg("save_dir") if defined?(Yami) && Yami.respond_to?(:cfg))
    d = ENV["YAMI_DATA_DIR"] if d.nil? || d.empty?
    d.nil? || d.empty? ? Dir.pwd : d
  end

  # A game starting its own Game.exe (to restart after changing language or
  # settings) gets a real restart: the player relaunches it when it exits.
  def launch(cmd)
    exe = cmd.to_s.tr("\\", "/")
    restart = exe =~ /(\A|[\/\s"'])(game|#{Regexp.escape(File.basename(Dir.pwd))})[^\/]*\.exe/i ||
              exe =~ /\.exe\b/i && exe !~ /notepad|explorer|cmd\.exe|http/i
    Yami.log("game asked to start: #{exe.strip[0, 120]}#{restart ? " (restart: will relaunch when it exits)" : " (ignored)"}") rescue nil
    Yami.request_restart if restart && defined?(Yami) && Yami.respond_to?(:request_restart)
    !!restart
  end

  # ------------------------------------------------------------------ calls
  def call(name, args)
    case name
    # --- keyboard -------------------------------------------------------
    when "getasynckeystate", "getkeystate"
      key_down?(args[0]) ? 0x8000 : 0
    when "getkeyboardstate"
      st = raw_states
      fill(args[0], (0...256).map { |vk| key_down?(vk, st) ? 0x80 : 0 }.pack("C*"))
      1
    when "mapvirtualkey", "mapvirtualkeyex" then 0
    when "getkeyboardlayout" then 0x04090409
    when "keybd_event", "sendinput" then 0
    when "toascii", "tounicode", "tounicodeex" then 0

    # --- ini files ------------------------------------------------------
    when "getprivateprofilestring"
      # (section, key, default, buffer, size, file)
      v = ini_read(args[5], args[0], args[1]) || cstr(args[2])
      size = args[4].to_i
      out = v.b.byteslice(0, [size - 1, 0].max).to_s
      fill(args[3], out + "\0")
      out.bytesize
    when "getprivateprofileint"
      (ini_read(args[3], args[0], args[1]) || args[2]).to_i
    when "writeprivateprofilestring"
      ini_write(args[3], args[0], args[1], args[2])

    # --- strings --------------------------------------------------------
    when "multibytetowidechar"
      # (codepage, flags, str, len, wbuf, wlen)
      src = args[2].is_a?(String) ? args[2].b : ""
      len = args[3].to_i
      src = len < 0 ? src.split("\0", 2).first.to_s + "\0" : src.byteslice(0, len).to_s
      w = src.force_encoding(Encoding::UTF_8).scrub("?").encode(Encoding::UTF_16LE).b
      chars = w.bytesize / 2
      return chars if args[5].to_i == 0
      fill(args[4], w)
      [chars, args[5].to_i].min
    when "widechartomultibyte"
      # (codepage, flags, wstr, wlen, buf, len, default, used)
      src = args[2].is_a?(String) ? args[2].b : ""
      wlen = args[3].to_i
      if wlen < 0
        i = 0
        i += 2 while i + 1 < src.bytesize && src.getbyte(i) | src.getbyte(i + 1) != 0
        src = src.byteslice(0, i).to_s + "\0\0"
      else
        src = src.byteslice(0, wlen * 2).to_s
      end
      u = src.force_encoding(Encoding::UTF_16LE).scrub.encode(Encoding::UTF_8).b
      return u.bytesize if args[5].to_i == 0
      fill(args[4], u)
      [u.bytesize, args[5].to_i].min
    when "rtlmovememory", "copymemory"
      dst, src, n = args
      fill(dst, src.b.byteslice(0, n.to_i).to_s) if dst.is_a?(String) && src.is_a?(String)
      0
    when "lstrlen", "lstrlena" then cstr(args[0]).bytesize
    when "lstrcpy", "lstrcpya"
      fill(args[0], cstr(args[1]) + "\0"); 1

    # --- window ---------------------------------------------------------
    when "findwindow", "findwindowex", "getactivewindow", "getforegroundwindow",
         "getdesktopwindow", "getfocus", "getparent", "getmodulehandle", "loadlibrary"
      HWND
    when "getwindowthreadprocessid", "getcurrentthreadid", "getcurrentprocessid" then 1
    when "getwindowrect", "getclientrect"
      w, h = screen_size
      fill(args[1], [0, 0, w, h].pack("l4")); 1
    when "clienttoscreen", "screentoclient" then 1
    when "getcursorpos"
      x = (Input.mouse_x rescue 0); y = (Input.mouse_y rescue 0)
      # panoramic: menus are centred and work in the game's own coordinates
      x -= Yami::Wide.margin if defined?(Yami::Wide) && Yami::Wide.panoramic?
      fill(args[0], [x, y].pack("l2")); 1
    when "getsystemmetrics"
      w, h = screen_size
      { 0 => w, 1 => h, 4 => 0, 5 => 1, 6 => 1, 7 => 0, 8 => 0, 32 => 0, 33 => 0 }.fetch(args[0].to_i, 0)
    when "getdevicecaps" then 96
    when "getwindowlong", "getwindowlongptr", "setwindowlong", "setwindowlongptr" then 0
    when "setwindowpos", "movewindow", "showwindow", "updatewindow", "setforegroundwindow",
         "setwindowtext", "setcursorpos", "systemparametersinfo", "setfocus" then 1
    when "getwindowtext"
      t = ($yami_window_title ||= (ini_read("Game.ini", "Game", "Title") || "Game"))
      fill(args[1], t.b.byteslice(0, [args[2].to_i - 1, 0].max).to_s + "\0"); t.bytesize
    when "showcursor" then 0
    when "messagebox", "messageboxa", "messageboxw"
      text = cstr(args[1])
      (Kernel.send(:print, text) rescue nil) unless text.empty? # RGSS print = message box, intended here
      1

    # --- system ---------------------------------------------------------
    when "gettickcount", "timegettime"
      (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i & 0x7FFFFFFF
    when "queryperformancecounter"
      fill(args[0], [(Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1_000_000).to_i].pack("q")); 1
    when "queryperformancefrequency"
      fill(args[0], [1_000_000].pack("q")); 1
    when "getuserdefaultlangid", "getsystemdefaultlangid", "getuserdefaultuilanguage" then 0x0409
    when "getusername", "getcomputername"
      fill(args[0], "Player\0"); 1
    when "getmodulefilename"
      fill(args[1], "Game.exe\0"); 8
    when "shgetfolderpath", "shgetspecialfolderpath"
      # (hwnd, csidl, token, flags, path) / (hwnd, path, csidl, create)
      buf = name == "shgetfolderpath" ? args[4] : args[1]
      fill(buf, save_dir.b + "\0")
      name == "shgetfolderpath" ? 0 : 1
    when "createdirectory" then (Dir.mkdir(cstr(args[0])) rescue nil; 1)
    when "getfileattributes" then File.exist?(cstr(args[0])) ? (File.directory?(cstr(args[0])) ? 0x10 : 0x80) : -1
    when "getsystempowerstatus"
      fill(args[0], [1, 0, 100, 0, -1, -1].pack("CCCCll")); 1

    # --- starting programs: only "start the game again" means anything here
    when "shellexecute"   # (hwnd, verb, file, params, dir, show)
      launch(cstr(args[2]) + " " + cstr(args[3])) ? 42 : 2
    when "winexec"        # (cmdline, show)
      launch(cstr(args[0])) ? 32 : 2
    when "createprocess"  # (app, cmdline, ...)
      launch(cstr(args[0]) + " " + cstr(args[1])) ? 1 : 0
    else
      0
    end
  rescue StandardError => e
    (STDERR.write("[yami-win32] #{name}: #{e.class}: #{e.message}\n") rescue nil)
    0
  end
end

# The class games instantiate (and often reopen to add helpers).
class Win32API
  attr_reader :dll, :func

  KNOWN_SET = YamiWin32::KNOWN.to_h { |n| [n, true] }.freeze
  NAMES = {} # func name -> resolved name (Essentials creates these objects every frame)
  # Calls made for every key, every frame by older Essentials' input code
  # (GetAsyncKeyState + pbSameThread). Kept off the generic dispatcher.
  FAST = {
    "getasynckeystate" => ->(a) { YamiWin32.key_down?(a[0]) ? 0x8000 : 0 },
    "getkeystate" => ->(a) { YamiWin32.key_down?(a[0]) ? 0x8000 : 0 },
    "getforegroundwindow" => ->(_a) { YamiWin32::HWND },
    "getactivewindow" => ->(_a) { YamiWin32::HWND },
    "getcurrentthreadid" => ->(_a) { 1 },
    "getcurrentprocessid" => ->(_a) { 1 },
    "getwindowthreadprocessid" => ->(_a) { 1 },
  }.freeze

  def self.resolve(func)
    NAMES[func] ||= begin
      # GetPrivateProfileStringA / ...W → getprivateprofilestring
      n = func.downcase
      n = n[0..-2] if !KNOWN_SET[n] && n =~ /[aw]\z/ && KNOWN_SET[n[0..-2]]
      n.freeze
    end
  end

  def initialize(dll = "", func = "", imports = nil, export = nil, *_rest)
    @dll = dll.to_s
    @func = func.to_s
    @name = Win32API.resolve(@func)
    @fast = FAST[@name]
  end

  def call(*args)
    @fast ? @fast.call(args) : YamiWin32.call(@name, args)
  end
  alias Call call
end

MiniFFI = Win32API unless defined?(MiniFFI)

# -----------------------------------------------------------------------------
# Windows environment variables games rely on. Older Essentials' image loader
# runs Dir.chdir(ENV["TEMP"]) (TypeError: nil into String without it), and
# screenshots/saves use TEMP, APPDATA, USERPROFILE.
# -----------------------------------------------------------------------------
begin
  yami_home = (Yami.cfg("save_dir") if defined?(Yami) && Yami.respond_to?(:cfg)).to_s
  yami_home = ENV["YAMI_DATA_DIR"].to_s if yami_home.empty?
  yami_home = Dir.pwd if yami_home.empty?
  yami_tmp = File.join(yami_home, "Temp")
  Dir.mkdir(yami_tmp) unless File.directory?(yami_tmp)
  %w[TEMP TMP].each { |k| ENV[k] = yami_tmp if ENV[k].to_s.empty? || !File.directory?(ENV[k]) }
  %w[APPDATA LOCALAPPDATA USERPROFILE HOMEPATH].each { |k| ENV[k] = yami_home if ENV[k].to_s.empty? }
  ENV["USERNAME"] = "Player" if ENV["USERNAME"].to_s.empty?
  ENV["COMPUTERNAME"] = "ANDROID" if ENV["COMPUTERNAME"].to_s.empty?
  ENV["OS"] = "Windows_NT" if ENV["OS"].to_s.empty?
  # Essentials' FontInstaller looks for its fonts in %SystemRoot%\Fonts and
  # warns on every start when they are missing ("the look of the game's text
  # will not be optimal"), then tries to install them. The engine already
  # loads the game's Fonts folder, so point the Windows folder at the game.
  %w[SystemRoot windir WINDIR].each { |k| ENV[k] = Dir.pwd if ENV[k].to_s.empty? }
rescue StandardError => e
  (STDERR.write("[yami] Windows environment: #{e.message}\n") rescue nil)
end

# -----------------------------------------------------------------------------
# Windows file system semantics for game scripts:
#  * "\\" works as a path separator
#  * names match regardless of case (Windows-made games are full of
#    "Hero.png" vs "hero.png"; imported games live on case-sensitive storage)
#  * opening a folder as a file fails with "access denied" (Errno::EACCES),
#    which older Essentials (FileTests: pbGetFileChar) rescues — Linux would
#    fail later with Errno::EISDIR. The error matches both.
# -----------------------------------------------------------------------------
module Yami
  class DirAsFileError < Errno::EACCES; end

  module WinFS
    ORIG = {
      exist: File.method(:exist?), dir: File.method(:directory?),
      children: Dir.method(:children), pwd: Dir.method(:pwd),
    }
    @cache = {}
    @hits = 0

    module_function

    def path_arg?(f); f.is_a?(String) || (f.respond_to?(:to_path) && !f.is_a?(IO)); end

    def norm(f)
      return f unless path_arg?(f)
      s = f.is_a?(String) ? f : f.to_path
      s.include?("\\") ? s.tr("\\", "/") : s
    end

    def flush; @cache.clear; @resolved.clear; @answers.clear; end

    # A file was written, created, deleted or renamed: forget only what
    # involves its folder. Clearing everything made the game re-list its
    # folders from storage (Graphics/Characters on an SD card: ~200 ms) after
    # every write - and the overlay's status file is written every second.
    def forget(*files)
      dirs = files.filter_map do |f|
        next unless path_arg?(f)
        s = norm(f).to_s
        r = @resolved[s] || s
        [File.expand_path(File.dirname(s)), File.expand_path(File.dirname(r.to_s))]
      end.flatten.uniq
      return flush if dirs.empty?
      in_dirs = ->(p) { dirs.include?(File.expand_path(File.dirname(p.to_s))) }
      @cache.delete_if { |k, _| dirs.include?(File.expand_path(k.to_s)) }
      @resolved.delete_if { |k, v| in_dirs.(v) || in_dirs.(k) }
      @answers.each_value { |h| h.delete_if { |k, _| in_dirs.(k) || dirs.include?(File.expand_path(k.to_s)) } }
    rescue StandardError
      flush
    end
    @resolved = {}

    # Answers to existence queries (exist?, file?, directory?, ...) per
    # path. Games ask these constantly - Essentials probes several
    # extensions per image, some scripts every frame - and each one was a
    # trip through Android's shared-storage layer (~0.1-1 ms). Game files
    # don't change on their own; every write, delete, rename, mkdir and
    # chdir made through Ruby clears the answers.
    MEMO = %i[exist? file? directory? readable? size? zero?].freeze
    @answers = {}
    def answer(m, path)
      h = (@answers[m] ||= {})
      return h[path] if h.key?(path)
      @answers.clear if h.size > 20_000
      (@answers[m] ||= {})[path] = yield
    end

    # dir -> [exact names, downcased -> real name]; one directory read each
    def listing(dir)
      @cache[dir] ||= begin
        names = ORIG[:children].call(dir)
        h = {}
        names.each { |n| h[n.downcase] ||= n }
        [names.to_h { |n| [n, true] }, h]
      rescue StandardError
        [{}, {}]
      end
    end

    # The real path for f, matching each part case-insensitively when the
    # exact name doesn't exist. Unresolvable parts are kept as given.
    def resolve(f)
      return f unless path_arg?(f)
      s = norm(f)
      return s if s.empty?
      key = s.is_a?(String) ? s : s.to_s
      hit = @resolved[key]
      return hit if hit
      return(@resolved[key] = s) if ORIG[:exist].call(s)
      @resolved.clear if @resolved.size > 4096 # bounded; images are probed by many paths
      @resolved[key] = resolve_parts(s)
    end

    def resolve_parts(s)
      s = s.b unless s.valid_encoding? # Windows-1252 names from old scripts
      abs = s.start_with?("/")
      parts = s.split("/")
      cur = abs ? "/" : "."
      out = []
      parts.each_with_index do |part, i|
        next if part.empty? && i.zero?
        if part.empty? || part == "." || part == ".."
          out << part
          cur = File.join(cur, part)
          next
        end
        exact, lower = listing(cur)
        real = exact[part] ? part : lower[part.downcase]
        unless real
          out.concat(parts[i..-1])
          break
        end
        out << real
        cur = File.join(cur, real)
      end
      r = out.join("/")
      r = "/" + r if abs
      r += "/" if s.end_with?("/") && !r.end_with?("/")
      r
    end

    def dir_as_file!(path)
      return unless path.is_a?(String) && !path.empty?
      raise Yami::DirAsFileError, "Is a directory - #{path}" if answer(:directory?, path) { ORIG[:dir].call(path) }
    end

    def writes?(mode)
      m = mode.is_a?(String) ? mode : (mode.is_a?(Integer) ? (mode & (File::WRONLY | File::RDWR | File::CREAT)).nonzero? && "w" : nil)
      m.is_a?(String) && m =~ /[wa+]/
    end
  end

  # File.open / File.read & co.
  module WinFile
    READS = %i[read binread readlines foreach]
    QUERIES = %i[exist? file? directory? readable? writable? size size? zero? empty? mtime atime ctime
                 stat lstat ftype symlink? executable?]
    WRITES = %i[delete unlink write binwrite truncate chmod utime]
    PURE = %i[basename dirname extname split]

    %i[open new].each do |m|
      define_method(m) do |*a, **k, &b|
        if Yami::WinFS.path_arg?(a[0])
          a[0] = Yami::WinFS.resolve(a[0])
          if Yami::WinFS.writes?(a[1] || k[:mode])
            Yami::WinFS.forget(a[0])
          else
            Yami::WinFS.dir_as_file!(a[0])
          end
        end
        k.empty? ? super(*a, &b) : super(*a, **k, &b)
      end
    end
    READS.each do |m|
      define_method(m) do |*a, **k, &b|
        if Yami::WinFS.path_arg?(a[0])
          a[0] = Yami::WinFS.resolve(a[0])
          Yami::WinFS.dir_as_file!(a[0])
        end
        k.empty? ? super(*a, &b) : super(*a, **k, &b)
      end
    end
    QUERIES.each do |m|
      next unless File.respond_to?(m)
      memo = Yami::WinFS::MEMO.include?(m)
      define_method(m) do |*a, **k, &b|
        a[0] = Yami::WinFS.resolve(a[0]) if Yami::WinFS.path_arg?(a[0])
        if memo && a.size == 1 && k.empty? && !b && a[0].is_a?(String)
          Yami::WinFS.answer(m, a[0]) { super(*a) }
        else
          k.empty? ? super(*a, &b) : super(*a, **k, &b)
        end
      end
    end
    WRITES.each do |m|
      define_method(m) do |*a, **k, &b|
        a.map! { |f| Yami::WinFS.path_arg?(f) ? Yami::WinFS.resolve(f) : f }
        Yami::WinFS.forget(*a.select { |f| Yami::WinFS.path_arg?(f) })
        k.empty? ? super(*a, &b) : super(*a, **k, &b)
      end
    end
    define_method(:rename) do |from, to|
      Yami::WinFS.forget(from, to)
      super(Yami::WinFS.resolve(from), Yami::WinFS.resolve(to)).tap { Yami::WinFS.forget(from, to) }
    end
    PURE.each do |m|
      define_method(m) { |f, *a| super(Yami::WinFS.norm(f), *a) }
    end
  end

  module WinFileTest
    %i[exist? file? directory? size size? zero? readable?].each do |m|
      memo = Yami::WinFS::MEMO.include?(m)
      define_method(m) do |f, *a|
        r = Yami::WinFS.resolve(f)
        if memo && a.empty? && r.is_a?(String)
          Yami::WinFS.answer(m, r) { super(r) }
        else
          super(r, *a)
        end
      end
    end
  end

  module WinDir
    # Relative lookups depend on the current folder: drop cached resolutions
    # when it changes (and again when a block-form chdir returns).
    def chdir(*a, **k, &blk)
      a[0] = Yami::WinFS.resolve(a[0]) if Yami::WinFS.path_arg?(a[0])
      Yami::WinFS.flush
      if blk
        k.empty? ? super(*a) { |*x| Yami::WinFS.flush; blk.call(*x) }.tap { Yami::WinFS.flush } :
                   super(*a, **k) { |*x| Yami::WinFS.flush; blk.call(*x) }.tap { Yami::WinFS.flush }
      else
        k.empty? ? super(*a) : super(*a, **k)
      end
    end

    %i[exist? entries children foreach each_child empty?].each do |m|
      next unless Dir.respond_to?(m)
      define_method(m) do |*a, **k, &b|
        a[0] = Yami::WinFS.resolve(a[0]) if Yami::WinFS.path_arg?(a[0])
        k.empty? ? super(*a, &b) : super(*a, **k, &b)
      end
    end
    %i[mkdir rmdir delete unlink].each do |m|
      define_method(m) do |*a, &b|
        a[0] = Yami::WinFS.resolve(a[0]) if Yami::WinFS.path_arg?(a[0])
        Yami::WinFS.forget(a[0])
        super(*a, &b).tap { Yami::WinFS.forget(a[0]) }
      end
    end
    %i[glob []].each do |m|
      define_method(m) do |*a, **k, &b|
        a[0] = a[0].is_a?(Array) ? a[0].map { |x| Yami::WinFS.norm(x) } : Yami::WinFS.norm(a[0])
        k.empty? ? super(*a, &b) : super(*a, **k, &b)
      end
    end
  end
end
class << Errno::EISDIR
  def ===(e); e.is_a?(Yami::DirAsFileError) || super; end
end
File.singleton_class.prepend(Yami::WinFile)
FileTest.singleton_class.prepend(Yami::WinFileTest)
Dir.singleton_class.prepend(Yami::WinDir)
(STDERR.write("[yami] Win32API compatibility layer active\n") rescue nil)
