# =============================================================================
#  Yami runtime layer — loaded by mkxp-z (preloadScript) before game scripts.
#
#  * Map data streaming   : map files read into RAM on a background thread;
#                           transfers decode from memory instead of storage
#  * Optimized maps       : per-map compact tilesets built by yami_optimizer.rb
#  * Speed-up             : frame-rate / frame-skip / hybrid turbo (F10)
#  * Widescreen           : full or panoramic, for RMXP and Pokémon Essentials
#  * Save redirection     : SaveN.rxdata written to Yami's per-game folder
#  * Graphics warm-up     : tilesets/characters pulled into the OS page cache
#
#  Developer API:
#    Graphics.yami_disable_turbo!   (Graphics.kirin_disable_turbo! is accepted too)
#    Yami.version, Yami.turbo?, Yami.widescreen
#    System.invalidate_optimized_maps
# =============================================================================

# Output goes to a file on Android (not a tty), where Ruby buffers it; flush
# every line so the engine log is current even if the game hangs.
# NOTE: never use print/p here — in RGSS those open a message box.
$stdout.sync = true rescue nil
$stderr.sync = true rescue nil
STDOUT.sync = true rescue nil
STDERR.sync = true rescue nil
$yami_t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
(STDERR.write("[yami] preload start (#{RUBY_VERSION}, cwd #{Dir.pwd})\n") rescue nil)

module Yami
  VERSION = "0.1.0"
  CFG = {}

  begin
    path = ENV["YAMI_CFG"]
    if path && File.exist?(path)
      File.foreach(path) do |line|
        k, v = line.chomp.split("=", 2)
        CFG[k] = v if k && v
      end
    end
  rescue StandardError
  end

  module_function

  def version; VERSION; end
  def cfg(k, d = nil); CFG.fetch(k, d); end
  def flag(k); CFG[k] == "true"; end
  def num(k, d); (v = CFG[k]) ? v.to_f : d; end
  def game_dir; @game_dir ||= Dir.pwd; end
  def rgss; defined?(RGSS_VERSION) ? RGSS_VERSION.to_i : ($RGSS_VERSION || 1).to_i; end

  def norm(path)
    p = path.to_s.tr("\\", "/").sub(%r{\A\./}, "")
    p.downcase
  end

  def log(msg)
    t = Process.clock_gettime(Process::CLOCK_MONOTONIC) - $yami_t0
    STDERR.write(format("[yami %6.2fs] %s\n", t, msg)) rescue nil
  end

  # Tiny status channel to the Android overlay (turbo state etc.).
  def status(key, value)
    @status ||= {}
    return if @status[key] == value
    @status[key] = value
    f = cfg("status_file")
    return unless f
    # IO.write, not File.*: Yami's own file must not go through the game's
    # Windows file layer (whose caches every game write updates)
    IO.write(f, @status.map { |k, v| "#{k}=#{v}\n" }.join)
  rescue StandardError
  end

  # --------------------------------------------------------------- frame hooks
  @tick_hooks = []
  @once_hooks = []
  @frame_no = 0
  @hook_fails = {}.compare_by_identity
  @hook_errors = []
  @hooks_off = []

  def on_tick(&b); @tick_hooks << b; end
  def once_pending; @once_hooks.size; end
  def once_when(cond, &b); @once_hooks << [cond, b]; end

  def frame_no; @frame_no; end

  # A failing hook must not cost every frame (an exception and a log line
  # per frame is a stutter of its own): each distinct error is logged once,
  # and a hook failing 100 frames in a row is switched off.
  def tick_hook_failed(h, e)
    n = (@hook_fails[h] = @hook_fails.fetch(h, 0) + 1)
    key = "#{e.class}: #{e.message}"
    unless @hook_errors.include?(key)
      @hook_errors << key
      where = (e.backtrace || []).find { |l| l.include?("yami_") } || (e.backtrace || [])[0]
      log("tick hook: #{key} (#{where})")
    end
    return if n < 100
    @hooks_off << h
    @hook_fails.delete(h)
    log("tick hook switched off after 100 failures in a row: #{key}")
  end

  def tick
    @frame_no += 1
    @key_snap = nil # new frame: read the keyboard afresh
    @tick_hooks.each do |h|
      h.call
      @hook_fails.delete(h) if @hook_fails.key?(h)
    rescue StandardError => e
      tick_hook_failed(h, e)
    end
    unless @hooks_off.empty?
      @tick_hooks.reject! { |h| @hooks_off.include?(h) }
      @hooks_off.clear
    end
    run_once
  end

  # Runs pending one-shot hooks whose condition now holds. Called every frame,
  # and from object creation (games build their title screen before the first
  # Graphics.update).
  def run_once
    return if @once_hooks.empty? || @running_once
    begin
      @running_once = true
      ready = @once_hooks.select { |cond, _| (cond.call rescue false) }
      # Remove before running: a hook can never run twice, even if its body
      # creates objects that call back into run_once.
      @once_hooks -= ready
      ready.each do |_, b|
        begin
          b.call
        rescue StandardError => e
          log("once hook: #{e.class}: #{e.message}")
        end
      end
    ensure
      @running_once = false
    end
  end

  # Keyboard state, one byte per SDL scancode (String), or an Array from
  # raw_key_states on engines without the live accessor. Live state works even
  # when the game replaces Input.update (older Essentials polls Windows'
  # GetAsyncKeyState for every key, every frame). One snapshot per frame —
  # refreshed at each Graphics.update and after 4 ms for code that polls in a
  # loop without drawing — instead of a fresh 512-byte String per key query.
  @key_snap = nil
  @key_snap_t = 0.0
  def key_states
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    if @key_snap.nil? || now - @key_snap_t > 0.004
      live = (Input.yami_live_key_states rescue nil)
      @key_snap = live.is_a?(String) ? live : ((Input.raw_key_states rescue nil) || [])
      @key_snap_t = now
    end
    @key_snap
  end

  def key_states_stale!; @key_snap = nil; end

  def key_down?(scancode)
    st = key_states
    st.is_a?(String) ? st.getbyte(scancode).to_i != 0 : !!st[scancode]
  rescue StandardError
    false
  end
end

# Frame profile for the session log: what a long frame was spent on.
module Yami
  module Prof
    @acc = Hash.new(0.0)
    @cnt = Hash.new(0)
    @draw = 0.0
    class << self
      attr_reader :acc, :cnt
      attr_accessor :draw
      def measure(key)
        t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        yield
      ensure
        @acc[key] += Process.clock_gettime(Process::CLOCK_MONOTONIC) - t
        @cnt[key] += 1
      end
      def reset; @acc.clear; @cnt.clear; end
    end
  end
end

class << Graphics
  alias_method :yami_update, :update
  def update(*args)
    Yami.tick
    t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    r = yami_update(*args)
    Yami::Prof.draw = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t
    r
  end
end

# =============================================================================
#  Map data streaming (RAM cache)
# =============================================================================
module Yami
  module MapCache
    @bytes = {}
    @lock = Mutex.new
    @enabled = Yami.flag("map_cache")

    module_function

    def start
      return unless @enabled
      list = File.join(Yami.game_dir, ".yami/maps.txt")
      return unless File.exist?(list)
      budget = (Yami.num("map_cache_mb", 192) * 1024 * 1024).to_i
      entries = File.readlines(list).map { |l| l.chomp.split("\t") }.select { |e| e.size >= 2 }
      @thread = Thread.new do
        used = 0
        entries.each do |rel, size|
          size = size.to_i
          break if used + size > budget
          begin
            data = File.binread(File.join(Yami.game_dir, rel))
            @lock.synchronize { @bytes[Yami.norm(rel)] = data }
            used += data.bytesize
          rescue StandardError
          end
          Thread.pass
        end
        Yami.log("map cache: #{@bytes.size} maps, #{used / 1024} KiB")
      end
      @thread.priority = -2 rescue nil
    end

    def fetch(key)
      return nil unless @enabled
      @lock.synchronize { @bytes[key] }
    end

    def clear
      @lock.synchronize { @bytes.clear }
    end
  end

  # ===========================================================================
  #  Optimized maps (output of yami_optimizer.rb)
  # ===========================================================================
  module OptMaps
    @enabled = Yami.flag("optimized_maps")
    @maps = {}
    @variants = []
    @tilesets_ok = false

    module_function

    def dir; File.join(Yami.game_dir, ".yami/opt"); end
    def enabled?; @enabled && !@maps.empty?; end

    def stat_sig(path)
      st = File.stat(path)
      "#{st.size}:#{st.mtime.to_i}"
    rescue StandardError
      nil
    end

    def load_manifest
      return unless @enabled
      manifest = File.join(dir, "maps.txt")
      return unless File.exist?(manifest)
      lines = File.readlines(manifest).map(&:chomp)
      header = lines.shift.to_s.split("\t")   # tilesets_sig
      tilesets_src = Dir.glob(File.join(Yami.game_dir, "Data", "*")).find { |f| File.basename(f).downcase == "tilesets.rxdata" }
      @tilesets_ok = tilesets_src && stat_sig(tilesets_src) == header[1]
      unless @tilesets_ok
        Yami.log("optimized maps stale (Tilesets changed) — using originals")
        return
      end
      lines.each do |l|
        name, sig = l.split("\t")
        next unless name
        @maps["data/#{name.downcase}"] = [File.join(dir, "Data", name), sig, File.join(Yami.game_dir, "Data", name)]
      end
      vfile = File.join(dir, "variants.rxdata")
      @variants = File.exist?(vfile) ? Marshal.load(File.binread(vfile)) : []
      Yami.log("optimized maps: #{@maps.size} maps, #{@variants.size} tileset variants")
    rescue StandardError => e
      Yami.log("optimized maps disabled: #{e.message}")
      @maps.clear
    end

    # Original map changed since optimization? Then fall back to it.
    def lookup(key)
      e = @maps[key]
      return nil unless e
      opt, sig, src = e
      return nil unless File.exist?(opt)
      return nil if File.exist?(src) && stat_sig(src) != sig
      opt
    end

    def patch_tilesets(arr)
      return arr unless enabled? && arr.is_a?(Array)
      @variants.each { |id, ts| arr[id] = ts }
      arr
    end

    def invalidate!
      return unless File.directory?(dir)
      File.rename(dir, dir + ".disabled-#{Time.now.to_i}")
      @maps.clear
    rescue StandardError
    end
  end
end

alias yami_load_data load_data
def load_data(path, *rest)
  Yami::Prof.measure(:load_data) { yami_load_data_inner(path, *rest) }
end

def yami_load_data_inner(path, *rest)
  return yami_load_data(path, *rest) if !path.is_a?(String) || rest.first == true
  key = Yami.norm(path)
  if Yami::OptMaps.enabled? && (opt = Yami::OptMaps.lookup(key))
    begin
      return Marshal.load(File.binread(opt))
    rescue StandardError => e
      Yami.log("optimized map #{key} unreadable (#{e.message}); using original")
    end
  end
  if (bytes = Yami::MapCache.fetch(key))
    return Marshal.load(bytes)
  end
  obj = yami_load_data(path, *rest)
  obj = Yami::OptMaps.patch_tilesets(obj) if key == "data/tilesets.rxdata"
  obj
end

module System
  def self.invalidate_optimized_maps
    Yami::OptMaps.invalidate!
  end
end

# =============================================================================
#  Speed-up (turbo)
# =============================================================================
module Yami
  module Turbo
    @mode = Yami.cfg("turbo_mode", "framerate")
    @speed = [[Yami.num("turbo_speed", 3).to_i, 2].max, 10].min
    @toggle = Yami.flag("turbo_toggle")
    @scancode = Yami.num("turbo_scancode", 67).to_i
    @active = false
    @disabled = false
    @was_down = false
    @base_rate = nil
    @base_skip = nil

    class << self
      attr_reader :active
      attr_accessor :base_rate

      def disable!
        set(false)
        @disabled = true
        Yami.status("turbo_disabled", 1)
      end

      def poll
        return if @disabled
        down = Yami.key_down?(@scancode)
        if @toggle
          set(!@active) if down && !@was_down
        else
          set(down) if down != @active
        end
        @was_down = down
      end

      def set(on)
        return if on == @active
        if on
          @base_rate = Graphics.frame_rate
          @base_skip = (Graphics.frameskip rescue nil)
          # every mode targets a higher logic rate; skip modes also drop draws
          apply_rate(@base_rate * @speed)
          (Graphics.frameskip = true rescue nil) unless @mode == "framerate"
        else
          apply_rate(@base_rate) if @base_rate
          (Graphics.frameskip = (@base_skip ? true : false) rescue nil) unless @mode == "framerate"
        end
        @active = on
        Yami.status("turbo", on ? 1 : 0)
      end

      def apply_rate(r)
        Graphics.yami_set_frame_rate(r.to_i.clamp(10, 600))
      end
    end
  end

  def self.turbo?; Turbo.active; end
