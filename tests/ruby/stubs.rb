# Minimal stand-ins for mkxp-z native classes.
class Table
  attr_reader :xsize, :ysize, :zsize
  def initialize(x, y = 1, z = 1); @xsize, @ysize, @zsize = x, y, z; @d = Array.new(x * y * z, 0); end
  def [](x, y = 0, z = 0); return nil if x >= @xsize || y >= @ysize || z >= @zsize; @d[x + y * @xsize + z * @xsize * @ysize]; end
  def []=(*a); v = a.pop; x, y, z = a; y ||= 0; z ||= 0; @d[x + y * @xsize + z * @xsize * @ysize] = v; end
  def _dump(_l); [3, @xsize, @ysize, @zsize, @d.size].pack("V5") + @d.pack("v*"); end
  def self._load(s); dim, x, y, z, n = s.unpack("V5"); t = new(x, y, z); t.instance_variable_set(:@d, s[20, n * 2].unpack("v*")); t; end
end
class Color; def initialize(*a); end; end
class Rect; attr_accessor :x, :y, :width, :height; def initialize(x, y, w, h); @x, @y, @width, @height = x, y, w, h; end; end
class Font; attr_accessor :size; end
class Bitmap
  DIMS = {}
  attr_reader :width, :height, :blts, :font
  def self.max_size; 16384; end
  def initialize(a, b = nil)
    if b then @width, @height = a, b
    else @width, @height = DIMS.fetch(File.basename(a, ".*")) { raise "no image #{a}" } end
    @blts = []; @font = Font.new
  end
  def blt(x, y, src, r); @blts << [x, y, r.x, r.y]; end
  def to_file(path); File.write(path, Marshal.dump([@width, @height, @blts])); end
  def clear; end; def fill_rect(*); end; def draw_text(*); end; def dispose; end
end
class Viewport; attr_reader :rect; def initialize(*a); @rect = a; end; def rect=(r); @rect = [r.x, r.y, r.width, r.height]; end; end
class Sprite
  attr_accessor :bitmap, :z, :viewport; attr_writer :x
  def initialize(vp = nil); @viewport = vp; @x = 0; end
  def x; @x; end
end
class Window < Sprite; end
class Plane < Sprite; end
module Graphics
  @w, @h, @rate, @skip, @updates = 640, 480, 40, false, 0
  class << self
    attr_accessor :frame_rate, :frameskip
    attr_reader :updates
    def width; @w; end; def height; @h; end
    def resize_screen(w, h); @w, @h = w, h; end
    def update; @updates += 1; end
    def snap_to_bitmap; :native_snap; end
  end
  self.frame_rate = 40
end
module Input
  # Like the engine: raw_key_states is a snapshot refreshed only by the native
  # Input.update; yami_live_key_states is the live event-thread state.
  @keys = Array.new(512, false)
  @snapshot = Array.new(512, false)
  class << self
    attr_reader :keys
    def update; @snapshot = @keys.dup; end
    def raw_key_states; @snapshot.dup; end
    def yami_live_key_states; @keys.map { |k| k ? 1 : 0 }.pack("C*"); end
  end
end
module Audio; end
def load_data(p, raw = false); d = File.binread(p); raw ? d : Marshal.load(d); end
def save_data(o, p); File.binwrite(p, Marshal.dump(o)); end

# In RGSS, print/p open a message box that blocks the game. Count calls so the
# tests fail if the runtime ever uses them.
$msgboxes = 0
def print(*a); $msgboxes += 1; end
def p(*a); $msgboxes += 1; a.first; end
