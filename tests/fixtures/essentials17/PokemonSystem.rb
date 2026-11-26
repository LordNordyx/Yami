class PokemonSystem
  attr_accessor :textspeed
  attr_accessor :battlescene
  attr_accessor :battlestyle
  attr_accessor :frame
  attr_accessor :textskin
  attr_accessor :font
  attr_accessor :screensize
  attr_accessor :border
  attr_accessor :language
  attr_accessor :runstyle
  attr_accessor :bgmvolume
  attr_accessor :sevolume
  attr_accessor :textinput

  def initialize
    @textspeed   = 2   # Text speed (0=slow, 1=normal, 2=fast)
    @battlescene = 0   # Battle effects (animations) (0=on, 1=off)
    @battlestyle = 0   # Battle style (0=switch, 1=set)
    @frame       = 0   # Default window frame (see also $TextFrames)
    @textskin    = 0   # Speech frame
    @font        = 0   # Font (see also $VersionStyles)
    @screensize  = (DEFAULTSCREENZOOM.floor).to_i # 0=half size, 1=full size, 2=double size
    @border      = 0   # Screen border (0=off, 1=on)
    @language    = 0   # Language (see also LANGUAGES in script PokemonSystem)
    @runstyle    = 0   # Run key functionality (0=hold to run, 1=toggle auto-run)
    @bgmvolume   = 100 # Volume of background music and ME
    @sevolume    = 100 # Volume of sound effects
    @textinput   = 0   # Text input mode (0=cursor, 1=keyboard)
  end

  def textskin
    @textskin = 0 if !@textskin
    return @textskin
  end

  def border
    @border = 0 if !@border
    return @border
  end

  def language
    @language = 0 if !@language
    return @language
  end

  def runstyle
    @runstyle = 0 if !@runstyle
    return @runstyle
  end

  def bgmvolume
    @bgmvolume = 100 if !@bgmvolume
    return @bgmvolume
  end

  def sevolume
    @sevolume = 100 if !@sevolume
    return @sevolume
  end

  def textinput
    @textinput = 0 if !@textinput
    return @textinput
  end

  def tilemap; return MAPVIEWMODE; end
end