end

class << Graphics
  alias_method :yami_set_frame_rate, :frame_rate=
  # Games that change the frame rate while turbo is on keep their new base rate.
  # "60 FPS" setting (like Kirin's): games asking for less run at 60 (RPG
  # Maker XP's 40). Essentials scales movement by Graphics.frame_rate, so it
  # walks at the right speed and looks smoother; animations counted in frames
  # play faster.
  def frame_rate=(v)
    v = 60 if Yami.flag("force_60") && v.to_i < 60
    if Yami::Turbo.active
      Yami::Turbo.base_rate = v
      return yami_set_frame_rate(v * (Yami.num("turbo_speed", 3).to_i.clamp(2, 10)))
    end
    yami_set_frame_rate(v)
  end

  def yami_disable_turbo!; Yami::Turbo.disable!; end
  if Yami.flag("force_60")
    Graphics.frame_rate = 60
    Yami.log("frame rate: forced to 60 fps")
  end
  def kirin_disable_turbo!; Yami::Turbo.disable!; end
end

Yami.on_tick { Yami::Turbo.poll }

# Real engine FPS for the Android info overlay, about once per second.
module Yami
  @fps_frames = 0
  @fps_t = nil
  # Frame-time monitor for the session log: every 10 s, how many frames ran
  # long (over 1.5x the frame time), the worst one, and how many of them had
  # a Ruby GC run in them.
  @hitch = { n: 0, gc: 0, worst: 0.0, frames: 0, t: nil }
  def self.hitch_tick(now)
    h = @hitch
    gc = GC.count
    if @last_frame_t
      dt = now - @last_frame_t
      target = 1.0 / [Graphics.frame_rate.to_i, 1].max
      h[:frames] += 1
      @sec_worst = dt if dt > (@sec_worst || 0)
      if dt > target * 1.5
        h[:n] += 1
        h[:gc] += 1 if gc != @last_gc
        h[:worst] = dt if dt > h[:worst]
        # breakdown of the long frame (at most one line a second)
        if !@last_detail || now - @last_detail >= 1.0
          @last_detail = now
          draw = Prof.draw.to_f
          parts = Prof.acc.sort_by { |_, v| -v }.map { |k, v| format("%s %.0f ms x%d", k, v * 1000, Prof.cnt[k]) }
          log(format("long frame %.0f ms: game %.0f ms, draw+wait %.0f ms%s%s", dt * 1000, (dt - draw) * 1000,
                     draw * 1000, gc != @last_gc ? ", GC" : "", parts.empty? ? "" : " | " + parts.join(", ")))
        end
      end
    end
    @last_frame_t = now
    @last_gc = gc
    Prof.reset
    h[:t] ||= now
    return if now - h[:t] < 10
    log(format("frames: %d long of %d (%d with GC), worst %.0f ms", h[:n], h[:frames], h[:gc], h[:worst] * 1000)) if h[:frames] > 0
    h[:n] = h[:gc] = h[:frames] = 0
    h[:worst] = 0.0
    h[:t] = now
  end

  def self.fps_tick
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    hitch_tick(now) rescue nil
    @fps_t ||= now
    @fps_frames += 1
    return if now - @fps_t < 1.0
    status("fps", (@fps_frames / (now - @fps_t)).round)
    status("worst", ((@sec_worst || 0) * 1000).round)
    @sec_worst = 0
    # the game's own logic rate (not turbo): the app matches the display to it
    status("rate", (Turbo.active && Turbo.base_rate) || Graphics.frame_rate)
    @fps_frames = 0
    @fps_t = now
  end
end
Yami.on_tick { Yami.fps_tick }

# Progress trace for the engine log: first frame, scene changes, a heartbeat.
module Yami
  @frames = 0
  @last_scene = nil
  @last_beat = 0
  def self.trace_tick
    @frames += 1
    log("first Graphics.update — game scripts are running") if @frames == 1
    sc = ($scene.class.name rescue nil)
    if sc != @last_scene
      log("scene: #{sc}")
      @last_scene = sc
    end
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    if now - @last_beat >= 10
      @last_beat = now
      log("alive: frame #{@frames}, #{Graphics.width}x#{Graphics.height}, scene #{sc}")
    end
  end
end
Yami.on_tick { Yami.trace_tick }

# =============================================================================
#  Save redirection for classic RMXP save files (SaveN.rxdata in game folder)
# =============================================================================
module Yami
  module Saves
    PATTERN = /\A(?:\.\/)?save\d*\.(?:rxdata|rvdata2?)\z/i
    @dir = Yami.cfg("save_dir")
    @on = Yami.flag("redirect_saves") && @dir && !@dir.empty?

    module_function

    # Returns the redirected path, or the original when not a save file.
    def redirect(path, writing = false)
      return path unless @on && path.is_a?(String)
      p = path.tr("\\", "/")
      return path unless p =~ PATTERN
      target = File.join(@dir, File.basename(p))
      return target if writing || raw_exist?(target)
      raw_exist?(path) ? path : target   # legacy save in game folder still loads
    end

    # Bypasses our own File.exist? hook.
    def raw_exist?(p)
      File.respond_to?(:yami_exist?) ? File.yami_exist?(p) : File.exist?(p)
    end

    def on?; @on; end
  end
end

if Yami::Saves.on?
  class << File
    alias_method :yami_open, :open
    def open(path, *args, **kw, &b)
      mode = args.first.to_s
      writing = mode.include?("w") || mode.include?("a") || mode.include?("+")
      yami_open(Yami::Saves.redirect(path, writing), *args, **kw, &b)
    end
    %i[exist? file? mtime size delete unlink].each do |m|
      next unless method_defined?(m) || respond_to?(m)
      alias_method :"yami_#{m}", m
      define_method(m) do |*a|
        a[0] = Yami::Saves.redirect(a[0]) if a[0].is_a?(String)
        send(:"yami_#{m}", *a)
      end
    end
  end
  class << FileTest
    alias_method :yami_exist?, :exist?
    def exist?(p); yami_exist?(Yami::Saves.redirect(p)); end
  end
  alias yami_save_data save_data
  def save_data(obj, path); yami_save_data(obj, Yami::Saves.redirect(path, true)); end
end

# Native entry points, saved before any game script can replace them.
module Yami
  # A screenshot as the game sees its screen: in panoramic, only its own
  # (centred) area, at its own size — games draw it back in their coordinates.
  def self.snap_ui(bmp)
    return bmp unless defined?(Yami::Wide) && Yami::Wide.panoramic? && bmp.is_a?(Bitmap)
    m = Yami::Wide.margin
    bw, bh = Yami::Wide.base
    return bmp unless m > 0 && bw && bmp.width > bw
    out = Bitmap.new(bw, bh)
    out.blt(0, 0, bmp, Rect.new(m, 0, bw, bh))
    bmp.dispose
    out
  rescue StandardError
    bmp
  end
end

class << Graphics
  alias_method :yami_native_resize, :resize_screen
  alias_method :yami_native_width, :width
  alias_method :yami_native_height, :height
  alias_method :yami_native_snap, :snap_to_bitmap if method_defined?(:snap_to_bitmap)
end

# =============================================================================
#  Older Pokémon Essentials (v13-v17) screen system
#
#  Its Sprite_Resizer adds a decorative border (BORDERWIDTH/BORDERHEIGHT around
#  the game, e.g. 640x480 -> 800x600), scales every Sprite/Viewport/Plane by a
#  window-size factor and replaces Graphics.snap_to_bitmap with a Windows DLL
#  screenshot. None of that makes sense on a phone: the game ends up drawn in
#  a corner of a bigger screen with the background repeating around it.
#  Yami pins it to factor 1, no border, and the real screen size.
# =============================================================================
module Yami
  module OldEss
    @active = false
    module_function

    def active?; @active; end

    def resizer?
      Object.private_method_defined?(:pbSetResizeFactor) || Object.method_defined?(:pbSetResizeFactor)
    end

    def const_or(name, d)
      Object.const_defined?(name) ? Object.const_get(name).to_i : d
    end

    def set_const(name, v, owner = Object)
      old = $VERBOSE
      return unless owner.const_defined?(name, false)
      $VERBOSE = nil
      owner.send(:remove_const, name)
      owner.const_set(name, v)
    ensure
      $VERBOSE = old
    end

    # The game's design resolution, before any border, from whichever
    # constants its Essentials generation uses: v19+ Settings::SCREEN_*,
    # v18 top-level SCREEN_* (e.g. Pokémon Myth: 512x384), v15-17
    # DEFAULTSCREEN*. nil if none (not Essentials).
    def design_size
      st = (::Settings if Object.const_defined?(:Settings) && ::Settings.is_a?(Module))
      if st && st.const_defined?(:SCREEN_WIDTH) && st.const_defined?(:SCREEN_HEIGHT)
        return [st::SCREEN_WIDTH.to_i, st::SCREEN_HEIGHT.to_i]
      end
      return [SCREEN_WIDTH.to_i, SCREEN_HEIGHT.to_i] if Object.const_defined?(:SCREEN_WIDTH) && Object.const_defined?(:SCREEN_HEIGHT)
      if Object.const_defined?(:DEFAULTSCREENWIDTH) && Object.const_defined?(:DEFAULTSCREENHEIGHT)
        return [DEFAULTSCREENWIDTH.to_i, DEFAULTSCREENHEIGHT.to_i]
      end
      nil
    rescue StandardError
      nil
    end

    # Remembered the first time it is known (before anything overwrites it).
    def base
      @base ||= design_size
    end

    BORDER_CONSTS = %i[BORDERWIDTH BORDERHEIGHT BORDER_WIDTH BORDER_HEIGHT]

    # Makes the engine screen exactly the game's size (widened if enabled).
    def fit
      w, h = base
      tw, th = defined?(Yami::Wide) ? Yami::Wide.target(w, h) : [w, h]
      Yami::Wide.base = [w, h] if defined?(Yami::Wide) && Yami::Wide.on?
      Graphics.yami_native_resize(tw, th)
      [tw, th]
    end

    def apply
      return if @active || !resizer?
      @active = true
      w, h = base
      BORDER_CONSTS.each { |c| set_const(c, 0) }
      $ResizeOffsetX = 0
      $ResizeOffsetY = 0

      Object.class_eval do
        def pbSetResizeFactor(_factor = 1, norecalc = false)
          $ResizeOffsetX = 0
          $ResizeOffsetY = 0
          if respond_to?(:pbSetResizeFactor2, true)
            begin
              pbSetResizeFactor2(1.0, norecalc) # rescales existing sprites back to 1x
            rescue StandardError => e
              Yami.log("pbSetResizeFactor2: #{e.class}: #{e.message}")
            end
          end
          $ResizeFactor = 1.0
          $ResizeFactorMul = 100
          Yami::OldEss.fit
        end
        def pbConfigureFullScreen(*); pbSetResizeFactor(1); end
        def pbConfigureWindowedScreen(*); pbSetResizeFactor(1); end
        private :pbSetResizeFactor, :pbConfigureFullScreen, :pbConfigureWindowedScreen
      end

      # The border option draws a frame picture over the edges; turn it off.
      if defined?(PokemonSystem) && PokemonSystem.method_defined?(:border)
        PokemonSystem.class_eval { def border; 0; end }
      end
      ($ResizeBorder.visible = false) rescue nil

      # Its screenshot needs rubyscreen.dll; use the engine's.
      if Graphics.respond_to?(:yami_native_snap)
        loc = (Graphics.method(:snap_to_bitmap).source_location rescue nil)
        if loc
          Graphics.define_singleton_method(:snap_to_bitmap) { |*a| Yami.snap_ui(yami_native_snap(*a)) }
        end
      end

      tw, th = fit
      # Sprite_Resizer keeps the size in class variables; keep them in step.
      gw = defined?(Yami::Wide) && Yami::Wide.panoramic? ? w : tw
      %i[@@width @@height].zip([gw, th]).each do |cv, v|
        Graphics.class_variable_set(cv, v) if Graphics.class_variable_defined?(cv)
      end
      set_const(:DEFAULTSCREENWIDTH, gw)
      pbSetResizeFactor(1) rescue nil
      Yami::Wide.claim! if defined?(Yami::Wide)
      Yami.log("older Essentials screen: #{w}x#{h} -> #{tw}x#{th}, border off, factor 1")
    end
  end
