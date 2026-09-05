import Foundation

/// Top-left origin, normalized to the full referenced image. Empty rectangles are rejected.
public struct NormalizedRect: Codable, Sendable, Equatable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) throws {
        guard [x, y, width, height].allSatisfy({ $0.isFinite }),
              x >= 0, y >= 0, width > 0, height > 0,
              x <= 1, y <= 1, width <= 1, height <= 1,
              x + width <= 1, y + height <= 1 else {
            throw AppError(code: .unsupportedInput)
        }
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    public static let fullPage = try! NormalizedRect(x: 0, y: 0, width: 1, height: 1)

    private enum CodingKeys: String, CodingKey { case x, y, width, height }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(x: c.decode(Double.self, forKey: .x), y: c.decode(Double.self, forKey: .y),
                      width: c.decode(Double.self, forKey: .width), height: c.decode(Double.self, forKey: .height))
    }

    /// Call once at the Vision adapter boundary. Values otherwise retain top-left coordinates.
    public static func fromBottomLeft(x: Double, y: Double, width: Double, height: Double) throws -> Self {
        try Self(x: x, y: 1 - (y + height), width: width, height: height)
    }
}

/// Row-major 3x3 homography. Maps normalized source coordinates into normalized destination coordinates.
/// A nil mapping on an asset/result means mapping is unreliable: reference the derived image itself.
public struct CoordinateMapping: Codable, Sendable, Equatable {
    public let values: [Double]
    public init(values: [Double]) throws {
        guard values.count == 9, values.allSatisfy({ $0.isFinite }) else {
            throw AppError(code: .unsupportedInput)
        }
        let m = values
        let determinant = m[0] * (m[4]*m[8] - m[5]*m[7]) - m[1] * (m[3]*m[8] - m[5]*m[6]) + m[2] * (m[3]*m[7] - m[4]*m[6])
        guard determinant.isFinite, abs(determinant) > 1e-12 else { throw AppError(code: .unsupportedInput) }
        self.values = values
    }
    public static let identity = try! CoordinateMapping(values: [1,0,0,0,1,0,0,0,1])
    private enum CodingKeys: String, CodingKey { case values }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(values: c.decode([Double].self, forKey: .values))
    }
}
