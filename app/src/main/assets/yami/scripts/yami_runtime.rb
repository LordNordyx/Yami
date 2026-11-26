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

  # Live state (works even when the game replaces Input.update, as older
  # Essentials does); falls back to raw_key_states.
  def key_down?(scancode)
    live = (Input.yami_live_key_states rescue nil)
    return live.getbyte(scancode).to_i != 0 if live.is_a?(String)
    states = Input.raw_key_states
    states && states[scancode] ? true : false
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

    # The game's own resolution, before any border.
    def base
      @base ||= [const_or(:DEFAULTSCREENWIDTH, 640), const_or(:DEFAULTSCREENHEIGHT, 480)]
    end

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
      %i[BORDERWIDTH BORDERHEIGHT].each { |c| set_const(c, 0) }
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
          Graphics.define_singleton_method(:snap_to_bitmap) { |*a| yami_native_snap(*a) }
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
      return false unless Object.const_defined?(:DEFAULTSCREENWIDTH)
      Object.const_defined?(:BORDERWIDTH) || resizer? || !$ResizeOffsetX.nil?
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
      %i[BORDERWIDTH BORDERHEIGHT].each do |c|
        set_const(c, 0) if Object.const_defined?(c) && Object.const_get(c) != 0
      end
      if defined?(PokemonSystem) && PokemonSystem.method_defined?(:border) &&
         PokemonSystem.instance_method(:border).source_location.to_a[0].to_s !~ /yami_/
        PokemonSystem.class_eval { def border; 0; end }
      end
      ($ResizeBorder.visible = false) if $ResizeBorder.respond_to?(:visible=) && $ResizeBorder.visible rescue nil
      if Graphics.respond_to?(:yami_native_snap)
        loc = (Graphics.method(:snap_to_bitmap).source_location rescue nil)
        if loc && loc[0].to_s !~ /yami_/
          Graphics.define_singleton_method(:snap_to_bitmap) { |*a| yami_native_snap(*a) }
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
    end
  end
end

# Every screen-size request ends here — including the game's own alias of
# resize_screen (Sprite_Resizer's "oldresizescreen"), taken after this runs.
class << Graphics
  def resize_screen(w, h)
    w = w.to_i; h = h.to_i # older Essentials passes floats (size * factor)
    if Yami::OldEss.border_game?
      Yami::OldEss.neutralize!
      w, h = Yami::OldEss.base # never the bordered/scaled size
    end
    if defined?(Yami::Wide) && Yami::Wide.on?
      Yami::Wide.base = [w, h]
      w, h = Yami::Wide.target(w, h)
    end
    yami_native_resize(w, h)
  end
end

# Essentials draws frames while its scripts are still loading, so keep checking.
Yami.on_tick { Yami::OldEss.tick }

# =============================================================================
#  Widescreen
# =============================================================================
module Yami
  module Wide
    @mode = Yami.cfg("widescreen", "off")
    @ratio = Yami.num("ratio", 0.0)
    @base = nil
    @ctx = 0

    class << self
      attr_accessor :ctx, :base
      def mode; @mode; end
      def on?; @mode != "off" && @ratio > 1.0; end
      def panoramic?; on? && @mode == "panoramic"; end

      def target(w, h)
        return [w, h] unless on?
        nw = ((h * @ratio) / 4.0).round * 4
        nw > w ? [nw, h] : [w, h]
      end

      def real_w; Graphics.yami_width; end
      def base_w; (@base || [real_w])[0]; end
      def margin; panoramic? ? (real_w - base_w) / 2 : 0; end
      def map_ctx?; @ctx > 0; end

      # Older Essentials keeps the size in DEFAULTSCREENWIDTH and may redefine
      # Graphics.width/height in Ruby — possibly after this runtime started.
      # Report the real size to it (full mode). Cheap; runs every frame.
      def claim!
        return if !on? || panoramic?
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
      Yami::Wide.map_ctx? ? yami_width : Yami::Wide.base_w
    end
  end

  # Widen the default resolution right away (RMXP games never call resize_screen).
  Graphics.resize_screen(Graphics.yami_width, Graphics.height)
  Yami.on_tick { Yami::Wide.claim! }

  # --- full-screen viewports ----------------------------------------------------
  class Viewport
    alias_method :yami_vp_init, :initialize
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
      bw, bh = Yami::Wide.base
      rw = Graphics.yami_width
      x, y, w, h = a
      if Yami::Wide.panoramic? && !Yami::Wide.map_ctx?
        x += Yami::Wide.margin
      elsif x == 0 && w == bw && h == bh
        w = rw # map layers and full-screen effects span the whole display
      end
      yami_vp_init(x, y, w, h)
    end
  end

  # --- panoramic: offset UI drawn without a viewport -----------------------------
  if Yami::Wide.panoramic?
    module Yami::UIOffset
      def initialize(*a)
        super
        @yami_ui = !a[0].is_a?(Viewport) && !Yami::Wide.map_ctx? && viewport.nil?
        # VX/Ace style Window.new(x, y, w, h) already placed it; re-apply offset
        self.x = (a[0].is_a?(Integer) ? a[0] : 0) if @yami_ui
      end
      def x; @yami_ui ? (@yami_lx || 0) : super; end
      def x=(v)
        return super unless @yami_ui
        @yami_lx = v
        super(v + Yami::Wide.margin)
      end
      def viewport=(v)
        lx = x
        super
        @yami_ui = v.nil?
        self.x = lx
      end
    end
    [Sprite, Window].each { |k| k.prepend(Yami::UIOffset) unless k.ancestors.include?(Yami::UIOffset) }
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
          @display_x = [@display_x + distance, [(width * 128) - (Graphics.width * 4), 0].max].min
        end
        def scroll_down(distance)
          @display_y = [@display_y + distance, [(height * 128) - (Graphics.height * 4), 0].max].min
        end
      end
      Game_Player.class_eval do
        def center(x, y)
          max_x = [($game_map.width * 128) - (Graphics.width * 4), 0].max
          max_y = [($game_map.height * 128) - (Graphics.height * 4), 0].max
          $game_map.display_x = [0, [x * 128 - Game_Player::CENTER_X, max_x].min].max
          $game_map.display_y = [0, [y * 128 - Game_Player::CENTER_Y, max_y].min].max
        end
      end
    end

    # Panoramic: everything map-related runs in "map context" and sees the full width.
    if Yami::Wide.panoramic?
      names = %w[Spriteset_Map Game_Map Game_Player Game_Character Game_Event Game_Follower
                 TilemapRenderer CustomTilemap SynchronizedTilemapAutotiles Spriteset_Global]
      names.each do |n|
        next unless Object.const_defined?(n)
        klass = Object.const_get(n)
        wrap = lambda do |target, publics, privates|
          mod = Module.new
          (publics + privates).uniq.each do |m|
            next if m == :initialize_copy
            mod.send(:define_method, m) do |*a, &b|
              Yami::Wide.ctx += 1
              begin
                super(*a, &b)
              ensure
                Yami::Wide.ctx -= 1
              end
            end
            mod.send(:ruby2_keywords, m) if mod.respond_to?(:ruby2_keywords, true)
          end
          privates.each { |m| mod.send(:private, m) }
          target.prepend(mod)
        end
        wrap.call(klass, klass.public_instance_methods(false) + klass.protected_instance_methods(false),
                  klass.private_instance_methods(false))
        wrap.call(klass.singleton_class, klass.singleton_class.public_instance_methods(false), [])
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