end
module Yami
  module OldEss
    module_function

    # Any game with Essentials' border system, whatever its functions are
    # called (versions and fan edits differ).
    def border_game?
      return false unless base
      BORDER_CONSTS.any? { |c| Object.const_defined?(c) } || resizer? || !$ResizeOffsetX.nil?
    end

    # Undo the border and the window factor. Idempotent; cheap.
    def neutralize!
      $ResizeOffsetX = 0
      $ResizeOffsetY = 0
      if $ResizeFactor && $ResizeFactor != 1.0
        $ResizeFactor = 1.0
        $ResizeFactorMul = 100
        begin
          pbRefreshResizeFactor if respond_to?(:pbRefreshResizeFactor, true)
        rescue StandardError => e
          Yami.log("pbRefreshResizeFactor: #{e.class}: #{e.message}")
        end
      end
      BORDER_CONSTS.each do |c|
        set_const(c, 0) if Object.const_defined?(c) && Object.const_get(c) != 0
      end
      if defined?(PokemonSystem) && PokemonSystem.method_defined?(:border) &&
         PokemonSystem.instance_method(:border).source_location.to_a[0].to_s !~ /yami_/
        PokemonSystem.class_eval { def border; 0; end }
      end
      ($ResizeBorder.visible = false) if $ResizeBorder.respond_to?(:visible=) && $ResizeBorder.visible rescue nil
      # Its fade-to-black viewport is a fixed 640x480: make it cover the display.
      size = [Graphics.yami_native_width, Graphics.yami_native_height]
      if @fade_size != size && Graphics.class_variable_defined?(:@@fadeoutvp)
        vp = Graphics.class_variable_get(:@@fadeoutvp)
        if vp.respond_to?(:yami_vp_set_rect) && !(vp.disposed? rescue false)
          vp.yami_vp_set_rect(Rect.new(0, 0, *size))
          vp.instance_variable_set(:@yami_last, nil)
          Yami::Wide::Layers.unclip(vp) if defined?(Yami::Wide::Layers)
        end
        @fade_size = size
      end
      if Graphics.respond_to?(:yami_native_snap)
        loc = (Graphics.method(:snap_to_bitmap).source_location rescue nil)
        if loc && loc[0].to_s !~ /yami_/
          Graphics.define_singleton_method(:snap_to_bitmap) { |*a| Yami.snap_ui(yami_native_snap(*a)) }
        end
      end
    end

    def expected_size
      w, h = base
      defined?(Yami::Wide) ? Yami::Wide.target(w, h) : [w, h]
    end

    def tick
      return unless border_game?
      unless @logged
        @logged = true
        Yami.log("older Essentials border system: base #{base.inspect}, resizer=#{resizer?}, " \
                 "offsets=#{$ResizeOffsetX.inspect}/#{$ResizeOffsetY.inspect}, factor=#{$ResizeFactor.inspect}")
      end
      neutralize!
      apply unless active?
      fit if [Graphics.yami_native_width, Graphics.yami_native_height] != expected_size
      pin_size!
    end

    # Sprite_Resizer keeps the screen size in Graphics' @@width/@@height and
    # its resize_screen overwrites them with whatever it is asked for (Myth:
    # the bordered 800x600). Code that reads them directly must see the size
    # the game is laid out in: its own (panoramic) or the full one (full/off).
    def pin_size!
      w, h = base
      if defined?(Yami::Wide) && Yami::Wide.on? && !Yami::Wide.panoramic?
        w, h = Graphics.yami_native_width, Graphics.yami_native_height
      end
      [[:@@width, w], [:@@height, h]].each do |cv, v|
        Graphics.class_variable_set(cv, v) if Graphics.class_variable_defined?(cv) && Graphics.class_variable_get(cv) != v
      end
    end
  end
end

# Every screen-size request ends here — including the game's own alias of
# resize_screen (Sprite_Resizer's "oldresizescreen"), taken after this runs.
class << Graphics
  def resize_screen(w, h)
    req = [w, h]
    w = w.to_i; h = h.to_i # older Essentials passes floats (size * factor)
    if Yami::OldEss.border_game?
      Yami::OldEss.neutralize!
      w, h = Yami::OldEss.base # never the bordered/scaled size
    end
    if defined?(Yami::Wide) && Yami::Wide.on?
      Yami::Wide.base = [w, h]
      w, h = Yami::Wide.target(w, h)
    end
    if (@yami_resize_logs = (@yami_resize_logs || 0) + 1) <= 12
      from = caller.find { |c| c !~ /yami_/ }.to_s.sub(/:in .*/, "")
      Yami.log("screen: #{req.join('x')} requested by #{from.empty? ? 'Yami' : from} -> #{w}x#{h}")
    end
    yami_native_resize(w, h)
  end
end

# Essentials draws frames while its scripts are still loading, so keep checking.
Yami.on_tick { Yami::OldEss.tick }

# --- native map renderer -----------------------------------------------------
# Essentials draws maps with a Ruby tilemap (CustomTilemap): many sprites
# rebuilt in Ruby as the map scrolls (stutter). The engine's own Tilemap draws
# the same map on the GPU — Kirin's "native map renderer". On by default;
# "GPU map renderer" in the settings (native_tilemap=false) turns it off.
module Yami::NativeTilemap
  # Tilesets taller than this are never handed to the GPU tilemap: the engine
  # takes its oversized-image path for them, which draws blank/black tiles on
  # Android (Pokémon Myth: 256x26000). Kirin's "Optimize maps" fixes the same
  # thing on disk; here each map gets, in memory, a compact tileset of just the
  # tile rows it uses and a remapped copy of its data for drawing only.
  COMPACT_ABOVE = 4096
  WATCH = {}.compare_by_identity   # map_data Table -> renderer (runtime edits)

  # Runtime map edits mirrored into the drawn copy. A captured original, not
  # prepend: a game script aliasing Table#[]= afterwards would otherwise
  # recurse forever (prepend + alias).
  def self.hook_table_edits
    return if ::Table.instance_variable_get(:@yami_edits)
    ::Table.instance_variable_set(:@yami_edits, true)
    orig = ::Table.instance_method(:[]=)
    ::Table.send(:define_method, :[]=) do |*a|
      r = orig.bind_call(self, *a)
      if !WATCH.empty? && (tm = WATCH[self])
        tm.yami_tile_set(a) rescue nil
      end
      r
    end
  end

  module Compact
    def tileset=(v); @yami_ts = v; yami_sync; end
    def tileset; @yami_ts; end
    def map_data=(v)
      WATCH.delete(@yami_md) if @yami_md
      @yami_md = v
      yami_sync
    end
    def map_data; @yami_md; end
    def priorities=(v); @yami_pr = v; yami_sync; end
    def priorities; @yami_pr; end

    def dispose
      WATCH.delete(@yami_md) if @yami_md
      yami_drop_compact
      super
    end

    def yami_compact?; !!@yami_cts; end

    # Runtime change to the map's own data: mirror it into the drawn copy.
    def yami_tile_set(args)
      return unless @yami_cmd && args.size == @yami_md_dims
      v = args[-1]
      if v >= 384 && !@yami_rows.key?((v - 384) >> 3)
        @yami_key = nil
        return yami_sync     # a tile row this map didn't use yet
      end
      @yami_cmd[*args[0..-2]] = yami_map_id(v)
    end

    private

    def yami_map_id(id)
      return id if id < 384
      384 + (@yami_rows[(id - 384) >> 3] << 3) + ((id - 384) & 7)
    end

    def yami_raw(m, v)
      ::Tilemap.instance_method(m).bind(self).call(v)
    end

    def yami_huge?(ts)
      ts && !(ts.disposed? rescue true) && ts.height > COMPACT_ABOVE
    end

    def yami_drop_compact
      @yami_cts.dispose if @yami_cts && !(@yami_cts.disposed? rescue true)
      @yami_cts = @yami_cmd = @yami_rows = @yami_key = nil
    end

    def yami_sync
      ts, md, pr = @yami_ts, @yami_md, @yami_pr
      if yami_huge?(ts)
        return unless md                     # wait for the map (no huge atlas)
        key = [ts.object_id, md.object_id]
        yami_build(ts, md) unless @yami_key == key && @yami_cts
        yami_raw(:tileset=, @yami_cts)
        yami_raw(:map_data=, @yami_cmd)
        yami_raw(:priorities=, yami_priorities(pr)) if pr
        WATCH[md] = self
      else
        yami_drop_compact
        WATCH.delete(md) if md
        yami_raw(:tileset=, ts) if ts
        yami_raw(:map_data=, md) if md
        yami_raw(:priorities=, pr) if pr
      end
    end

    def yami_build(ts, md)
      yami_drop_compact
      xs, ys, zs = md.xsize, md.ysize, md.zsize
      max_row = ts.height / 32
      fast = Yami::Prof.measure(:compact_tileset) { yami_build_fast(md, max_row) } rescue nil
      if fast
        rows, cmd = fast
      else
        rows, cmd = yami_build_slow(md, max_row)
      end
      cts = Bitmap.new(256, [rows.size, 1].max * 32)
      rows.each { |old, nw| cts.blt(0, nw * 32, ts, Rect.new(0, old * 32, 256, 32)) }
      @yami_rows = rows
      @yami_cts, @yami_cmd, @yami_key = cts, cmd, [ts.object_id, md.object_id]
      @yami_md_dims = zs > 1 ? 4 : (ys > 1 ? 3 : 2)
      @yami_cpr_src = nil
      Yami.log("map renderer: compact tileset #{rows.size} rows (#{rows.size * 32}px of #{ts.height}px)#{fast ? '' : ' (slow path)'}")
    end

    # The whole map in a few native array operations (a map loaded while
    # walking - Essentials' connected maps - must not cost a frame): the
    # engine Table's serialized form is 5 int32 + int16 cells.
    def yami_build_fast(md, max_row)
      if md.respond_to?(:yami_remap_rows) && ::Table.respond_to?(:_load)
        order, data = md.yami_remap_rows(max_row)   # native, one pass
        rows = {}
        order.each { |r| rows[r] = rows.size }
        return [rows, ::Table._load(data)]
      end
      return nil unless md.respond_to?(:_dump) && ::Table.respond_to?(:_load)
      bin = md._dump(-1)
      hdr = bin.byteslice(0, 20)
      ids = bin.byteslice(20, bin.bytesize - 20).unpack("s<*")
      return nil unless ids.size == md.xsize * md.ysize * md.zsize
      tiles = ids.uniq.select { |i| i >= 384 }
      used = tiles.map { |i| (i - 384) >> 3 }.uniq.select { |r| r < max_row }.sort
      rows = {}
      used.each { |r| rows[r] = rows.size }
      top = [ids.max || 0, 383].max
      lut = Array.new(top + 1) { |i| i }
      tiles.each do |i|
        r = rows[(i - 384) >> 3]
        lut[i] = r ? 384 + (r << 3) + ((i - 384) & 7) : 0
      end
      ids.each_with_index { |i, k| ids[k] = 0 if i < 0 } if ids.min.to_i < 0
      out = []
      ids.each_slice(8192) { |sl| out.concat(lut.values_at(*sl)) }
      [rows, ::Table._load(hdr + out.pack("s<*"))]
    end

    def yami_build_slow(md, max_row)
      xs, ys, zs = md.xsize, md.ysize, md.zsize
      rows = {}
      zs.times do |z| ys.times do |y| xs.times do |x|
        id = md[x, y, z]
        next if id.nil? || id < 384
        r = (id - 384) >> 3
        rows[r] = rows.size if r < max_row && !rows.key?(r)
      end end end
      @yami_rows = rows
      cmd = Table.new(xs, ys, zs)
      zs.times do |z| ys.times do |y| xs.times do |x|
        id = md[x, y, z] || 0
        cmd[x, y, z] = (id >= 384 && !rows.key?((id - 384) >> 3)) ? 0 : yami_map_id(id)
      end end end
      [rows, cmd]
    end

    def yami_priorities(pr)
      return @yami_cpr if @yami_cpr_src.equal?(pr) && @yami_cpr
      cpr = Table.new(384 + [@yami_rows.size, 1].max * 8)
      n = [pr.xsize, 384].min
      n.times { |i| cpr[i] = pr[i] }
      @yami_rows.each do |old, nw|
        8.times do |c|
          src = 384 + (old << 3) + c
          cpr[384 + (nw << 3) + c] = pr[src] if src < pr.xsize
        end
      end
      @yami_cpr_src, @yami_cpr = pr, cpr
      cpr
    end
  end

  # Essentials variants hand their tilemap extra properties (v18:
  # terrain_tags, others elsewhere). The engine Tilemap renders without them;
  # keep whatever is set so the scripts that read it back still work.
  def self.renderer
    @renderer ||= Class.new(::Tilemap) do
      include Compact
      def method_missing(name, *args, &blk)
        n = name.to_s
        if n.end_with?("=") && args.size == 1
          (@yami_extra ||= {})[n.chomp("=")] = args[0]
        elsif args.empty? && !blk && n =~ /\A[a-z_]\w*\z/
          (@yami_extra ||= {})[n]
        else
          super
        end
      end

      def respond_to_missing?(name, priv = false)
        n = name.to_s
        n.end_with?("=") || (@yami_extra && @yami_extra.key?(n)) || super
      end
    end
  end

  def self.install
    return true if @done
    return false unless Object.const_defined?(:TilemapLoader) && Object.const_defined?(:Tilemap)
    @done = true
    hook_table_edits
    unless TilemapLoader.method_defined?(:setClass) && TilemapLoader.method_defined?(:updateClass)
      Yami.log("native map renderer: unfamiliar TilemapLoader, left as is")
      return true
    end
    TilemapLoader.class_eval do
      alias_method :yami_game_updateClass, :updateClass
      def updateClass
        return yami_game_updateClass if @yami_native_failed
        begin
          setClass(Yami::NativeTilemap.renderer)
        rescue StandardError => e
          @yami_native_failed = true
          Yami.log("native map renderer failed (#{e.class}: #{e.message}); using the game's")
          @tilemap = nil if @tilemap && @tilemap.class == Yami::NativeTilemap.renderer && (@tilemap.disposed? rescue true)
          yami_game_updateClass
        end
      end
    end
    Yami.log("native map renderer: Essentials' TilemapLoader uses the engine Tilemap")
    true
  end
