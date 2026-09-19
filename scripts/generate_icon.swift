#!/usr/bin/env swift

import AppKit

// Generate a bee-themed app icon using SF Symbols
func generateIcon(size: CGSize, filename: String) {
    let image = NSImage(size: size, flipped: false, drawingHandler: { rect in
        // Background gradient (golden yellow to amber, bee-like)
        let gradient = NSGradient(colors: [
            NSColor(red: 1.0, green: 0.78, blue: 0.0, alpha: 1.0),  // Golden
            NSColor(red: 1.0, green: 0.65, blue: 0.0, alpha: 1.0)   // Amber
        ])!
        gradient.draw(in: rect, angle: 135)

        // Use ladybug symbol (closest to bee in SF Symbols)
        let config = NSImage.SymbolConfiguration(pointSize: size.width * 0.55, weight: .medium)
        if let symbol = NSImage(systemSymbolName: "ladybug.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {

            // Draw black symbol
            NSColor(white: 0.15, alpha: 1.0).set()
            let symbolRect = CGRect(
                x: (size.width - symbol.size.width) / 2,
                y: (size.height - symbol.size.height) / 2 - size.height * 0.02, // Slight offset up
                width: symbol.size.width,
                height: symbol.size.height
            )
            symbol.draw(in: symbolRect)
        }

        return true
    })

    // Save as PNG
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to convert image for \(filename)")
        return
    }

    do {
        try pngData.write(to: URL(fileURLWithPath: filename))
        print("✓ Generated: \(filename)")
    } catch {
        print("✗ Failed to write: \(filename)")
    }
}

// Icon sizes for macOS
let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

print("Generating DoppelBee app icons...")
for (size, filename) in sizes {
    let path = "\(outputDir)/\(filename)"
    generateIcon(size: CGSize(width: CGFloat(size), height: CGFloat(size)), filename: path)
}

print("\n✓ All icons generated successfully!")
