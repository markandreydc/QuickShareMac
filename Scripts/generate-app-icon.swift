#!/usr/bin/env swift
import AppKit

// The brand image remains full-bleed for the header/About view. Generate every
// Dock/Finder icon directly from it, with the standard 824/1024 artwork footprint.
// Usage: swift Scripts/generate-app-icon.swift [--check]
let root=URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let assets=root.appendingPathComponent("QuickShareMac/Assets.xcassets")
let iconSet=assets.appendingPathComponent("AppIcon.appiconset")
let checkOnly=CommandLine.arguments.contains("--check")

func load(_ url:URL) throws -> CGImage{
	guard let image=NSBitmapImageRep(data: try Data(contentsOf: url))?.cgImage else{throw CocoaError(.fileReadCorruptFile)}
	return image
}

func alphaBounds(_ image:CGImage)->CGRect{
	let width=image.width, height=image.height
	var pixels=[UInt8](repeating: 0, count: width*height*4)
	pixels.withUnsafeMutableBytes{bytes in
		let context=CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width*4,
			space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue|CGBitmapInfo.byteOrder32Big.rawValue)!
		context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
	}
	var minX=width, minY=height, maxX = -1, maxY = -1
	for y in 0..<height{
		for x in 0..<width where pixels[(y*width+x)*4+3]>16{
			minX=min(minX,x); minY=min(minY,y); maxX=max(maxX,x); maxY=max(maxY,y)
		}
	}
	return maxX<0 ? .zero : CGRect(x: minX, y: minY, width: maxX-minX+1, height: maxY-minY+1)
}

let source=try load(assets.appendingPathComponent("QuickShareMacBrandIcon.imageset/QuickShareMacBrandIcon@2x.png"))
let sourceBounds=alphaBounds(source)
precondition(!sourceBounds.isEmpty, "The source artwork must not be empty")
let artwork=source.cropping(to: sourceBounds)!
let manifest=try JSONSerialization.jsonObject(with: Data(contentsOf: iconSet.appendingPathComponent("Contents.json"))) as! [String:Any]
let entries=manifest["images"] as! [[String:String]]
var checked=0
for entry in entries{
	let points=Double(entry["size"]!.split(separator: "x")[0])!
	let scale=Double(entry["scale"]!.dropLast())!
	let size=Int(points*scale)
	let destination=iconSet.appendingPathComponent(entry["filename"]!)
	if !checkOnly{
		let context=CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size*4,
			space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
		context.interpolationQuality = .high
		let edge=(CGFloat(size)*824/1024).rounded()
		let inset=(CGFloat(size)-edge)/2
		context.draw(artwork, in: CGRect(x: inset, y: inset, width: edge, height: edge))
		let png=NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
		try png.write(to: destination, options: .atomic)
	}
	let image=try load(destination)
	let bounds=alphaBounds(image)
	precondition(image.width==size && image.height==size, "Wrong dimensions: \(destination.lastPathComponent)")
	precondition(!bounds.isEmpty && bounds.minX>=1 && bounds.minY>=1 && bounds.maxX<CGFloat(size) && bounds.maxY<CGFloat(size), "Icon must have transparent margins: \(destination.lastPathComponent)")
	precondition(abs(bounds.midX-CGFloat(size)/2)<=1 && abs(bounds.midY-CGFloat(size)/2)<=1, "Artwork must be centered")
	if size>=32{
		precondition(bounds.width/CGFloat(size)<=0.85 && bounds.width/CGFloat(size)>=0.78, "Artwork must match the macOS Dock footprint")
	}
	checked+=1
}
print("Verified \(checked) app icon sizes: centered artwork, transparent margins, standard Dock footprint")
