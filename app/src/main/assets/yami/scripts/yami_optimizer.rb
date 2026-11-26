# =============================================================================
#  Yami map optimizer — runs inside the engine in "optimize" mode, then exits.
#
#  For every RMXP map whose tileset is oversized (taller than the threshold),
#  build a compact tileset containing only the tiles that map (and its events)
#  actually use. Maps with an identical used-tile set share one variant.
#
#  Output (originals are never modified):
#    Graphics/Tilesets/_yami/<tileset>_<n>.png   compact atlases, 8 tiles wide
#    .yami/opt/Data/MapXXX.rxdata                maps with remapped tile ids
#    .yami/opt/variants.rxdata                   [[id, RPG::Tileset], ...]
#    .yami/opt/maps.txt                          signatures for invalidation
#    .yami/opt/result.txt                        summary for the frontend
#
#  Passages, priorities and terrain tags are remapped with the tiles, and the
#  variant tilesets get new ids appended after the original list, so the game's
#  own tileset entries stay untouched.
# =============================================================================

module YamiOptimizer
  THRESHOLD = 4096
  OUT_DIR = File.join(Dir.pwd, ".yami/opt")
  ATLAS_SUB = "_yami"

  module_function

  def sig(path)
    st = File.stat(path)
    "#{st.size}:#{st.mtime.to_i}"
  end

  def find_ci(dir, name)
    return File.join(dir, name) if File.exist?(File.join(dir, name))
    Dir.glob(File.join(dir, "*")).find { |f| File.basename(f).downcase == name.downcase }
  end

  def tileset_image(name)
    dir = File.join(Dir.pwd, "Graphics", "Tilesets")
    %w[.png .PNG .jpg .bmp].each { |ext| f = find_ci(dir, name + ext); return f if f }
    nil
  end

  # ---------------------------------------------------------------- progress UI
  def ui_init
    @sprite = Sprite.new
    @sprite.bitmap = Bitmap.new(Graphics.width, Graphics.height)
    @sprite.z = 9999
  rescue StandardError
    @sprite = nil
  end

  def ui(text, frac)
    STDERR.write(format("[yami-opt %3d%%] %s\n", (frac * 100).round, text)) rescue nil # print = msgbox in RGSS
    return unless @sprite
    b = @sprite.bitmap
    b.clear
    w = b.width
    h = b.height
    b.fill_rect(0, 0, w, h, Color.new(10, 10, 12))
    b.font.size = 22
    b.draw_text(0, h / 2 - 48, w, 28, "Optimizing maps", 1)
    b.font.size = 16
    b.draw_text(0, h / 2 + 18, w, 22, text, 1)
    bw = (w * 0.6).to_i
    bx = (w - bw) / 2
    b.fill_rect(bx, h / 2 - 6, bw, 8, Color.new(40, 40, 48))
    b.fill_rect(bx, h / 2 - 6, (bw * frac.clamp(0.0, 1.0)).to_i, 8, Color.new(124, 92, 255))
    Graphics.update
  rescue StandardError
  end

  def write_atomic(path, data)
    tmp = path + ".tmp"
    File.open(tmp, "wb") { |f| f.write(data) }
    File.rename(tmp, path)
  end

  def remap_table(src, used, base = 384)
    t = Table.new(base + used.size)
    base.times { |i| t[i] = src[i] if i < src.xsize }
    used.each_with_index { |id, c| t[base + c] = id < src.xsize ? src[id] : 0 }
    t
  end

  # Collect tile ids >= 384 from all layers and from event tile graphics.
  def used_tiles(map)
    used = {}
    d = map.data
    xs = d.xsize
    ys = d.ysize
    zs = d.zsize
    z = 0
    while z < zs
      y = 0
      while y < ys
        x = 0
        while x < xs
          id = d[x, y, z]
          used[id] = true if id && id >= 384
          x += 1
        end
        y += 1
      end
      z += 1
    end
    (map.events || {}).each_value do |ev|
      ev.pages.each do |pg|
        id = pg.graphic.tile_id
        used[id] = true if id && id >= 384
      end
    end
    used.keys.sort
  end

  def remap_map!(map, index, new_tileset_id)
    d = map.data
    xs = d.xsize
    ys = d.ysize
    zs = d.zsize
    z = 0
    while z < zs
      y = 0
      while y < ys
        x = 0
        while x < xs
          id = d[x, y, z]
          d[x, y, z] = 384 + index[id] if id && id >= 384
          x += 1
        end
        y += 1
      end
      z += 1
    end
    (map.events || {}).each_value do |ev|
      ev.pages.each do |pg|
        id = pg.graphic.tile_id
        pg.graphic.tile_id = 384 + index[id] if id && id >= 384
      end
    end
    map.tileset_id = new_tileset_id
    map
  end

  def run
    result = { "tilesets" => 0, "variants" => 0, "saved_pixels" => 0, "maps" => 0, "note" => "" }
    rgss = (defined?(RGSS_VERSION) ? RGSS_VERSION.to_i : 1)
    data_dir = File.join(Dir.pwd, "Data")
    ts_file = find_ci(data_dir, "Tilesets.rxdata")
    unless ts_file
      result["note"] = rgss > 1 ? "VX/VX Ace maps use a different tileset model; skipped" : "No Data/Tilesets.rxdata"
      return result
    end

    ui_init
    ui("Reading tilesets…", 0.0)
    tilesets = Marshal.load(File.binread(ts_file))
    threshold = [THRESHOLD, (Bitmap.max_size rescue THRESHOLD)].min

    # Which tilesets are oversized?
    sizes = {}
    big = {}
    tilesets.each_with_index do |ts, id|
      next unless ts && ts.tileset_name && !ts.tileset_name.empty?
      img = tileset_image(ts.tileset_name)
      next unless img
      bmp = Bitmap.new(img) rescue next
      sizes[id] = [bmp.width, bmp.height]
      if bmp.width == 256 && bmp.height > threshold
        big[id] = bmp
      else
        bmp.dispose
      end
    end
    if big.empty?
      result["note"] = "No oversized tilesets — nothing to optimize"
      return result
    end
    result["tilesets"] = big.size

    Dir.mkdir(File.dirname(OUT_DIR)) unless File.directory?(File.dirname(OUT_DIR))
    [OUT_DIR, File.join(OUT_DIR, "Data")].each { |d| Dir.mkdir(d) unless File.directory?(d) }
    atlas_dir = File.join(Dir.pwd, "Graphics", "Tilesets", ATLAS_SUB)
    Dir.mkdir(atlas_dir) unless File.directory?(atlas_dir)

    map_files = Dir.glob(File.join(data_dir, "*")).select { |f| File.basename(f) =~ /\AMap\d{3,}\.rxdata\z/i }.sort
    variants = {}     # key => [new_id, index_hash]
    variant_list = [] # [[id, tileset]]
    next_id = tilesets.size
    manifest = ["tilesets\t#{sig(ts_file)}"]

    map_files.each_with_index do |mf, i|
      ui("#{File.basename(mf)}  (#{i + 1}/#{map_files.size})", i.to_f / map_files.size) if i % 4 == 0
      map = Marshal.load(File.binread(mf)) rescue next
      tid = map.tileset_id
      src = big[tid]
      next unless src
      used = used_tiles(map)
      key = "#{tid}:#{used.join(',')}"
      unless variants[key]
        rows = [(used.size + 7) / 8, 1].max
        atlas = Bitmap.new(256, rows * 32)
        used.each_with_index do |id, c|
          sx = (id - 384) % 8 * 32
          sy = (id - 384) / 8 * 32
          atlas.blt((c % 8) * 32, (c / 8) * 32, src, Rect.new(sx, sy, 32, 32))
        end
        orig = tilesets[tid]
        safe = orig.tileset_name.gsub(/[^0-9A-Za-z_\-]/, "_")
        fname = "#{safe}_#{variant_list.size}"
        atlas.to_file(File.join(atlas_dir, fname + ".png"))
        atlas.dispose
        ts = Marshal.load(Marshal.dump(orig))
        ts.id = next_id
        ts.name = "#{orig.name} (Yami #{variant_list.size})"
        ts.tileset_name = "#{ATLAS_SUB}/#{fname}"
        ts.passages = remap_table(orig.passages, used)
        ts.priorities = remap_table(orig.priorities, used)
        ts.terrain_tags = remap_table(orig.terrain_tags, used)
        index = {}
        used.each_with_index { |id, c| index[id] = c }
        variants[key] = [next_id, index]
        variant_list << [next_id, ts]
        result["saved_pixels"] += 256 * (sizes[tid][1] - rows * 32)
        next_id += 1
      end
      new_id, index = variants[key]
      remap_map!(map, index, new_id)
      name = File.basename(mf)
      write_atomic(File.join(OUT_DIR, "Data", name), Marshal.dump(map))
      manifest << "#{name}\t#{sig(mf)}"
      result["maps"] += 1
    end

    write_atomic(File.join(OUT_DIR, "variants.rxdata"), Marshal.dump(variant_list))
    write_atomic(File.join(OUT_DIR, "maps.txt"), manifest.join("\n") + "\n")
    result["variants"] = variant_list.size
    result["note"] = "#{result['maps']} maps now load #{variant_list.size} compact tilesets"
    big.each_value(&:dispose)
    ui("Done", 1.0)
    result
  end
end

begin
  res = YamiOptimizer.run
rescue Exception => e # rubocop:disable Lint/RescueException
  res = { "note" => "failed: #{e.class}: #{e.message}" }
end
begin
  dir = YamiOptimizer::OUT_DIR
  Dir.mkdir(File.dirname(dir)) unless File.directory?(File.dirname(dir))
  Dir.mkdir(dir) unless File.directory?(dir)
  File.open(File.join(dir, "result.txt"), "w") { |f| res.each { |k, v| f.puts("#{k}=#{v}") } }
rescue StandardError
end
exit