end

# Native map renderer for Essentials (see Yami::NativeTilemap), unless disabled.
unless Yami::CFG["native_tilemap"] == "false"
  # Locals, not @ivars: the engine evaluates preload scripts with self = nil,
  # so a top-level `@x ||= ...` raised FrozenError on every frame.
  ntm_done = false
  Yami.on_tick { ntm_done ||= (defined?(Yami::NativeTilemap) && Yami::NativeTilemap.install) }
end

# =============================================================================
#  GPU map renderer for Pokémon Essentials v20+ (TilemapRenderer)
# =============================================================================
# v20+ draws maps with one Ruby sprite per tile and walks all of them every
# frame (~900 in 16:9, plus repositioning and re-sorting while scrolling):
# the main cost of walking around. Kirin replaces it with a native renderer;
# here TilemapRenderer.new hands out a subclass that keeps the game's
# interface but draws each loaded map ($map_factory.maps) with one engine
# Tilemap. Same depth rules as v21: priorities, bridges (bridge tiles drop to
# the ground while on a bridge), reflective tiles below reflections (-100).
# Left alone when a plugin changed TilemapRenderer, the game uses extra
# autotiles or zoom, or native_tilemap=false.
module Yami
  module V20Maps
    module_function

    def eligible?
      return @eligible unless @eligible.nil?
      @eligible = begin
        why = nil
        if !defined?(::TilemapRenderer) || !defined?(::Game_Map) || !defined?(::GameData::TerrainTag)
          why = "not Essentials v20+"
        elsif ::TilemapRenderer::ZOOM_X != 1 || ::TilemapRenderer::ZOOM_Y != 1
          why = "map zoom"
        elsif !::TilemapRenderer::EXTRA_AUTOTILES.empty?
          why = "extra autotiles"
        else
          files = %i[initialize update refresh_tile refresh_tile_bitmap refresh_tile_z check_if_screen_moved].map do |m|
            ::TilemapRenderer.instance_method(m).source_location&.first rescue :missing
          end
          why = "TilemapRenderer changed by a script" if files.uniq.size != 1 || files.include?(:missing)
        end
        if why
          Yami.log("GPU map renderer (v20+): not used (#{why})")
          false
        else
          Yami.log("GPU map renderer (v20+): Essentials' TilemapRenderer drawn by the engine")
          true
        end
      rescue StandardError => e
        Yami.log("GPU map renderer (v20+): not used (#{e.class}: #{e.message})")
        false
      end
    end

    def install
      return true if @installed
      return false unless defined?(::TilemapRenderer) && defined?(::Scene_Map)
      @installed = true
      klass = renderer_class
      ::TilemapRenderer.singleton_class.send(:define_method, :new) do |*a, &b|
        if equal?(::TilemapRenderer) && Yami::V20Maps.eligible?
          klass.new(*a, &b)
        else
          super(*a, &b)
        end
      end
      true
    end

    # Copies of a map's data split by reflective tiles: [others, reflective].
    def split(data, refl_ids)
      xs, ys, zs = data.xsize, data.ysize, data.zsize
      main = Table.new(xs, ys, zs)
      refl = Table.new(xs, ys, zs)
      if data.respond_to?(:_dump) && ::Table.respond_to?(:_load)
        bin = data._dump(-1)
        hdr = bin.byteslice(0, 20)
        ids = bin.byteslice(20, bin.bytesize - 20).unpack("s<*")
        top = [ids.max.to_i, 0].max
        lm = Array.new(top + 1) { |i| refl_ids[i] ? 0 : i }
        lr = Array.new(top + 1) { |i| refl_ids[i] ? i : 0 }
        ids.map! { |i| i < 0 ? 0 : i }
        om = []; orf = []
        ids.each_slice(8192) { |sl| om.concat(lm.values_at(*sl)); orf.concat(lr.values_at(*sl)) }
        return [::Table._load(hdr + om.pack("s<*")), ::Table._load(hdr + orf.pack("s<*"))]
      end
      zs.times { |z| ys.times { |y| xs.times { |x|
        id = data[x, y, z].to_i
        if refl_ids[id] then refl[x, y, z] = id else main[x, y, z] = id end
      } } }
      [main, refl]
    end

    def renderer_class
      @renderer_class ||= Class.new(::TilemapRenderer) do
        def initialize(viewport)
          @tilesets  = ::TilemapRenderer::TilesetBitmaps.new
          @autotiles = ::TilemapRenderer::AutotileBitmaps.new
          @tone      = Tone.new(0, 0, 0, 0)
          @color     = Color.new(0, 0, 0, 0)
          @last_tone = Tone.new(0, 0, 0, 0)
          @last_color = Color.new(0, 0, 0, 0)
          @self_viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
          @viewport  = viewport || @self_viewport
          @ox = @oy = 0
          @visible = true
          @disposed = false
          @yami_ts = {}     # filename => [bitmap, count] (original images)
          @yami_at = {}
          @yami_maps = {}   # map_id => entry
        end

        def dispose
          return if @disposed
          @yami_maps.each_value { |e| yami_drop(e) }
          @yami_maps.clear
          (@yami_ts.values + @yami_at.values).each { |b, _| b.dispose if b && !b.disposed? }
          @yami_ts.clear
          @yami_at.clear
          @self_viewport.dispose
          @self_viewport = nil
          @disposed = true
        end

        def disposed?; @disposed; end

        def add_tileset(filename); yami_add(@yami_ts, filename) { pbGetTileset(filename) }; end
        def remove_tileset(filename); yami_remove(@yami_ts, filename); end
        def add_autotile(filename); yami_add(@yami_at, filename) { pbGetAutotile(filename) }; end
        def remove_autotile(filename); yami_remove(@yami_at, filename); end
        def add_extra_autotiles(_id); end
        def remove_extra_autotiles(_id); end
        def refresh; @yami_refresh = true; end

        def update
          return if @disposed
          tone_changed = @last_tone != @tone
          color_changed = @last_color != @color
          @last_tone = @tone.clone if tone_changed
          @last_color = @color.clone if color_changed
          bridge = ($PokemonGlobal.bridge rescue 0).to_i > 0
          live = {}
          $map_factory.maps.each do |map|
            id = map.map_id
            e = @yami_maps[id]
            if e.nil? || @yami_refresh || !e[:map].equal?(map) || !e[:data].equal?(map.data) ||
               e[:tileset] != map.tileset_name || e[:autotiles] != map.autotile_names
              yami_drop(e) if e
              e = @yami_maps[id] = yami_build(map)
              tone_changed = color_changed = true
              e[:bridge] = nil
            end
            live[id] = true
            ox = (map.display_x.to_f / Game_Map::X_SUBPIXELS).round
            oy = (map.display_y.to_f / Game_Map::Y_SUBPIXELS).round
            if e[:bridge] != bridge
              e[:bridge] = bridge
              e[:main].priorities = bridge ? e[:prio_bridge] : e[:prio]
            end
            e[:tilemaps].each do |tm|
              tm.ox = ox
              tm.oy = oy
              tm.tone = @tone if tone_changed
              tm.color = @color if color_changed
              tm.update
            end
          end
          @yami_maps.keys.each do |id|
            next if live[id]
            yami_drop(@yami_maps.delete(id))
          end
          @yami_refresh = false
        end

        # runtime edits of the map's own data, mirrored into the split copies
        def yami_tile_set(args)
          @yami_maps.each_value do |e|
            next unless e[:split]
            v = args[-1]
            idx = args[0..-2]
            if e[:refl_ids][v]
              e[:main_data][*idx] = 0
              e[:refl_data][*idx] = v
            else
              e[:main_data][*idx] = v
              e[:refl_data][*idx] = 0
            end
          end
        end

        private

        def yami_add(store, filename)
          return if filename.nil? || filename.empty?
          if (e = store[filename])
            e[1] += 1
          else
            store[filename] = [yield, 1]
          end
        end

        def yami_remove(store, filename)
          return if filename.nil? || filename.empty? || !store[filename]
          e = store[filename]
          e[1] -= 1
          return if e[1] > 0
          store.delete(filename)
          e[0].dispose if e[0] && !e[0].disposed?
        end

        def yami_tilemap(map, data, prio)
          tm = Yami::NativeTilemap.renderer.new(@viewport)
          tm.tileset = @yami_ts[map.tileset_name]&.first
          map.autotile_names.each_with_index do |name, i|
            next if name.nil? || name.empty? || i > 6
            bmp = @yami_at[name]&.first
            tm.autotiles[i] = bmp if bmp
          end
          tm.map_data = data
          tm.priorities = prio
          tm
        end

        def yami_build(map)
          prio = map.priorities
          tags = map.terrain_tags
          n = prio.xsize
          refl_ids = {}
          bridge_ids = []
          n.times do |i|
            t = tags ? tags[i].to_i : 0
            next if t == 0
            d = GameData::TerrainTag.try_get(t)
            next unless d
            refl_ids[i] = true if i >= 48 && d.shows_reflections
            bridge_ids << i if d.bridge
          end
          prio_bridge = prio
          unless bridge_ids.empty?
            prio_bridge = prio.clone
            bridge_ids.each { |i| prio_bridge[i] = 0 }
          end
          e = { map: map, data: map.data, tileset: map.tileset_name, autotiles: map.autotile_names.dup,
                prio: prio, prio_bridge: prio_bridge, refl_ids: refl_ids }
          if refl_ids.empty?
            e[:main] = yami_tilemap(map, map.data, prio)
            e[:tilemaps] = [e[:main]]
          else
            main_data, refl_data = Yami::V20Maps.split(map.data, refl_ids)
            refl_prio = prio.clone
            refl_ids.each_key { |i| refl_prio[i] = 0 if i < refl_prio.xsize }
            e[:main] = yami_tilemap(map, main_data, prio)
            refl = yami_tilemap(map, refl_data, refl_prio)
            refl.yami_ground_z = -100 if refl.respond_to?(:yami_ground_z=)
            e.merge!(split: true, main_data: main_data, refl_data: refl_data)
            e[:tilemaps] = [refl, e[:main]]
            Yami::NativeTilemap::WATCH[map.data] = self
          end
          e
        end

        def yami_drop(e)
          return unless e
          Yami::NativeTilemap::WATCH.delete(e[:data]) if e[:split]
          e[:tilemaps].each { |tm| tm.dispose unless tm.disposed? }
        end
      end
    end
  end
end

