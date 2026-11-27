# Stand-ins for mkxp-z's native classes, faithful enough to run real
# Pokémon Essentials v17 scripts (Sprite_Resizer aliases and overrides most
# of these). "Native" state is what the engine would actually draw.
class RGSSError < StandardError; end
class Hangup < Exception; end

class Rect
  attr_accessor :x, :y, :width, :height
  def initialize(x = 0, y = 0, w = 0, h = 0); set(x, y, w, h); end
  def set(x, y, w, h); @x, @y, @width, @height = x, y, w, h; self; end
  def to_a; [@x, @y, @width, @height]; end
end

class Color
  attr_accessor :red, :green, :blue, :alpha
  def initialize(r = 0, g = 0, b = 0, a = 255); set(r, g, b, a); end
  def set(r, g, b, a = 255); @red, @green, @blue, @alpha = r, g, b, a; self; end
end

class Tone; def initialize(*); end; end

class Table
  attr_reader :xsize, :ysize, :zsize
  def initialize(x, y = 1, z = 1); @xsize, @ysize, @zsize = x, y, z; @d = Array.new(x * y * z, 0); end
  def [](x, y = 0, z = 0); @d[x + y * @xsize + z * @xsize * @ysize]; end
  def []=(*a); v = a.pop; x, y, z = a; @d[x + (y || 0) * @xsize + (z || 0) * @xsize * @ysize] = v; end
end

class Font
  attr_accessor :size, :name, :color, :bold, :italic, :shadow, :outline, :out_color
  class << self
    attr_accessor :default_name, :default_size, :default_bold, :default_italic, :default_color,
                  :default_shadow, :default_outline, :default_out_color
    def exist?(_n); true; end
  end
  def initialize(n = nil, s = 24); @name = n; @size = s; @color = Color.new(255, 255, 255); end
end

class Bitmap
  attr_reader :width, :height, :font
  def initialize(a, b = nil)
    if b then @width, @height = a.to_i, b.to_i
    else @width, @height = 640, 480 end
    @font = Font.new
  end
  def rect; Rect.new(0, 0, @width, @height); end
  def text_size(t); Rect.new(0, 0, t.to_s.size * 12, @font.size || 24); end
  def font=(f); @font = f; end
  def hue_change(*); end; def blur; end; def set_pixel(*); end; def clone; Bitmap.new(@width, @height); end
  def get_pixel(*); Color.new(0, 0, 0, 255); end
  def fill_rect(*); end; def clear; end; def blt(*); end; def stretch_blt(*); end
  def draw_text(*); end; def dispose; @disposed = true; end; def disposed?; !!@disposed; end
  def address; 0; end
end

class Viewport
  attr_accessor :z, :visible, :color, :tone
  def initialize(*a)
    r = a.size == 1 ? a[0] : Rect.new(*a)
    @nrect = Rect.new(r.x, r.y, r.width, r.height)
    @nox = @noy = 0
    @color = Color.new(0, 0, 0, 0); @z = 0; @visible = true
  end
  def rect; @nrect; end
  def rect=(r); @nrect = Rect.new(r.x, r.y, r.width, r.height); end
  def ox; @nox; end; def oy; @noy; end
  def ox=(v); @nox = v; end; def oy=(v); @noy = v; end
  def dispose; @disposed = true; end; def disposed?; !!@disposed; end
  def update; end; def flash(*); end
  def native_rect; @nrect.to_a; end
end

class Sprite
  attr_accessor :bitmap, :z, :visible, :opacity, :viewport, :src_rect, :angle, :mirror, :color, :tone, :blend_type
  def initialize(vp = nil)
    @viewport = vp; @nx = @ny = @nox = @noy = 0; @nzx = @nzy = 1.0; @visible = true; @z = 0
    @src_rect = Rect.new
  end
  def x; @nx; end; def y; @ny; end; def ox; @nox; end; def oy; @noy; end
  def zoom_x; @nzx; end; def zoom_y; @nzy; end
  def x=(v); @nx = v; end; def y=(v); @ny = v; end
  def ox=(v); @nox = v; end; def oy=(v); @noy = v; end
  def zoom_x=(v); @nzx = v; end; def zoom_y=(v); @nzy = v; end
  def bush_depth; @nbd || 0; end; def bush_depth=(v); @nbd = v; end
  def dispose; @disposed = true; end; def disposed?; !!@disposed; end
  def update; end; def flash(*); end
  def native_pos; [@nx, @ny]; end
end

class Plane
  attr_accessor :bitmap, :z, :visible, :opacity, :viewport
  def initialize(vp = nil); @viewport = vp; @nox = @noy = 0; @nzx = @nzy = 1.0; end
  def ox; @nox; end; def oy; @noy; end; def zoom_x; @nzx; end; def zoom_y; @nzy; end
  def ox=(v); @nox = v; end; def oy=(v); @noy = v; end
  def zoom_x=(v); @nzx = v; end; def zoom_y=(v); @nzy = v; end
  def dispose; @disposed = true; end; def disposed?; !!@disposed; end
end

class Tilemap
  attr_accessor :tileset, :map_data, :flash_data, :priorities, :visible, :ox, :oy, :viewport
  def initialize(vp = nil); @viewport = vp; @autotiles = []; end
  def autotiles; @autotiles; end
  def update; end; def dispose; end; def disposed?; false; end
end

class Window
  attr_accessor :x, :y, :width, :height, :z, :viewport, :visible, :windowskin, :contents
  def initialize(vp = nil); @viewport = vp; @x = @y = 0; end
  def dispose; end; def disposed?; false; end
end

module Graphics
  @w, @h, @updates = 640, 480, 0
  @resizes = []
  class << self
    attr_accessor :frame_rate, :frame_count
    attr_reader :updates, :resizes
    def width; @w; end
    def height; @h; end
    def resize_screen(w, h)
      raise TypeError, "Integer expected" unless w.is_a?(Integer) && h.is_a?(Integer)
      @resizes << [w, h]; @w, @h = w, h
    end
    def update; @updates += 1; end
    def freeze; end; def transition(*); end; def frame_reset; end
    def snap_to_bitmap; :native_snap; end
    def brightness; 255; end; def brightness=(v); end
  end
  self.frame_rate = 40
end

module Input
  @keys = Array.new(512, false)
  class << self
    def update; end
    def raw_key_states; @keys.dup; end
    def yami_live_key_states; @keys.map { |k| k ? 1 : 0 }.pack("C*"); end
    def trigger?(*); false; end; def press?(*); false; end; def repeat?(*); false; end
  end
end

module Audio
  %i[bgm bgs me se].each do |k|
    define_singleton_method(:"#{k}_play") { |*| nil }
    define_singleton_method(:"#{k}_stop") { |*| nil }
    define_singleton_method(:"#{k}_fade") { |*| nil }
  end
end
module RPG; module Cache; def self.load_bitmap(*); Bitmap.new(640, 480); end; end; end

def load_data(p, raw = false); d = File.binread(p); raw ? d : Marshal.load(d); end
def save_data(o, p); File.binwrite(p, Marshal.dump(o)); end

$msgboxes = 0
def print(*a); $msgboxes += 1; end
def p(*a); $msgboxes += 1; a.first; end
