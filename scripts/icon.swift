import AppKit
import Foundation
let directory = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath:directory,withIntermediateDirectories:true)
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
        let transform = NSAffineTransform(); transform.scale(by:CGFloat(pixels)/1024); transform.concat()
        NSColor(calibratedRed:0.055,green:0.11,blue:0.12,alpha:1).setFill()
        NSBezierPath(roundedRect:NSRect(x:20,y:20,width:984,height:984),xRadius:215,yRadius:215).fill()
        NSColor(calibratedRed:0.21,green:0.86,blue:0.72,alpha:1).setStroke()
        let phone = NSBezierPath(roundedRect:NSRect(x:316,y:172,width:392,height:680),xRadius:68,yRadius:68)
        phone.lineWidth = 38; phone.stroke()
        NSColor(calibratedRed:0.21,green:0.86,blue:0.72,alpha:1).setFill()
        NSBezierPath(roundedRect:NSRect(x:445,y:777,width:134,height:18),xRadius:9,yRadius:9).fill()
        NSBezierPath(roundedRect:NSRect(x:445,y:220,width:134,height:14),xRadius:7,yRadius:7).fill()
        let play=NSBezierPath(); play.move(to:NSPoint(x:454,y:422)); play.line(to:NSPoint(x:454,y:608)); play.line(to:NSPoint(x:594,y:515)); play.close(); play.fill()
        NSGraphicsContext.restoreGraphicsState()
        let name="icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
        try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:directory).appendingPathComponent(name))
    }
}