unless Yami::CFG["native_tilemap"] == "false"
  v20_done = false
  Yami.on_tick do
    v20_done ||= begin
      if defined?(::TilemapRenderer)
        Yami::NativeTilemap.hook_table_edits if defined?(::Table)
        Yami::V20Maps.install
      else
        false
      end
    end
  end
end

# =============================================================================
#  Widescreen
# =============================================================================
module Yami
  module Wide
    @mode = Yami.cfg("widescreen", "off")
    @ratio = Yami.num("ratio", 0.0)
    @base = nil

    class << self
      attr_accessor :base
      def mode; @mode; end
      def on?; @mode != "off" && @ratio > 1.0; end

      # "auto": Pokémon Essentials (menus drawn for 4:3) -> panoramic, other
      # games -> full. Decided as soon as the game's first scripts exist.
      def panoramic?
        return false unless on?
        return true if @mode == "panoramic"
        return false unless @mode == "auto"
        return @auto unless @auto.nil?
        pano = essentials?
        if pano || ($yami_boot_frames || 0) > 0
          @auto = pano
          Yami.log("widescreen auto: #{pano ? 'panoramic (Pokémon Essentials)' : 'full'}")
        end
        pano
      end

      # Pokémon Essentials, any generation, recognisable while its scripts load:
      # its screen constants (v15-17 DEFAULTSCREEN*, v18 SCREEN_* + BORDER_*,
      # v19+ Settings::SCREEN_*), or its Sprite_Resizer. (PBSpecies is not
      # usable: Essentials loads it from its data files later on.)
      def essentials?
        return true if Yami::OldEss.design_size
        Object.const_defined?(:PBSpecies) || Object.const_defined?(:BORDER_WIDTH) ||
          Object.const_defined?(:BORDERWIDTH) || ($ResizeFactorMul.is_a?(Integer) && Object.const_defined?(:ScreenBorder))
      rescue StandardError
        false
      end

      def target(w, h)
        return [w, h] unless on?
        nw = ((h * @ratio) / 4.0).round * 4
        nw > w ? [nw, h] : [w, h]
      end

      def real_w; Graphics.yami_width; end
      def base_w; (@base || [real_w])[0]; end
      def margin; panoramic? ? (real_w - base_w) / 2 : 0; end

      # --- map code vs UI ----------------------------------------------------
      # Panoramic: map code works with the full display width; everything else
      # (battles, messages, menus, title) keeps the game's width and is centred.
      # mkxp-z names script sections "NNN:Name". Two kinds of map code:
      #  * map rendering (Spriteset_Map, tilemap, character sprites): anything
      #    running inside it is map, e.g. dark-cave / flash overlays that
      #    Essentials creates from event handlers while the spriteset is built.
      #    Nothing in there opens a menu or a battle.
      #  * map logic (Game_Map, Game_Player, Game_Event...): only as the direct
      #    caller. Essentials starts wild battles from inside Game_Player#update
      #    and runs event messages inside the map update; those stay UI.
      RENDER_SECTION = /\A(?:Spriteset_Map|Spriteset_MapAnimation|Sprite_Character|
                          Tilemap|CustomTilemap|TilemapLoader|TilemapRenderer)/ix
      MAP_SECTION = /\A(?:Game_Map|Game_Player|Game_Character|Game_Event|Game_Follower|
                       Sprite_Reflection|Sprite_Shadow|Sprite_SurfBase|DependentEvent|Weather|
                       RPG__Weather|PField_Weather|Overworld_?Weather|Follow)/ix
      INFRA_SECTION = /\A(?:Sprite_?Resizer)/i
      # message system: textboxes / choices span the 16:9 width over the map
      DIALOG_SECTION = /\A(?:Messages?\b|PokemonMessages|Window_Message)/ix
      # window/text libraries: count as whoever called them
      LIB_SECTION = /\A(?:SpriteWindow|DrawText|BitmapCache|SpriteWrapper|AnimatedBitmap|Sprite_Window)/ix

      # :render, :map, :ui or :infra for a backtrace path
      # (no path: code run from C, e.g. by the engine itself — never a game script)
      def section_kind(path)
        return :infra unless path.is_a?(String) && !path.empty?
        (@section_kind ||= {})[path] ||= begin
          path = path.scrub("?") unless path.valid_encoding? # names from Windows code pages
          name = File.basename(path).sub(/\A\[?\d+\]?[:\s]*/, "").sub(/\.rb\z/, "")
          if path.include?("yami_") || path.start_with?("<internal") || name =~ INFRA_SECTION
            :infra
          elsif name =~ RENDER_SECTION
            :render
          elsif name =~ MAP_SECTION
            :map
          elsif name =~ DIALOG_SECTION
            :dialog
          elsif name =~ LIB_SECTION
            :lib
          else
            :ui
          end
        end
      end

      # Map overlays whose methods are also called from UI-side code (e.g. the
      # dark-cave sprite: Flash re-centres its light from field-move code).
      # Wrapped once the game's scripts have loaded (nothing aliases them
      # afterwards), so their code always counts as map rendering.
      RENDER_CLASSES = %w[DarknessSprite]
      def render_depth; @render_depth || 0; end
      def render_depth=(v); @render_depth = v; end

      def wrap_render_classes!
        return unless panoramic?
        RENDER_CLASSES.each do |n|
          next unless Object.const_defined?(n)
          k = Object.const_get(n)
          next if !k.is_a?(Class) || k.instance_variable_get(:@yami_render)
          k.instance_variable_set(:@yami_render, true)
          # Captured originals, not prepend: a later `alias` of these methods
          # then simply wraps ours (prepend + alias would recurse forever).
          (k.public_instance_methods(false) + k.private_instance_methods(false)).uniq.each do |m|
            orig = k.instance_method(m)
            priv = k.private_method_defined?(m)
            k.send(:define_method, m) do |*a, &b|
              Yami::Wide.render_depth += 1
              begin
                orig.bind(self).call(*a, &b)
              ensure
                Yami::Wide.render_depth -= 1
              end
            end
            k.send(:private, m) if priv
          end
          Yami.log("panoramic: #{n} draws at full width")
        end
      end

      # Games ask for Graphics.width hundreds of times a frame; walking the
      # stack each time cost milliseconds and fed the GC (stutter). A call
      # site (its 3 nearest frames) gets the same answer within a frame, so
      # the full walk runs once per site per frame.
      # Key: the 3 nearest frames of game code (Yami's layer and the game's
      # own resizer wrappers skipped, they're the same for every caller), or
      # nil when the nearest 8 frames don't have 3 (then: no caching).
      def site_key(locs)
        k = 0
        n = 0
        locs.each do |l|
          next if section_kind(l.path) == :infra
          k = (k * 31 + l.lineno) ^ l.path.hash
          return k if (n += 1) == 3
        end
        nil
      end

      def site_cache(kind)
        f = Yami.frame_no
        if @site_frame != f
          @site_frame = f
          @site_map = {}
          @site_dialog = {}
        end
        kind == :map ? @site_map : @site_dialog
      end

      def map_caller?
        return true if (@render_depth || 0) > 0
        key = site_key(caller_locations(2, 8))
        return map_caller_walk unless key
        cache = site_cache(:map)
        r = cache[key]
        return r unless r.nil?
        cache[key] = map_caller_walk
      rescue StandardError => e
        # Graphics.width must never take a game down: treat as UI
        Yami.log("map_caller?: #{e.class}: #{e.message}") unless @mc_logged
        @mc_logged = true
        false
      end

      def map_caller_walk
        nearest = true
        caller_locations(3, 40).each do |loc|
          k = section_kind(loc.path)
          next if k == :infra
          return true if k == :render || (nearest && k == :map)
          nearest = false
        end
        false
      end

      # Is this the message system, while the map is showing? (window
      # libraries are transparent; anything else stops the search)
      def dialog_caller?
        return false unless Yami::Wide::Layers.map_shown_cached?
        key = site_key(caller_locations(2, 8))
        return dialog_caller_walk unless key
        cache = site_cache(:dialog)
        r = cache[key]
        return r unless r.nil?
        cache[key] = dialog_caller_walk
      rescue StandardError
        false
      end

      def dialog_caller_walk
        caller_locations(3, 40).each do |loc|
          k = section_kind(loc.path)
          next if k == :infra || k == :lib
          return k == :dialog
        end
        false
      end

      # Shared full-width layer for wide dialogue (unclipped, above the map).
      def dialog_viewport
        rw, rh = Graphics.yami_width, Graphics.yami_height
        v = @dialog_vp
        if v.nil? || (v.disposed? rescue true) || @dialog_size != [rw, rh]
          (v.dispose rescue nil) if v
          v = Viewport.allocate
          v.send(:yami_vp_init, 0, 0, rw, rh)
          v.z = 99_999
          Yami::Wide::Layers.unclip(v)
          @dialog_vp = v
          @dialog_size = [rw, rh]
        end
        v
      end

      # Panoramic: "Show Picture" images are cutscene art in the game's
      # coordinates; centre the map's picture layer (Spriteset_Map @viewport2,
      # RMXP and Essentials) like other UI. Checked each frame: cheap.
      def center_pictures!
        return unless panoramic?
        sp = ($scene.instance_variable_get(:@spriteset) rescue nil)
        return unless sp && sp.class.name.to_s.include?("Spriteset_Map")
        vp = sp.instance_variable_get(:@viewport2)
        return if !vp.is_a?(Viewport) || vp.instance_variable_get(:@yami_pic) || (vp.disposed? rescue true)
        bw, bh = base
        r = [0, 0, bw, bh] # game coordinates; the engine centres the UI layer
        vp.yami_vp_set_rect(Rect.new(*r))
        vp.instance_variable_set(:@yami_last, r)
        vp.yami_unclipped = false if vp.respond_to?(:yami_unclipped=)
        Yami::Wide::Layers.forget_map(vp)
        vp.instance_variable_set(:@yami_pic, true)
      rescue StandardError => e
        Yami.log("pictures layer: #{e.class}: #{e.message}")
      end

      # Panoramic + a game that defines its own Graphics.width (older
      # Essentials): menus keep the game's width, map code (camera, tilemap,
      # map viewports) sees the full display width.
      def claim_panoramic!
        %i[width height].each do |m|
          meth = (Graphics.method(m) rescue nil)
          loc = meth && meth.source_location
          next unless loc && !loc[0].to_s.include?("yami_")
          native = m == :width ? :yami_native_width : :yami_native_height
          # Never the game's own value for UI: older Essentials keeps it in
          # @@width/@@height, which Pokémon Myth sets to the bordered 800x600
          # later on (menus/textboxes then laid out for 800x600 in a 640x480
          # frame: shifted screens, text off screen).
          idx = m == :width ? 0 : 1
          Graphics.define_singleton_method(m) do
            if Yami::Wide.map_caller? || (idx == 0 && Yami::Wide.dialog_caller?)
              send(native)
            else
              (Yami::Wide.base || [send(native), send(native)])[idx]
            end
          end
          Yami.log("panoramic: wrapped the game's Graphics.#{m} (UI: the game's size, map: the full #{m})")
        end
      end

      # Older Essentials keeps the size in DEFAULTSCREENWIDTH and may redefine
      # Graphics.width/height in Ruby — possibly after this runtime started.
      # Report the real size to it (full mode). Cheap; runs every frame.
      def claim!
        return unless on?
        return claim_panoramic! if panoramic?
        rw = Graphics.yami_width
        if Object.const_defined?(:DEFAULTSCREENWIDTH) && DEFAULTSCREENWIDTH != rw
          Yami::OldEss.base # remember the game's own size first
          Yami::OldEss.set_const(:DEFAULTSCREENWIDTH, rw)
        end
        %i[width height].each do |m|
          loc = (Graphics.method(m).source_location rescue nil)
          next unless loc && !loc[0].to_s.include?("yami_")
          native = m == :width ? :yami_width : :yami_height
          Graphics.define_singleton_method(m) { send(native) }
          Yami.log("widescreen: game redefined Graphics.#{m}; reporting the real #{m}")
        end
      end
    end
  end

  def self.widescreen; Wide.mode; end
end

