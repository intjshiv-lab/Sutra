import AppKit

func renderSVG(svgURL: URL, targetPixelSize: Int, outputURL: URL) -> Bool {
    guard let rep = NSImageRep(contentsOf: svgURL) else {
        // Fallback: load as NSImage
        guard let img = NSImage(contentsOf: svgURL) else {
            print("Failed to load SVG at \(svgURL.path)")
            return false
        }
        return saveImage(img, pixelSize: targetPixelSize, outputURL: outputURL)
    }
    
    let img = NSImage()
    img.addRepresentation(rep)
    return saveImage(img, pixelSize: targetPixelSize, outputURL: outputURL)
}

func saveImage(_ img: NSImage, pixelSize: Int, outputURL: URL) -> Bool {
    guard let bitmapRep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        print("Failed to create bitmap rep")
        return false
    }
    
    bitmapRep.size = NSSize(width: pixelSize, height: pixelSize)
    
    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: bitmapRep) else {
        print("Failed to create graphics context")
        return false
    }
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    
    img.draw(
        in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
        from: NSRect(origin: .zero, size: img.size),
        operation: .copy,
        fraction: 1.0
    )
    
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    
    guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
        print("Failed to get PNG data")
        return false
    }
    
    do {
        try pngData.write(to: outputURL)
        return true
    } catch {
        print("Write error: \(error)")
        return false
    }
}

let args = CommandLine.arguments
if args.count < 3 {
    print("Usage: generate_icons <svg-path> <output-iconset-dir>")
    exit(1)
}

let svgURL = URL(fileURLWithPath: args[1])
let iconsetDir = URL(fileURLWithPath: args[2])

try? FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let iconSizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

print("Rendering icons from \(svgURL.lastPathComponent) into \(iconsetDir.path)...")

for (name, size) in iconSizes {
    let out = iconsetDir.appendingPathComponent(name)
    if renderSVG(svgURL: svgURL, targetPixelSize: size, outputURL: out) {
        print("  ✓ \(name) (\(size)x\(size))")
    } else {
        print("  ✗ Failed \(name)")
    }
}
print("Done!")
