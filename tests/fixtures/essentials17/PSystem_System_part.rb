if !Kernel.respond_to?("pbSetResizeFactor")
  def pbSetResizeFactor(dummy,dummy2=false); end
  def setScreenBorderName(border); end

  $ResizeFactor    = 1.0
  $ResizeFactorMul = 100
  $ResizeOffsetX   = 0
  $ResizeOffsetY   = 0
  $ResizeFactorSet = false

  module Graphics
    def self.snap_to_bitmap; return nil; end
  end
end