if Yami::Wide.on?
  class << Graphics
    alias_method :yami_width, :width
    alias_method :yami_height, :height
    # Panoramic: UI code sees the original width; map code sees the full width.
    def width
      return yami_width unless Yami::Wide.panoramic?
      Yami::Wide.map_caller? || Yami::Wide.dialog_caller? ? yami_width : Yami::Wide.base_w
    end
  end

  # Widen the default resolution right away (RMXP games never call resize_screen).
  Graphics.resize_screen(Graphics.yami_width, Graphics.height)
  Yami.on_tick { Yami::Wide.claim!; Yami::Wide.center_pictures!; Yami::Wide::Curtains.sync; Yami::Wide::Layers.sync }
  # map overlay classes, as soon as they exist (one constant lookup per frame)
  Yami.on_tick { Yami::Wide.wrap_render_classes! }

  # --- full-screen viewports ----------------------------------------------------
  module Yami::Wide
    # Where a viewport the game asks for should really be drawn. Returns the
    # rect and whether it is a centred full-screen UI viewport.
    # kind: :ui_full / :ui (panoramic UI: kept exactly as the game set it —
    # the engine draws the whole UI layer in the centred box), :map (map
    # code: screen coordinates, full width), :plain (full / off modes)
    def self.adjust(x, y, w, h)
      bw, bh = base
      full = x == 0 && w == bw && h == bh
      if panoramic?
        return [[x, y, (full ? Graphics.yami_width : w), h], :map] if map_caller?
        return [[x, y, w, h], full ? :ui_full : :ui]
      end
      [[x, y, (full ? Graphics.yami_width : w), h], :plain] # full-screen effects span the display
    end

    # Panoramic: fades and flashes on a centred full-screen UI viewport (its
    # colour) are mirrored onto the side margins, so the whole display fades.
    module Curtains
      @list = []
      class << self
        def track(vp); @list << [vp, nil] unless @list.any? { |v, _| v.equal?(vp) }; end

        def make(x, w)
          v = Viewport.allocate
          v.send(:yami_vp_init, x, 0, w, Graphics.yami_height)
          Yami::Wide::Layers.unclip(v)
          v
        end

        def sync
          return if @list.empty?
          m = Yami::Wide.margin
          @list.reject! do |entry|
            vp, cur = entry
            if (vp.disposed? rescue true)
              cur&.each { |c| c.dispose unless c.disposed? }
              next true
            end
            c = vp.color
            on = m > 0 && c.alpha.to_i > 0 && vp.visible
            if on && !cur
              rw = Graphics.yami_width
              cur = entry[1] = [make(0, m), make(m + Yami::Wide.base_w, rw - m - Yami::Wide.base_w)]
            end
            cur&.each do |cv|
              cv.visible = on
              next unless on
              cv.z = vp.z
              cv.color.set(c.red, c.green, c.blue, c.alpha)
            end
            false
          end
        rescue StandardError => e
          Yami.log("curtains: #{e.class}: #{e.message}")
          @list.clear
        end
      end
    end
  end

  # --- adaptive layers ----------------------------------------------------------
  # Panoramic: the engine clips every UI element to the centred box (UI never
  # spills into the sides) except layers marked unclipped (map, fades,
  # curtains). When a full-screen UI scene covers the map, or no map is shown,
  # the engine fills the sides with a soft, dimmed enlargement of the box
  # instead of black bars ("ambient"); over the map (pause menu, dialogue) the
  # sides show the map.
  module Yami::Wide::Layers
    # Sides of 4:3 menus on a wide screen: the menu's own art blurred, dimmed
    # further, or pure black (AMOLED). Setting "menu_sides".
    AMBIENT_DIM = { "art" => 45, "dim" => 80, "black" => 100 }.fetch(Yami.cfg("menu_sides", "art"), 45)
    @map_vps = []
    @ui_full = []   # [viewport, [children]]
    @state = nil

    class << self
      def engine?; Graphics.respond_to?(:yami_ui_clip); end

      def unclip(o)
        o.yami_unclipped = true if o.respond_to?(:yami_unclipped=)
      rescue StandardError
      end

      def classify(vp, kind)
        case kind
        when :map
          unclip(vp)
          @map_vps << vp unless @map_vps.any? { |v| v.equal?(vp) }
        when :ui_full
          Yami::Wide::Curtains.track(vp)
          @ui_full << [vp, {}.compare_by_identity] unless @ui_full.any? { |v, _| v.equal?(vp) }
        end
      end

      def forget_map(vp); @map_vps.reject! { |v| v.equal?(vp) }; end

      # children of full-screen UI viewports (background detection)
      def adopt(child, vp)
        return unless vp
        e = @ui_full.find { |v, _| v.equal?(vp) }
        e[1][child] = true if e
      end

      def alive?(o); !(o.disposed? rescue true); end

      # an opaque picture covering (most of) the box: a full-screen scene
      def covering?(vp, kids)
        bw, bh = Yami::Wide.base
        kids.reject! { |c, _| !alive?(c) }
        kids.each_key.any? do |c|
          next false unless (c.visible rescue false)
          b = (c.bitmap rescue nil)
          next false unless b && !(b.disposed? rescue true)
          # only pictures loaded from files are backgrounds; canvases games
          # draw on (Bitmap.new(w, h): HUDs, overlays, text) are see-through
          next false unless b.instance_variable_get(:@yami_file)
          next false if ((c.opacity rescue nil) || 255) < 200
          next true if c.is_a?(Plane) # tiles the whole viewport
          zx = (c.zoom_x rescue nil) || 1
          zy = (c.zoom_y rescue nil) || 1
          b.width * zx >= bw * 0.9 && b.height * zy >= bh * 0.5 && ((c.x rescue nil) || 0) <= bw * 0.1
        end
      end

      def map_shown?
        # the map's layers can outlive the map scene (Essentials keeps them in
        # class variables): only count them while the map scene runs
        return false unless $scene && $scene.class.name.to_s.include?("Scene_Map")
        @map_vps.reject! { |v| !alive?(v) }
        top = @map_vps.select { |v| v.visible }.map { |v| v.z.to_i }.max
        return false unless top
        @ui_full.reject! { |v, _| !alive?(v) }
        @ui_full.none? { |v, kids| v.visible && v.z.to_i >= top && covering?(v, kids) }
      end

      def map_shown_cached?
        @map_shown_cached = map_shown? if @map_shown_cached.nil?
        @map_shown_cached
      end

      def sync
        @map_shown_cached = Yami::Wide.panoramic? ? map_shown? : false
        return unless engine?
        pano = Yami::Wide.panoramic?
        m = Yami::Wide.margin
        bw, bh = Yami::Wide.base || [Graphics.yami_width, Graphics.yami_height]
        clip = pano && m > 0 ? [m, 0, bw, bh] : nil
        amb = clip && !@map_shown_cached ? [m, bw, AMBIENT_DIM] : nil
        state = [clip, amb]
        return if state == @state
        @state = state
        clip ? Graphics.yami_ui_clip(*clip) : Graphics.yami_ui_clip_off
        amb ? Graphics.yami_ambient(*amb) : Graphics.yami_ambient_off
      rescue StandardError => e
        Yami.log("layers: #{e.class}: #{e.message}")
        @state = :error
        (Graphics.yami_ui_clip_off; Graphics.yami_ambient_off) rescue nil
      end
    end
  end

  class Viewport
    alias_method :yami_vp_init, :initialize
    alias_method :yami_vp_set_rect, :rect= if method_defined?(:rect=)
    def initialize(*a)
      Yami.run_once unless Yami.once_pending.zero?
      Yami::OldEss.tick
      Yami::Wide.claim!
      # Normalise Viewport.new(rect) here. Never re-dispatch to `initialize`:
      # a game subclass may override it and hand a Rect back to super, which
      # would recurse forever (stack overflow seen with Pokémon Essentials).
      if a.size == 1 && a[0].is_a?(Rect)
        r = a[0]
        a = [r.x, r.y, r.width, r.height]
      end
      return yami_vp_init(*a) unless a.size == 4
      n, kind = Yami::Wide.adjust(*a)
      @yami_last = n
      yami_vp_init(*n)
      Yami::Wide::Layers.classify(self, kind)
    end

    # Older Essentials creates every viewport as 100x100 and sets the real
    # size through rect= (its Sprite_Resizer), so adjust here too. A rect the
    # game read back from us and hands over again is passed through as is.
    def rect=(r)
      return yami_vp_set_rect(r) unless r.respond_to?(:width)
      v = [r.x, r.y, r.width, r.height]
      return yami_vp_set_rect(r) if v == @yami_last
      n, kind = Yami::Wide.adjust(*v)
      @yami_last = n
      yami_vp_set_rect(n == v ? r : Rect.new(*n))
      Yami::Wide::Layers.classify(self, kind)
    end
  end

  # --- panoramic: object hooks ------------------------------------------------
  # UI objects are never moved or resized by Yami (the engine draws the UI
  # layer in the centred box). These hooks only: register children of
  # full-screen UI viewports (background detection), mark map overlays drawn
  # without a viewport as map, and put message windows over the map into the
  # wide dialogue layer. Captured originals (not prepend/alias): Essentials
  # aliases these same methods.
  if %w[panoramic auto].include?(Yami::Wide.mode)
    unless Sprite.instance_variable_get(:@yami_hooked)
      Sprite.instance_variable_set(:@yami_hooked, true)
      sinit = Sprite.instance_method(:initialize)
      ssetvp = Sprite.instance_method(:viewport=)
      Sprite.send(:define_method, :initialize) do |*a, &b|
        sinit.bind(self).call(*a, &b)
        if Yami::Wide.panoramic?
          vp = viewport
          if vp
            Yami::Wide::Layers.adopt(self, vp)
          elsif Yami::Wide.map_caller?
            Yami::Wide::Layers.unclip(self) # map overlay drawn without a viewport
          elsif Yami::Wide.dialog_caller?
            ssetvp.bind(self).call(Yami::Wide.dialog_viewport) # wide textbox over the map
          end
        end
      end
      Sprite.send(:define_method, :viewport=) do |v|
        ssetvp.bind(self).call(v)
        Yami::Wide::Layers.adopt(self, v) if v && Yami::Wide.panoramic?
      end
    end

    unless Plane.instance_variable_get(:@yami_hooked)
      Plane.instance_variable_set(:@yami_hooked, true)
      pinit = Plane.instance_method(:initialize)
      psetvp = Plane.instance_method(:viewport=)
      Plane.send(:define_method, :initialize) do |*a, &b|
        pinit.bind(self).call(*a, &b)
        Yami::Wide::Layers.adopt(self, a[0]) if a[0].is_a?(Viewport) && Yami::Wide.panoramic?
      end
      Plane.send(:define_method, :viewport=) do |v|
        psetvp.bind(self).call(v)
        Yami::Wide::Layers.adopt(self, v) if v && Yami::Wide.panoramic?
      end
    end

    # pictures loaded from files (backgrounds) vs canvases (overlays)
    unless Bitmap.instance_variable_get(:@yami_hooked)
      Bitmap.instance_variable_set(:@yami_hooked, true)
      binit = Bitmap.instance_method(:initialize)
      Bitmap.send(:define_method, :initialize) do |*a, &b|
        if a.size == 1 && a[0].is_a?(String)
          Yami::Prof.measure(:image_load) { binit.bind(self).call(*a, &b) }
          @yami_file = true
        else
          binit.bind(self).call(*a, &b)
        end
      end
    end

    # the game's screenshots: its own area at its own size
    if Graphics.respond_to?(:yami_native_snap)
      Graphics.define_singleton_method(:snap_to_bitmap) { |*a| Yami.snap_ui(yami_native_snap(*a)) }
    end
  end

  # --- after the game's scripts are loaded ------------------------------------
  Yami.once_when(-> { defined?(Game_Player) && defined?(Game_Map) }) do
    Yami::OldEss.apply # must settle the real size first
    rw = Graphics.yami_width
    rh = Graphics.height
    essentials = defined?(Settings) && Settings.const_defined?(:SCREEN_WIDTH)
    # Older Essentials has its own camera code: never apply the stock RMXP patches to it.
    essentials_old = !essentials && %i[DEFAULTSCREENWIDTH PBSpecies PokeBattle_Pokemon PokemonSystem]
                                      .any? { |c| Object.const_defined?(c) }
    silence = ->(&blk) { v = $VERBOSE; $VERBOSE = nil; blk.call; $VERBOSE = v }

    # Older Essentials (v15-v18): screen size lives in top-level constants, and
    # its Sprite_Resizer may redefine Graphics.width/height in Ruby.
    Yami::Wide.claim!

    if essentials
      if !Yami::Wide.panoramic?
        silence.call { Settings.send(:remove_const, :SCREEN_WIDTH); Settings.const_set(:SCREEN_WIDTH, rw) }
      end
      if Game_Player.const_defined?(:SCREEN_CENTER_X) && defined?(Game_Map::TILE_WIDTH)
        xs = defined?(Game_Map::X_SUBPIXELS) ? Game_Map::X_SUBPIXELS : 4
        silence.call do
          Game_Player.send(:remove_const, :SCREEN_CENTER_X)
          Game_Player.const_set(:SCREEN_CENTER_X, ((rw / 2) - (Game_Map::TILE_WIDTH / 2)) * xs)
        end
      end
    elsif essentials_old
      # Its camera reads Graphics.width (now the real width) — nothing to patch.
    elsif Game_Player.const_defined?(:CENTER_X) && Game_Player.const_defined?(:CENTER_Y)
      # Stock RMXP camera assumes a 20x15 tile screen. (Only games that still
      # have it: this hook can run while Essentials is loading, before
      # anything identifies it as Essentials.)
      if Game_Player.const_defined?(:CENTER_X)
        silence.call do
          Game_Player.send(:remove_const, :CENTER_X)
          Game_Player.const_set(:CENTER_X, ((rw / 2) - 16) * 4)
        end
      end
      Game_Map.class_eval do
        def scroll_right(distance)
          @display_x = [@display_x + distance, [(width * 128) - (Graphics.yami_width * 4), 0].max].min
        end
        def scroll_down(distance)
          @display_y = [@display_y + distance, [(height * 128) - (Graphics.yami_height * 4), 0].max].min
        end
      end
      Game_Player.class_eval do
        def center(x, y)
          max_x = [($game_map.width * 128) - (Graphics.yami_width * 4), 0].max
          max_y = [($game_map.height * 128) - (Graphics.yami_height * 4), 0].max
          $game_map.display_x = [0, [x * 128 - Game_Player::CENTER_X, max_x].min].max
          $game_map.display_y = [0, [y * 128 - Game_Player::CENTER_Y, max_y].min].max
        end
      end
    end

    Yami.log("widescreen #{Yami::Wide.mode}: #{rw}x#{rh} (base #{Yami::Wide.base.inspect})")
  end
