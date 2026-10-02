import AppKit
// Render the same red general motif used by the game, at every required icon size.
let output = CommandLine.arguments[1]
let sizes = [20,29,40,58,60,76,80,87,120,152,167,180,1024]
for size in sizes {
 let context = CGContext(data:nil,width:size,height:size,bitsPerComponent:8,bytesPerRow:size*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
 NSGraphicsContext.saveGraphicsState()
 NSGraphicsContext.current = NSGraphicsContext(cgContext:context,flipped:false)
 context.scaleBy(x:CGFloat(size)/1024,y:CGFloat(size)/1024)
 NSGradient(starting:NSColor(srgbRed:0.48,green:0.025,blue:0.065,alpha:1),ending:NSColor(srgbRed:0.83,green:0.12,blue:0.13,alpha:1))!.draw(in:NSRect(x:0,y:0,width:1024,height:1024),angle:70)
 NSColor(srgbRed:1,green:0.73,blue:0.36,alpha:0.2).setStroke()
 for n in stride(from:128,through:896,by:128) {
  let path = NSBezierPath(); path.lineWidth = 4
  path.move(to:NSPoint(x:n,y:0)); path.line(to:NSPoint(x:n,y:1024))
  path.move(to:NSPoint(x:0,y:n)); path.line(to:NSPoint(x:1024,y:n)); path.stroke()
 }
 NSColor(srgbRed:0.24,green:0.025,blue:0.025,alpha:1).setFill()
 NSBezierPath(ovalIn:NSRect(x:134,y:110,width:756,height:756)).fill()
 NSColor(srgbRed:0.65,green:0.38,blue:0.15,alpha:1).setFill()
 NSBezierPath(ovalIn:NSRect(x:134,y:135,width:756,height:756)).fill()
 let face = NSBezierPath(ovalIn:NSRect(x:134,y:168,width:756,height:756))
 NSGradient(starting:NSColor(srgbRed:1,green:0.86,blue:0.59,alpha:1),ending:NSColor(srgbRed:1,green:0.96,blue:0.82,alpha:1))!.draw(in:face,angle:90)
 let red = NSColor(srgbRed:0.7,green:0.055,blue:0.055,alpha:1)
 red.setStroke(); let ring = NSBezierPath(ovalIn:NSRect(x:174,y:208,width:676,height:676)); ring.lineWidth = 12; ring.stroke()
 let label = "帥" as NSString
 let attrs: [NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:490,weight:.bold),.foregroundColor:red]
 let extent = label.size(withAttributes:attrs)
 label.draw(at:NSPoint(x:(1024-extent.width)/2,y:546-extent.height/2),withAttributes:attrs)
 NSGraphicsContext.restoreGraphicsState()
 let bitmap = NSBitmapImageRep(cgImage:context.makeImage()!)
 try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:output).appendingPathComponent("Icon-\(size).png"))
}
