import AppKit

enum WindowEdgeRegressionTests {
    enum Failure: Error { case assertion(String) }

    static func run() throws -> Int {
        var passed = 0
        func check(_ condition: Bool, _ name: String) throws {
            guard condition else { throw Failure.assertion(name) }
            print("PASS: \(name)"); passed += 1
        }
        for scale in [1, 2] {
            let width = 640 * scale, height = 600 * scale
            let radius = 24 * scale, sidebar = 81 * scale
            // The document reaches the viewport bottom. Only small corner
            // regions are fixed; a whole-row average cannot detect them.
            func frame(_ offset: Int, outputHeight: Int? = nil) -> PixelRaster {
                let h = outputHeight ?? height
                var bytes = [UInt8](repeating: 255, count: width * h * 4)
                for y in 0..<h { for x in 0..<width {
                    let i = (y * width + x) * 4
                    if x < sidebar {
                        bytes[i] = 221; bytes[i+1] = 227; bytes[i+2] = 234
                    } else if x > 160 * scale && x < 570 * scale {
                        let row = (outputHeight == nil ? y + offset : y)
                        if row % (31 * scale) < 19 * scale {
                            let value = UInt8((row * 37 + x * 19 + row * x / 11) % 200)
                            bytes[i] = value; bytes[i+1] = value; bytes[i+2] = value
                        }
                    }
                    // Different rounded corners at the window and inner pane.
                    // A simple circle gives a deterministic exact oracle.
                    if y >= h - radius {
                        let dy = Double(y - (h - radius)) + 0.5
                        let cut = Double(radius) - sqrt(max(0, Double(radius * radius) - dy * dy))
                        if Double(x) + 0.5 < cut || Double(width - x) - 0.5 < cut {
                            bytes[i] = 18; bytes[i+1] = 22; bytes[i+2] = 24
                        } else if x >= sidebar && Double(x - sidebar) + 0.5 < cut {
                            bytes[i] = 221; bytes[i+1] = 227; bytes[i+2] = 234
                        }
                    }
                } }
                return PixelRaster(width: width, height: h, bytes: bytes)
            }
            for offsets in [[3, 8, 19, 45, 82, 143, 245, 410, 680, 980], [15, 170, 420, 740, 1050]] {
                var capture = ScrollStitcher(first: frame(0))
                for step in offsets {
                    let offset = step * scale
                    _ = try capture.append(frame(offset))
                    let actual = try PixelRaster(capture.image()!)
                    try check(actual.bytes == frame(offset, outputHeight: height + offset).bytes,
                        "Rounded window and inner-sidebar corners appear once; every body row preserved (\(scale)x, \(offset))")
                }
                let end = offsets.last! * scale
                let completed = try PixelRaster(capture.image()!).bytes
                for step in [end - 80 * scale, end - 170 * scale, end - 40 * scale] {
                    _ = try capture.append(frame(step))
                    try check(try PixelRaster(capture.image()!).bytes == completed,
                        "Backscroll keeps the endpoint footer's moving text and fixed corners together (\(scale)x, \(step))")
                }
            }
        }
        return passed
    }
}