end

# =============================================================================
#  Graphics warm-up: read tileset / autotile / character files once in the
#  background so the first map load doesn't wait on storage.
# =============================================================================
if Yami.flag("warm_graphics") && Yami.cfg("mode") != "optimize"
  Thread.new do
    begin
      sleep 0.5 until ($yami_boot_frames || 0) >= 300
      budget = 256 * 1024 * 1024
      used = 0
      %w[Tilesets Autotiles Characters Panoramas Fogs].each do |sub|
        Dir.glob(File.join(Yami.game_dir, "Graphics", sub, "**", "*")).each do |f|
          next unless File.file?(f)
          sz = File.size(f)
          break if used + sz > budget
          File.open(f, "rb") { |io| io.read(1 << 20) while !io.eof? }
          used += sz
          Thread.pass
        end
      end
    rescue StandardError
    end
  end.priority = -3
end

unless Yami.cfg("mode") == "optimize"
  Yami::OptMaps.load_manifest
  # Stream maps only once the game is up, so it never competes with boot I/O
  # (games on SD cards go through a slow FUSE layer).
  $yami_boot_frames = 0
  Yami.on_tick { $yami_boot_frames += 1 }
  Yami.once_when(-> { $yami_boot_frames >= 180 }) { Yami::MapCache.start }
