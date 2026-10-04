// Local diagnostic: pass the supplied 3840-wide long image as the only argument.
// Reuses its initial 2100-row viewport chrome; the moving body is controlled test data.
// No user image is checked into the repository. This is not a live browser test.
import AppKit
import ImageIO
@main struct Replay {
    static func main() throws {
        setbuf(stdout, nil)
        let path = CommandLine.arguments[1]
        let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)!
        let captured = try PixelRaster(CGImageSourceCreateImageAtIndex(source, 0, nil)!)
        let width = captured.width, height = 2100, bodyTop = 470, decoration = 80
        let reference = captured.rows(0..<height)
        func frame(_ offset: Int, outputHeight: Int? = nil) -> PixelRaster {
            let h = outputHeight ?? height
            var bytes = [UInt8](repeating: 255, count: width * h * 4)
            for y in 0..<h {
                let sy = outputHeight == nil ? y : (y < height - decoration ? y : (y >= h - decoration ? height - h + y : height - decoration - 1))
                bytes.replaceSubrange((y * width * 4)..<((y + 1) * width * 4), with: reference.bytes[(sy * width * 4)..<((sy + 1) * width * 4)])
                guard y >= bodyTop else { continue }
                let documentY = outputHeight == nil ? y + offset : y
                for x in 900..<3300 {
                    let i = (y * width + x) * 4
                    var seed = UInt32(documentY) &* 747796405 &+ UInt32(x / 3) &* 2891336453
                    seed = ((seed >> ((seed >> 28) + 4)) ^ seed) &* 277803737
                    let v = UInt8(truncatingIfNeeded: (seed >> 22) ^ seed)
                    bytes[i] = v; bytes[i+1] = v; bytes[i+2] = v
                }
            }
            return PixelRaster(width: width, height: h, bytes: bytes)
        }
        let first = frame(0), second = frame(3)
        let edges = ScrollMatcher.fixedEdges(first, second, previousFeatures: ScrollFeatures(first), nextFeatures: ScrollFeatures(second))
        print("REAL_ATTACHMENT_EDGE_DEPTH", edges)
        var capture = ScrollStitcher(first: first)
        for offset in [3, 8, 19, 45, 82, 143, 245, 410, 680, 1070, 1610] {
            _ = try capture.append(frame(offset))
            let result = try PixelRaster(capture.image()!)
            let expected = frame(offset, outputHeight: height + offset)
            guard result.bytes == expected.bytes else { fatalError("Real edge replay mismatch at \(offset), height \(result.height)") }
            print("PASS: Actual attachment edge pixels with controlled scrolling, offset", offset)
        }
        let complete = try PixelRaster(capture.image()!).bytes
        for offset in [1500, 1300, 1450] {
            _ = try capture.append(frame(offset))
            guard try PixelRaster(capture.image()!).bytes == complete else { fatalError("Footer changed on reverse") }
        }
        print("PASS: Actual attachment edge replay remains intact during reverse scrolling")
    }
}
