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
    File.open(f, "w") { |io| @status.each { |k, v| io.puts("#{k}=#{v}") } }
  rescue StandardError
  end

  # --------------------------------------------------------------- frame hooks
  @tick_hooks = []
  @once_hooks = []

  def on_tick(&b); @tick_hooks << b; end
  def once_pending; @once_hooks.size; end
  def once_when(cond, &b); @once_hooks << [cond, b]; end

  def tick
    @key_snap = nil # new frame: read the keyboard afresh
    @tick_hooks.each { |h| h.call rescue log("tick hook: #{$!}") }
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

class << Graphics
  alias_method :yami_update, :update
  def update(*args)
    Yami.tick
    yami_update(*args)
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
  def frame_rate=(v)
    if Yami::Turbo.active
      Yami::Turbo.base_rate = v
      return yami_set_frame_rate(v * (Yami.num("turbo_speed", 3).to_i.clamp(2, 10)))
    end
    yami_set_frame_rate(v)
  end

  def yami_disable_turbo!; Yami::Turbo.disable!; end
  def kirin_disable_turbo!; Yami::Turbo.disable!; end
end

Yami.on_tick { Yami::Turbo.poll }

# Real engine FPS for the Android info overlay, about once per second.
module Yami
  @fps_frames = 0
  @fps_t = nil
  def self.fps_tick
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @fps_t ||= now
    @fps_frames += 1
    return if now - @fps_t < 1.0
    status("fps", (@fps_frames / (now - @fps_t)).round)
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

  module TableEdits
    def []=(*a)
      r = super
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
      rows = {}
      max_row = ts.height / 32
      zs.times do |z| ys.times do |y| xs.times do |x|
        id = md[x, y, z]
        next if id.nil? || id < 384
        r = (id - 384) >> 3
        rows[r] = rows.size if r < max_row && !rows.key?(r)
      end end end
      cts = Bitmap.new(256, [rows.size, 1].max * 32)
      rows.each { |old, nw| cts.blt(0, nw * 32, ts, Rect.new(0, old * 32, 256, 32)) }
      @yami_rows = rows
      cmd = Table.new(xs, ys, zs)
      zs.times do |z| ys.times do |y| xs.times do |x|
        id = md[x, y, z] || 0
        cmd[x, y, z] = (id >= 384 && !rows.key?((id - 384) >> 3)) ? 0 : yami_map_id(id)
      end end end
      @yami_cts, @yami_cmd, @yami_key = cts, cmd, [ts.object_id, md.object_id]
      @yami_md_dims = zs > 1 ? 4 : (ys > 1 ? 3 : 2)
      @yami_cpr_src = nil
      Yami.log("map renderer: compact tileset #{rows.size} rows (#{rows.size * 32}px of #{ts.height}px)")
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
    ::Table.prepend(TableEdits) unless ::Table < TableEdits
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
  Yami.on_tick { @yami_ntm_done ||= (defined?(Yami::NativeTilemap) && Yami::NativeTilemap.install) }
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

      def map_caller?
        return true if (@render_depth || 0) > 0
        nearest = true
        caller_locations(2, 40).each do |loc|
          k = section_kind(loc.path)
          next if k == :infra
          return true if k == :render || (nearest && k == :map)
          nearest = false
        end
        false
      rescue StandardError => e
        # Graphics.width must never take a game down: treat as UI
        Yami.log("map_caller?: #{e.class}: #{e.message}") unless @mc_logged
        @mc_logged = true
        false
      end

      # Is this the message system, while the map is showing? (window
      # libraries are transparent; anything else stops the search)
      def dialog_caller?
        return false unless Yami::Wide::Layers.map_shown_cached?
        caller_locations(2, 40).each do |loc|
          k = section_kind(loc.path)
          next if k == :infra || k == :lib
          return k == :dialog
        end
        false
      rescue StandardError
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
    AMBIENT_DIM = 45 # percent
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
          @ui_full << [vp, []] unless @ui_full.any? { |v, _| v.equal?(vp) }
        end
      end

      def forget_map(vp); @map_vps.reject! { |v| v.equal?(vp) }; end

      # children of full-screen UI viewports (background detection)
      def adopt(child, vp)
        return unless vp
        e = @ui_full.find { |v, _| v.equal?(vp) }
        e[1] << child if e && !e[1].any? { |c| c.equal?(child) }
      end

      def alive?(o); !(o.disposed? rescue true); end

      # an opaque picture covering (most of) the box: a full-screen scene
      def covering?(vp, kids)
        bw, bh = Yami::Wide.base
        kids.reject! { |c| !alive?(c) }
        kids.any? do |c|
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
        binit.bind(self).call(*a, &b)
        @yami_file = true if a.size == 1 && a[0].is_a?(String)
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
Yami.status("turbo", 0)
Yami.log("runtime #{Yami::VERSION} ready (rgss #{Yami.rgss}, widescreen=#{Yami::Wide.mode})")