end
# =============================================================================
#  Player features: instant text, cheats, minimap
# =============================================================================
# The player screen writes a small control file (key=value lines) whenever a
# quick-menu switch changes; read a few times a second with IO.read (outside
# the game's Windows file layer). The launch settings are the defaults.
module Yami
  module Features
    STATE = {
      "instant_text" => Yami.flag("instant_text"),
      "minimap" => Yami.flag("minimap"),
    }
    LOOK_KEYS = %w[look_scaling look_integer look_shader look_intensity].freeze
    @raw = nil
    @next = 0
    @look = nil

    module_function

    def on?(k); STATE[k] ? true : false; end

    # Shiny odds from the game settings: 1 in N for Pokémon created from now
    # on, or nil for the game's own.
    def shiny_odds
      n = Yami.cfg("shiny_odds", "0").to_i
      n >= 128 ? n : nil
    end

    def poll
      return if (@next -= 1) > 0
      @next = 10
      path = Yami.cfg("control_file")
      return unless path
      raw = (IO.read(path) rescue nil)
      return if raw.nil? || raw == @raw
      @raw = raw
      look = {}
      raw.each_line do |l|
        k, v = l.strip.split("=", 2)
        next unless k && v
        if STATE.key?(k)
          STATE[k] = v == "true"
        elsif LOOK_KEYS.include?(k)
          look[k] = v
        end
      end
      apply_look(look) unless look.empty?
    rescue StandardError => e
      Yami.log("features: #{e.class}: #{e.message}")
    end

    # The in-game menu's Look: scaling, pixel-perfect fit and shader, live.
    # The first values are the ones the game started with.
    def apply_look(look)
      if @look.nil?
        @look = look
        return
      end
      return if look == @look
      old = @look
      @look = look
      if look["look_scaling"] != old["look_scaling"] && Graphics.respond_to?(:smooth_scaling=)
        Graphics.smooth_scaling = look["look_scaling"].to_i
      end
      if look["look_integer"] != old["look_integer"] && Graphics.respond_to?(:integer_scaling=)
        Graphics.integer_scaling = look["look_integer"] == "true"
      end
      if (look["look_shader"] != old["look_shader"] || look["look_intensity"] != old["look_intensity"]) &&
         Graphics.respond_to?(:yami_post_shader)
        Graphics.yami_post_shader(look["look_shader"].to_s, (look["look_intensity"] || 1).to_f)
      end
      Yami.log("look: scaling #{look['look_scaling']}, pixel perfect #{look['look_integer']}, shader #{File.basename(look['look_shader'].to_s)}")
    end

    def tick
      poll
    end
  end

  # Shiny odds (game setting): decided once, when a Pokémon is created, so
  # Pokémon you already have stay as they are (Essentials up to v18 works
  # shininess out from the ID on every check). Wrapped once the scripts have
  # loaded (captured original, not prepend).
  module ShinyOdds
    module_function

    def install
      return if @done
      return unless defined?($scene) && $scene
      @done = true
      return unless Yami::Features.shiny_odds
      klass, var = if defined?(::PokeBattle_Pokemon) then [::PokeBattle_Pokemon, :@shinyflag]
                   elsif defined?(::Pokemon) && ::Pokemon.method_defined?(:shiny?) then [::Pokemon, :@shiny]
                   end
      return unless klass
      orig = klass.instance_method(:initialize)
      klass.send(:define_method, :initialize) do |*a, &b|
        r = orig.bind_call(self, *a, &b)
        odds = Yami::Features.shiny_odds
        instance_variable_set(var, true) if odds && rand(odds).zero?
        r
      end
      Yami.log("shiny odds: 1 in #{Yami::Features.shiny_odds} (#{klass})")
    end
  end

  # Dialogue at once: while a message is typing out, skip ahead each frame,
  # exactly as pressing the confirm button does (pauses inside a message and
  # the wait for the button still work). Essentials' message window.
  module InstantText
    module_function

    def install
      return true if @done
      return false unless defined?($scene) && $scene
      @done = true
      return true unless defined?(::Window_AdvancedTextPokemon)
      k = ::Window_AdvancedTextPokemon
      return true unless k.method_defined?(:skipAhead) && k.method_defined?(:busy?)
      orig = k.instance_method(:update)
      k.send(:define_method, :update) do |*a, &b|
        r = orig.bind_call(self, *a, &b)
        if Yami::Features.on?("instant_text") && busy? && !(respond_to?(:pausing?) && pausing?) &&
           !(respond_to?(:letterbyletter) && !letterbyletter)
          skipAhead rescue nil
        end
        r
      end
      Yami.log("instant text: Essentials message window")
      true
    end
  end

  # A small map of the current area in the top-right corner: walkable
  # ground, water, grass, the player.
  module Minimap
    RADIUS = 8              # tiles shown each way from the player: always 17 x 17
    MARGIN = 8
    CELLS_PER_FRAME = 600   # building work per frame, spread so it never stutters
    INK   = [16, 12, 24, 255].pack("C4")
    PAPER = Color.new(8, 8, 12, 215)
    module_function

    def screen_w
      Graphics.respond_to?(:yami_native_width) ? Graphics.yami_native_width : Graphics.width
    end

    def visible_now?
      return false unless Yami::Features.on?("minimap")
      return false unless defined?(::Scene_Map) && $scene.is_a?(::Scene_Map) && $game_map && $game_player
      if defined?(Yami::Wide::Layers) && Yami::Wide.panoramic?
        return Yami::Wide::Layers.map_shown_cached? rescue true
      end
      true
    end

    def sprites = [@frame, @sprite, @over]

    def tick
      unless visible_now?
        sprites.each { |s| s.visible = false if s && !s.disposed? }
        return
      end
      build_start if @map_id != $game_map.map_id || @data_id != $game_map.data.object_id
      build_step if @building
      show
    rescue StandardError => e
      Yami.log("minimap: #{e.class}: #{e.message}") unless @logged
      @logged = true
    end

    def viewport
      if @vp.nil? || @vp.disposed?
        @vp = Viewport.new(0, 0, screen_w, Graphics.respond_to?(:yami_native_height) ? Graphics.yami_native_height : Graphics.height)
        @vp.z = 90_000
        @vp.yami_unclipped = true if @vp.respond_to?(:yami_unclipped=)
        @vp.instance_variable_set(:@yami_overlay, true)
      end
      @vp
    end

    # The whole map is drawn once, 1:1, every tile a tiny copy of the real
    # one (6x6, or 4x4 on huge maps): the tiles the map uses are shrunk on
    # the GPU into one strip and read back once; each stack of layers is
    # composed once per distinct stack; walls are dimmed; ink lines trace
    # where you can and can't walk, with a soft shadow under walls.
    # The window then just slides over it, following the player.
    def build_start
      m = $game_map
      @map_id = m.map_id
      @data_id = m.data.object_id
      @w = m.width
      @h = m.height
      @t = @w * @h > 40_000 ? 4 : 6
      @pix = "\0".b * (@w * @t * @h * @t * 4)
      @walk = Array.new(@w * @h, true)
      @row = 0
      @ids = {}
      @tiles = {}
      @stacks = {}
      @phase = :scan
      @building = true
      @neutral = (defined?(::PBTerrain) && ::PBTerrain.const_defined?(:Neutral)) ? ::PBTerrain::Neutral : nil
    end

    def build_step
      case @phase
      when :scan then scan_rows
      when :sample then sample_tiles
      when :compose then compose_rows
      when :ink then ink_rows
      end
    end

    def rows_per_frame = [CELLS_PER_FRAME / [@w, 1].max, 1].max

    def scan_rows
      data = $game_map.data
      stop = [@row + rows_per_frame * 3, @h].min
      (@row...stop).each do |y|
        @w.times do |x|
          3.times do |z|
            id = data[x, y, z]
            @ids[id] = true if id && id >= 48 && !@ids.key?(id)
          end
        end
      end
      @row = stop
      return if @row < @h
      @row = 0
      @order = @ids.keys
      @phase = :sample
      @sampled = 0
    end

    def borrow(kind, name)
      return nil if name.nil? || name.empty?
      if defined?(::RPG::Cache) && ::RPG::Cache.respond_to?(kind)
        b = ::RPG::Cache.send(kind, name)
        @borrowed << b if b && b.respond_to?(:addRef)   # counted: give it back after
        return b
      end
      nil
    rescue StandardError
      nil
    end

    def sample_tiles
      if @sampled == 0
        @borrowed = []
        @strip.dispose if @strip && !@strip.disposed?
        @strip = Bitmap.new([@order.size * 4, 4].max, 4)
        @ts_bmp = borrow(:tileset, $game_map.tileset_name)
        @at_bmps = ($game_map.autotile_names || []).map { |n| borrow(:autotile, n) }
      end
      stop = [@sampled + 96, @order.size].min
      (@sampled...stop).each do |i|
        src, rect = tile_source(@order[i])
        next unless src && !src.disposed?
        @strip.stretch_blt(Rect.new(i * 4, 0, 4, 4), src, rect) rescue nil
      end
      @sampled = stop
      return if @sampled < @order.size
      raw = (@strip.raw_data rescue nil)
      if raw && raw.bytesize >= @order.size * 64
        w = @strip.width
        @order.each_with_index do |id, i|
          r = g = b = a = 0
          4.times do |yy|
            4.times do |xx|
              o = (yy * w + i * 4 + xx) * 4
              pa = raw.getbyte(o + 3)
              r += raw.getbyte(o) * pa; g += raw.getbyte(o + 1) * pa; b += raw.getbyte(o + 2) * pa; a += pa
            end
          end
          @tiles[id] = a > 0 ? [r / a, g / a, b / a, a / (16 * 255.0)] : nil
        end
      end
      @borrowed.each { |bm| bm.dispose rescue nil }
      @borrowed = []
      @strip.dispose
      @strip = nil
      @phase = :compose
      @row = 0
    end

    def tile_source(id)
      if id >= 384
        return [nil, nil] unless @ts_bmp
        t = id - 384
        [@ts_bmp, Rect.new((t % 8) * 32, (t / 8) * 32, 32, 32)]
      else
        b = @at_bmps[id / 48 - 1]
        return [nil, nil] unless b
        # the autotile's plain middle piece (small one-tile autotiles: itself)
        b.height <= 32 ? [b, Rect.new(0, 0, 32, 32)] : [b, Rect.new(32, 64, 32, 32)]
      end
    end

    WALK  = [96, 96, 112]
    WALL  = [40, 40, 52]
    WATER = [52, 96, 170]
    GRASS = [52, 112, 70]

    def kind(tag)
      return nil if tag.nil? || tag == 0
      if defined?(::GameData::TerrainTag)
        d = ::GameData::TerrainTag.try_get(tag)
        return :water if d && d.respond_to?(:can_surf) && d.can_surf
        return :grass if d && d.respond_to?(:land_wild_encounters) && d.land_wild_encounters
      elsif defined?(::PBTerrain)
        return :water if ::PBTerrain.respond_to?(:isSurfable?) && ::PBTerrain.isSurfable?(tag)
        return :grass if ::PBTerrain.respond_to?(:isGrass?) && ::PBTerrain.isGrass?(tag)
      end
      nil
    rescue StandardError
      nil
    end

    def shade(c, f) = [(c[0] * f).clamp(0, 255).to_i, (c[1] * f).clamp(0, 255).to_i, (c[2] * f).clamp(0, 255).to_i]
    def px(c) = [c[0], c[1], c[2], 255].pack("C4")

    # A cell as pixel art: one flat colour from the real tiles (snapped to
    # steps, so neighbouring areas merge into clean shapes) and a small
    # drawn mark for grass and water. Cached: there are few distinct cells.
    def cell(col, walk, look)
      @stacks[[col, walk, look]] ||= begin
        t = @t
        base = px(col)
        s = base * (t * t)
        put = ->(x, y, c) { s[(y * t + x) * 4, 4] = c if x < t && y < t }
        if look == :grass
          d = px(shade(col, 0.72))
          [[1, 2], [0, 3], [2, 3], [4, 4], [3, 5], [5, 5]].each { |x, y| put.(x * t / 6, y * t / 6, d) }
        elsif look == :water
          l = px(shade(col, 1.28))
          [[1, 1], [2, 1], [3, 4], [4, 4]].each { |x, y| put.(x * t / 6, y * t / 6, l) }
        end
        s
      end
    end

    def snap(v) = ((v.clamp(0, 255) + 12) / 24 * 24).clamp(0, 255).to_i

    def compose_rows
      m = $game_map
      data = m.data
      pas = m.passages
      pri = m.priorities
      tags = m.terrain_tags
      t = @t
      stride = @w * t * 4
      stop = [@row + rows_per_frame, @h].min
      (@row...stop).each do |y|
        @w.times do |x|
          walk = true
          look = nil
          cr = cg = cb = ca = 0.0
          2.downto(0) do |z|                     # colour: every layer, top down, like the game draws them
            id = data[x, y, z]
            next if id.nil? || id == 0
            c = @tiles[id] or next
            next if ca >= 0.97
            k = (1.0 - ca) * c[3]
            cr += k * c[0]; cg += k * c[1]; cb += k * c[2]; ca += k
          end
          2.downto(0) do |z|                     # walking: the game's own rule
            id = data[x, y, z]
            next if id.nil? || id == 0
            tg = tags ? tags[id] : 0
            next if @neutral && tg == @neutral
            look ||= kind(tg)
            if (pas[id] & 0x0f) == 0x0f
              walk = false
              break
            end
            break if pri[id] == 0
          end
          @walk[y * @w + x] = walk
          col = if ca > 0.05
                  r, g, b = cr / ca, cg / ca, cb / ca
                  l = (r + g + b) / 3.0                          # a little more colour
                  r = l + (r - l) * 1.3; g = l + (g - l) * 1.3; b = l + (b - l) * 1.3
                  f = walk ? 1.12 : 0.62                         # paths forward, walls back
                  [snap(r * f), snap(g * f), snap(b * f)]
                else
                  !walk ? (look == :water ? WATER : WALL) : (look == :water ? WATER : look == :grass ? GRASS : WALK)
                end
          blk = cell(col, walk, look)
          o = (y * t) * stride + x * t * 4
          t.times { |yy| @pix[o + yy * stride, t * 4] = blk.byteslice(yy * t * 4, t * 4) }
        end
      end
      @row = stop
      return if @row < @h
      @row = 0
      @phase = :ink
    end

    # Ink where walkable meets blocked; a soft shadow under the wall above.
    def ink_rows
      t = @t
      stride = @w * t * 4
      stop = [@row + rows_per_frame, @h].min
      (@row...stop).each do |y|
        @w.times do |x|
          o = (y * t) * stride + x * t * 4
          unless @walk[y * @w + x]
            if y > 0 && @walk[(y - 1) * @w + x]               # light catching the top of a wall
              t.times do |i|
                q = o + i * 4
                r, g, b, a = @pix.byteslice(q, 4).unpack("C4")
                @pix[q, 4] = [[r + 40, 255].min, [g + 40, 255].min, [b + 40, 255].min, a].pack("C4")
              end
            end
            next
          end
          up = y > 0 && !@walk[(y - 1) * @w + x]
          if up
            t.times { |i| @pix[o + i * 4, 4] = INK }
            t.times do |i|                               # second row: shadow
              q = o + stride + i * 4
              r, g, b, a = @pix.byteslice(q, 4).unpack("C4")
              @pix[q, 4] = [r * 3 / 5, g * 3 / 5, b * 3 / 5, a].pack("C4")
            end
          end
          t.times { |i| @pix[o + (t - 1) * stride + i * 4, 4] = INK } if y + 1 < @h && !@walk[(y + 1) * @w + x]
          t.times { |i| @pix[o + i * stride, 4] = INK } if x > 0 && !@walk[y * @w + x - 1]
          t.times { |i| @pix[o + i * stride + (t - 1) * 4, 4] = INK } if x + 1 < @w && !@walk[y * @w + x + 1]
        end
      end
      @row = stop
      finish if @row >= @h
    end

    def finish
      @building = false
      @phase = nil
      @stacks = {}
      @tiles = {}
      @bmp.dispose if @bmp && !@bmp.disposed?
      bw = @w * @t
      bh = @h * @t
      @bmp = Bitmap.new(bw, bh)
      if @bmp.respond_to?(:raw_data=)
        @bmp.raw_data = @pix
      else
        bh.times do |y|                              # runs of one colour per call
          x = 0
          while x < bw
            c = @pix[(y * bw + x) * 4, 4]
            x2 = x
            x2 += 1 while x2 + 1 < bw && @pix[(y * bw + x2 + 1) * 4, 4] == c
            r, g, b, al = c.unpack("C4")
            @bmp.fill_rect(x, y, x2 - x + 1, 1, Color.new(r, g, b, al))
            x = x2 + 1
          end
        end
      end
      @pix = nil
      make_sprites
      @sprite.bitmap = @bmp
    end

    def view = (2 * RADIUS + 1) * @t

    def make_sprites
      v = view
      if @frame.nil? || @frame.disposed? || @frame.bitmap.width != v + 4
        sprites.each { |s| s.dispose if s && !s.disposed? }
        @frame = Sprite.new(viewport)
        fb = Bitmap.new(v + 4, v + 4)
        fb.fill_rect(0, 0, v + 4, v + 4, Color.new(0, 0, 0, 170))           # ink border
        fb.fill_rect(1, 1, v + 2, v + 2, Color.new(255, 255, 255, 60))      # glass edge
        fb.fill_rect(2, 2, v, v, PAPER)
        [[0, 0], [v + 3, 0], [0, v + 3], [v + 3, v + 3]].each { |cx, cy| fb.fill_rect(cx, cy, 1, 1, Color.new(0, 0, 0, 0)) }
        @frame.bitmap = fb
        @frame.z = 0
        @sprite = Sprite.new(viewport)
        @sprite.z = 1
        @over = Sprite.new(viewport)
        @over.bitmap = Bitmap.new(v, v)
        @over.z = 2
      end
    end

    def tile_pos(ch)
      if ch.respond_to?(:real_x) && ch.real_x
        [ch.real_x / 128.0, ch.real_y / 128.0]
      else
        [ch.x.to_f, ch.y.to_f]
      end
    end

    def show
      return unless @sprite && !@sprite.disposed? && @sprite.bitmap
      t = @t
      v = view
      fx = screen_w - v - 4 - MARGIN
      fy = MARGIN
      @frame.x = fx; @frame.y = fy; @frame.visible = true
      px, py = tile_pos($game_player)
      left = ((px + 0.5) * t - v / 2.0).round
      top = ((py + 0.5) * t - v / 2.0).round
      sx = [left, 0].max; sy = [top, 0].max
      ex = [left + v, @w * t].min; ey = [top + v, @h * t].min
      if ex > sx && ey > sy
        @sprite.src_rect = Rect.new(sx, sy, ex - sx, ey - sy)
        @sprite.x = fx + 2 + (sx - left)
        @sprite.y = fy + 2 + (sy - top)
        @sprite.visible = true
      else
        @sprite.visible = false
      end
      draw_marks(px, py) if (Yami.frame_no % 3) == 0 || !@over.visible
      @over.x = fx + 2; @over.y = fy + 2; @over.visible = true
    end

    # NPCs as warm dots, the player as an arrow pointing where they face.
    def draw_marks(px, py)
      b = @over.bitmap
      b.clear
      t = @t
      v = view
      half = v / 2.0
      evs = ($game_map.events rescue nil) || {}
      dot = Color.new(255, 214, 120)
      evs.each_value do |ev|
        next if (ev.character_name.to_s.empty? rescue true)
        next if ev.instance_variable_get(:@erased)
        ex, ey = tile_pos(ev)
        cx = (half + (ex - px) * t).round
        cy = (half + (ey - py) * t).round
        next if cx < 1 || cy < 1 || cx > v - 2 || cy > v - 2
        b.fill_rect(cx - 1, cy - 1, 3, 3, Color.new(0, 0, 0, 200))
        b.fill_rect(cx, cy, 1, 1, dot)
        b.fill_rect(cx - 1, cy, 3, 1, dot); b.fill_rect(cx, cy - 1, 1, 3, dot)
      end
      blink = (Yami.frame_no / 20) % 2 == 0
      arrow(b, half.floor, half.floor, ($game_player.direction rescue 2), Color.new(255, 255, 255, blink ? 255 : 200))
    end

    # a 5-wide, 3-tall arrowhead, outlined in ink
    def arrow(b, cx, cy, dir, col)
      ink = Color.new(0, 0, 0, 220)
      [[-1, 0], [1, 0], [0, -1], [0, 1]].each { |dx, dy| arrow_shape(b, cx + dx, cy + dy, dir, ink) }
      arrow_shape(b, cx, cy, dir, col)
    end

    def arrow_shape(b, cx, cy, dir, c)
      3.times do |i|                       # i = 0 at the tip
        w = 1 + 2 * i
        case dir
        when 8 then b.fill_rect(cx - i, cy - 1 + i, w, 1, c)
        when 4 then b.fill_rect(cx - 1 + i, cy - i, 1, w, c)
        when 6 then b.fill_rect(cx + 1 - i, cy - i, 1, w, c)
        else        b.fill_rect(cx - i, cy + 1 - i, w, 1, c)
        end
      end
    end
  end

end

Yami.on_tick { Yami::Features.tick }
Yami.on_tick { Yami::ShinyOdds.install }
Yami.on_tick { Yami::InstantText.install }
Yami.on_tick { Yami::Minimap.tick }

Yami.status("turbo", 0)
Yami.log("runtime #{Yami::VERSION} ready (rgss #{Yami.rgss}, widescreen=#{Yami::Wide.mode})")
