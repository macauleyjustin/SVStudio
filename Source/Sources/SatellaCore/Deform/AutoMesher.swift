import Foundation

public struct SatAutoMeshParams: Sendable {
    public var outlineSpacing: Double
    public var innerSpacing: Double
    public var padding: Double
    public var alphaThreshold: UInt8

    public init(
        outlineSpacing: Double = 24.0,
        innerSpacing: Double = 28.0,
        padding: Double = 8.0,
        alphaThreshold: UInt8 = 12
    ) {
        self.outlineSpacing = outlineSpacing
        self.innerSpacing = innerSpacing
        self.padding = padding
        self.alphaThreshold = alphaThreshold
    }
}

public enum SatAutoMesher {
    private struct Pt {
        var x: Double
        var y: Double
    }

    /// Generate a contour-following Delaunay triangular mesh for an RGBA alpha mask.
    /// Captures all interior edges, multi-island components, and outer silhouette contours
    /// without ever clipping opaque foreground pixels.
    public static func generateMesh(
        id: String,
        textureId: String,
        parentDeformer: String?,
        partId: String?,
        drawOrder: Double,
        imgWidth: Int,
        imgHeight: Int,
        canvasOffsetX: Double = 0,
        canvasOffsetY: Double = 0,
        uvClipRect: [Double]? = nil,
        params: SatAutoMeshParams = SatAutoMeshParams(),
        alphaAt: (Int, Int) -> UInt8
    ) -> SatMesh {
        var x0 = imgWidth, y0 = imgHeight, x1 = -1, y1 = -1
        for y in 0..<imgHeight {
            for x in 0..<imgWidth {
                if alphaAt(x, y) > params.alphaThreshold {
                    if x < x0 { x0 = x }
                    if x > x1 { x1 = x }
                    if y < y0 { y0 = y }
                    if y > y1 { y1 = y }
                }
            }
        }
        guard x1 >= x0 && y1 >= y0 else {
            return SatMesh(
                id: id, texture: textureId, parent: parentDeformer, part: partId,
                drawOrder: drawOrder, opacity: 1.0, blendMode: .normal,
                clipMasks: nil, invertedMask: nil, uvClipRect: uvClipRect,
                vertices: [[canvasOffsetX, canvasOffsetY], [canvasOffsetX + 10, canvasOffsetY], [canvasOffsetX, canvasOffsetY + 10]],
                uv: [[0, 0], [0.01, 0], [0, 0.01]], triangles: [0, 1, 2]
            )
        }

        let pad = params.padding
        let bx0 = max(0.0, Double(x0) - pad)
        let by0 = max(0.0, Double(y0) - pad)
        let bx1 = min(Double(imgWidth), Double(x1 + 1) + pad)
        let by1 = min(Double(imgHeight), Double(y1 + 1) + pad)
        let artW = max(1.0, Double(x1 - x0 + 1))
        let artH = max(1.0, Double(y1 - y0 + 1))
        let bw = max(4.0, bx1 - bx0)
        let bh = max(4.0, by1 - by0)

        let effOutline = min(params.outlineSpacing, max(2.5, min(artW, artH) * 0.25))
        let effInner = min(params.innerSpacing, max(3.0, min(artW, artH) * 0.30))

        func isOpaque(_ px: Double, _ py: Double) -> Bool {
            let ix = Int(floor(px))
            let iy = Int(floor(py))
            if ix < 0 || iy < 0 || ix >= imgWidth || iy >= imgHeight { return false }
            return alphaAt(ix, iy) > params.alphaThreshold
        }

        func isNearArt(_ px: Double, _ py: Double, radius: Double) -> Bool {
            let step = max(1, Int(ceil(radius * 0.4)))
            let rInt = Int(ceil(radius))
            let ix = Int(round(px))
            let iy = Int(round(py))
            var dy = -rInt
            while dy <= rInt {
                var dx = -rInt
                while dx <= rInt {
                    if dx * dx + dy * dy <= rInt * rInt {
                        let sx = ix + dx
                        let sy = iy + dy
                        if sx >= 0 && sy >= 0 && sx < imgWidth && sy < imgHeight && alphaAt(sx, sy) > params.alphaThreshold {
                            return true
                        }
                    }
                    dx += step
                }
                dy += step
            }
            return false
        }

        var points: [Pt] = []
        let minDist = max(2.0, min(effOutline, effInner) * 0.48)
        let minDistSq = minDist * minDist

        func tryAdd(_ x: Double, _ y: Double, strictMinSq: Double = -1) {
            let cx = max(0.0, min(Double(imgWidth), x))
            let cy = max(0.0, min(Double(imgHeight), y))
            let limit = strictMinSq > 0 ? strictMinSq : minDistSq
            for p in points {
                let dx = p.x - cx
                let dy = p.y - cy
                if dx * dx + dy * dy < limit { return }
            }
            points.append(Pt(x: cx, y: cy))
        }

        // Trace ALL alpha transitions (not just outer min/max!) so holes, rings, and paired blobs never clip
        let stepY = max(1.5, effOutline * 0.72)
        var py = Double(y0)
        while py <= Double(y1) {
            let iy = max(0, min(imgHeight - 1, Int(round(py))))
            var inside = false
            for x in x0...x1 {
                let op = alphaAt(x, iy) > params.alphaThreshold
                if op && !inside {
                    tryAdd(Double(x) - pad * 0.65, py)
                    inside = true
                } else if !op && inside {
                    tryAdd(Double(x - 1) + pad * 0.65, py)
                    inside = false
                }
            }
            if inside {
                tryAdd(Double(x1) + pad * 0.65, py)
            }
            py += stepY
        }

        let stepX = max(1.5, effOutline * 0.72)
        var px = Double(x0)
        while px <= Double(x1) {
            let ix = max(0, min(imgWidth - 1, Int(round(px))))
            var inside = false
            for y in y0...y1 {
                let op = alphaAt(ix, y) > params.alphaThreshold
                if op && !inside {
                    tryAdd(px, Double(y) - pad * 0.65)
                    inside = true
                } else if !op && inside {
                    tryAdd(px, Double(y - 1) + pad * 0.65)
                    inside = false
                }
            }
            if inside {
                tryAdd(px, Double(y1) + pad * 0.65)
            }
            px += stepX
        }

        // Dense interior & perimeter lattice ensuring every art cell is covered safely
        let iStepX = max(3.0, effInner)
        let iStepY = max(3.0, effInner)
        var iy = by0
        var rowParity = 0
        while iy <= by1 + iStepY * 0.5 {
            var ix = bx0 + ((rowParity % 2 == 0) ? 0.0 : iStepX * 0.5)
            while ix <= bx1 + iStepX * 0.5 {
                let clampedX = min(bx1, ix)
                let clampedY = min(by1, iy)
                if isOpaque(clampedX, clampedY) || isNearArt(clampedX, clampedY, radius: pad + iStepX * 0.55) {
                    tryAdd(clampedX, clampedY, strictMinSq: (iStepX * 0.52) * (iStepX * 0.52))
                }
                ix += iStepX
            }
            iy += iStepY
            rowParity += 1
        }

        // Fallback tight box corners when art is tiny
        tryAdd(bx0, by0, strictMinSq: minDistSq * 0.7)
        tryAdd(bx1, by0, strictMinSq: minDistSq * 0.7)
        tryAdd(bx1, by1, strictMinSq: minDistSq * 0.7)
        tryAdd(bx0, by1, strictMinSq: minDistSq * 0.7)

        // Bowyer-Watson Delaunay Triangulation
        let n = points.count
        let maxSpan = max(bw, bh) * 5.0 + 200.0
        let cxMid = (bx0 + bx1) * 0.5
        let cyMid = (by0 + by1) * 0.5
        var allPts = points
        allPts.append(Pt(x: cxMid - maxSpan, y: cyMid - maxSpan))
        allPts.append(Pt(x: cxMid + maxSpan * 2.0, y: cyMid - maxSpan))
        allPts.append(Pt(x: cxMid, y: cyMid + maxSpan * 2.0))

        struct Tri {
            var a: Int
            var b: Int
            var c: Int
        }
        var tris: [Tri] = [Tri(a: n, b: n + 1, c: n + 2)]

        func inCircumcircle(_ t: Tri, _ p: Pt) -> Bool {
            let p1 = allPts[t.a], p2 = allPts[t.b], p3 = allPts[t.c]
            let ax = p1.x - p.x, ay = p1.y - p.y
            let bx = p2.x - p.x, by = p2.y - p.y
            let cx = p3.x - p.x, cy = p3.y - p.y
            let orient = (p2.x - p1.x) * (p3.y - p1.y) - (p2.y - p1.y) * (p3.x - p1.x)
            let det = (ax * ax + ay * ay) * (bx * cy - by * cx)
                - (bx * bx + by * by) * (ax * cy - ay * cx)
                + (cx * cx + cy * cy) * (ax * by - ay * bx)
            return orient >= 0 ? (det > 1e-9) : (det < -1e-9)
        }

        for i in 0..<n {
            let p = allPts[i]
            var bad: [Tri] = []
            var good: [Tri] = []
            for t in tris {
                if inCircumcircle(t, p) { bad.append(t) } else { good.append(t) }
            }
            var polygonEdges: [(Int, Int)] = []
            for t in bad {
                let es = [(t.a, t.b), (t.b, t.c), (t.c, t.a)]
                for e in es {
                    let shared = bad.contains { other in
                        if other.a == t.a && other.b == t.b && other.c == t.c { return false }
                        let oes = [(other.a, other.b), (other.b, other.c), (other.c, other.a)]
                        return oes.contains { ($0.0 == e.0 && $0.1 == e.1) || ($0.0 == e.1 && $0.1 == e.0) }
                    }
                    if !shared { polygonEdges.append(e) }
                }
            }
            tris = good
            for e in polygonEdges {
                tris.append(Tri(a: e.0, b: e.1, c: i))
            }
        }

        // Conservative keep rule: keep triangle if centroid OR any vertex OR any edge midpoint is within padded envelope
        func triangleContainsArt(_ pa: Pt, _ pb: Pt, _ pc: Pt) -> Bool {
            let minX = max(x0, Int(floor(min(pa.x, min(pb.x, pc.x)))))
            let maxX = min(x1, Int(ceil(max(pa.x, max(pb.x, pc.x)))))
            let minY = max(y0, Int(floor(min(pa.y, min(pb.y, pc.y)))))
            let maxY = min(y1, Int(ceil(max(pa.y, max(pb.y, pc.y)))))
            guard minX <= maxX && minY <= maxY else { return false }
            let stride = max(1, min(maxX - minX, maxY - minY) / 6)

            @inline(__always)
            func insideTri(_ x: Double, _ y: Double) -> Bool {
                let d1 = (x - pb.x) * (pa.y - pb.y) - (pa.x - pb.x) * (y - pb.y)
                let d2 = (x - pc.x) * (pb.y - pc.y) - (pb.x - pc.x) * (y - pc.y)
                let d3 = (x - pa.x) * (pc.y - pa.y) - (pc.x - pa.x) * (y - pa.y)
                let hasNeg = (d1 < -0.5) || (d2 < -0.5) || (d3 < -0.5)
                let hasPos = (d1 > 0.5) || (d2 > 0.5) || (d3 > 0.5)
                return !(hasNeg && hasPos)
            }

            var y = minY
            while y <= maxY {
                var x = minX
                while x <= maxX {
                    if alphaAt(x, y) > params.alphaThreshold && insideTri(Double(x), Double(y)) {
                        return true
                    }
                    x += stride
                }
                y += stride
            }
            return false
        }

        var keptIndices: [Int] = []
        let carveRadius = max(pad + 5.0, effOutline * 0.75)
        for t in tris where t.a < n && t.b < n && t.c < n {
            let pa = points[t.a], pb = points[t.b], pc = points[t.c]
            let area2 = abs((pb.x - pa.x) * (pc.y - pa.y) - (pb.y - pa.y) * (pc.x - pa.x))
            if area2 < 0.05 { continue }
            let mx = (pa.x + pb.x + pc.x) / 3.0
            let my = (pa.y + pb.y + pc.y) / 3.0
            if isNearArt(mx, my, radius: carveRadius) || triangleContainsArt(pa, pb, pc) {
                keptIndices.append(t.a)
                keptIndices.append(t.b)
                keptIndices.append(t.c)
            }
        }

        if keptIndices.isEmpty {
            return SatMesh(
                id: id, texture: textureId, parent: parentDeformer, part: partId,
                drawOrder: drawOrder, opacity: 1.0, blendMode: .normal,
                clipMasks: nil, invertedMask: nil, uvClipRect: uvClipRect,
                vertices: [
                    [canvasOffsetX + bx0, canvasOffsetY + by0],
                    [canvasOffsetX + bx1, canvasOffsetY + by0],
                    [canvasOffsetX + bx1, canvasOffsetY + by1],
                    [canvasOffsetX + bx0, canvasOffsetY + by1],
                ],
                uv: [
                    [bx0 / Double(imgWidth), by0 / Double(imgHeight)],
                    [bx1 / Double(imgWidth), by0 / Double(imgHeight)],
                    [bx1 / Double(imgWidth), by1 / Double(imgHeight)],
                    [bx0 / Double(imgWidth), by1 / Double(imgHeight)],
                ],
                triangles: [0, 1, 2, 0, 2, 3]
            )
        }

        var remap = [Int: Int]()
        var outVerts: [[Double]] = []
        var outUVs: [[Double]] = []
        var outTris: [Int] = []
        for oldIdx in keptIndices {
            let newIdx: Int
            if let existing = remap[oldIdx] {
                newIdx = existing
            } else {
                newIdx = outVerts.count
                remap[oldIdx] = newIdx
                let p = points[oldIdx]
                outVerts.append([canvasOffsetX + p.x, canvasOffsetY + p.y])
                outUVs.append([p.x / Double(imgWidth), p.y / Double(imgHeight)])
            }
            outTris.append(newIdx)
        }

        return SatMesh(
            id: id, texture: textureId, parent: parentDeformer, part: partId,
            drawOrder: drawOrder, opacity: 1.0, blendMode: .normal,
            clipMasks: nil, invertedMask: nil, uvClipRect: uvClipRect,
            vertices: outVerts, uv: outUVs, triangles: outTris
        )
    }
}
