import AppKit
let output=CommandLine.arguments[1]
let size=1024
let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
let context=NSGraphicsContext(bitmapImageRep:bitmap)!
NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context
NSColor.clear.setFill();NSRect(x:0,y:0,width:1024,height:1024).fill()
let base=NSBezierPath(roundedRect:NSRect(x:40,y:40,width:944,height:944),xRadius:212,yRadius:212)
NSGradient(starting:NSColor(calibratedRed:0.15,green:0.18,blue:0.22,alpha:1),ending:NSColor(calibratedRed:0.055,green:0.067,blue:0.085,alpha:1))!.draw(in:base,angle:90)
NSColor(calibratedRed:1,green:0.58,blue:0.31,alpha:0.35).setFill();NSBezierPath(roundedRect:NSRect(x:248,y:717,width:528,height:44),xRadius:18,yRadius:18).fill()
NSColor(calibratedRed:1,green:0.58,blue:0.31,alpha:0.65).setFill();NSBezierPath(roundedRect:NSRect(x:214,y:659,width:596,height:44),xRadius:18,yRadius:18).fill()
NSColor(calibratedRed:1,green:0.58,blue:0.31,alpha:1).setFill();NSBezierPath(roundedRect:NSRect(x:174,y:255,width:676,height:388),xRadius:50,yRadius:50).fill()
NSColor(calibratedRed:0.07,green:0.08,blue:0.1,alpha:1).setFill();NSBezierPath(roundedRect:NSRect(x:302,y:282,width:420,height:334),xRadius:20,yRadius:20).fill()
for x in [209,763] {for y in [295,371,447,523] {NSBezierPath(roundedRect:NSRect(x:x,y:y,width:52,height:48),xRadius:8,yRadius:8).fill()}}
NSColor(calibratedRed:0.97,green:0.94,blue:0.88,alpha:1).setFill()
let play=NSBezierPath();play.move(to:NSPoint(x:454,y:351));play.line(to:NSPoint(x:613,y:449));play.line(to:NSPoint(x:454,y:547));play.close();play.fill()
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:output))
