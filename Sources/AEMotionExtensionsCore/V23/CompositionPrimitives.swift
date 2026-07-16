import Foundation

public struct CompositionID: Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue.uuidString.lowercased() }
}

public struct LayerID: Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue.uuidString.lowercased() }
}

public enum CompositionTimeRangeError: Error, Equatable, Sendable {
    case nonFinite
    case negativeStart
    case negativeDuration
}

public struct CompositionTimeRange: Codable, Equatable, Sendable {
    public let start: Double
    public let duration: Double

    public var end: Double { start + duration }

    public init(start: Double, duration: Double) throws {
        guard start.isFinite, duration.isFinite else { throw CompositionTimeRangeError.nonFinite }
        guard start >= 0 else { throw CompositionTimeRangeError.negativeStart }
        guard duration >= 0 else { throw CompositionTimeRangeError.negativeDuration }
        self.start = start
        self.duration = duration
    }

    public init(start: Double, end: Double) throws {
        guard start.isFinite, end.isFinite else { throw CompositionTimeRangeError.nonFinite }
        guard start >= 0 else { throw CompositionTimeRangeError.negativeStart }
        guard end >= start else { throw CompositionTimeRangeError.negativeDuration }
        self.start = start
        self.duration = end - start
    }

    public func shifted(by delta: Double) throws -> CompositionTimeRange {
        try CompositionTimeRange(start: start + delta, duration: duration)
    }
}

public enum AffineTransformError: Error, Equatable, Sendable {
    case singular
    case nonFinite
}

/// Platform-independent affine transform using the same coefficient layout as CGAffineTransform.
public struct AffineTransform2D: Codable, Equatable, Sendable {
    public var a: Double
    public var b: Double
    public var c: Double
    public var d: Double
    public var tx: Double
    public var ty: Double

    public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.tx = tx
        self.ty = ty
    }

    public static let identity = AffineTransform2D(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    public static func translation(x: Double, y: Double) -> AffineTransform2D {
        .init(a: 1, b: 0, c: 0, d: 1, tx: x, ty: y)
    }

    public static func scale(x: Double, y: Double) -> AffineTransform2D {
        .init(a: x, b: 0, c: 0, d: y, tx: 0, ty: 0)
    }

    public static func rotation(radians: Double) -> AffineTransform2D {
        let cosine = cos(radians)
        let sine = sin(radians)
        return .init(a: cosine, b: sine, c: -sine, d: cosine, tx: 0, ty: 0)
    }

    /// Returns self * rhs, so rhs is applied first and self second.
    public func concatenating(_ rhs: AffineTransform2D) -> AffineTransform2D {
        .init(
            a: a * rhs.a + c * rhs.b,
            b: b * rhs.a + d * rhs.b,
            c: a * rhs.c + c * rhs.d,
            d: b * rhs.c + d * rhs.d,
            tx: a * rhs.tx + c * rhs.ty + tx,
            ty: b * rhs.tx + d * rhs.ty + ty
        )
    }

    public func inverted(epsilon: Double = 1e-12) throws -> AffineTransform2D {
        let determinant = a * d - b * c
        guard determinant.isFinite, abs(determinant) > epsilon else { throw AffineTransformError.singular }
        let inverse = 1 / determinant
        let result = AffineTransform2D(
            a: d * inverse,
            b: -b * inverse,
            c: -c * inverse,
            d: a * inverse,
            tx: (c * ty - d * tx) * inverse,
            ty: (b * tx - a * ty) * inverse
        )
        guard result.isFinite else { throw AffineTransformError.nonFinite }
        return result
    }

    public var isFinite: Bool {
        [a, b, c, d, tx, ty].allSatisfy(\.isFinite)
    }

    public func applying(x: Double, y: Double) -> (x: Double, y: Double) {
        (a * x + c * y + tx, b * x + d * y + ty)
    }
}

public struct LayerTransform: Codable, Equatable, Sendable {
    public var positionX: Double
    public var positionY: Double
    public var anchorX: Double
    public var anchorY: Double
    public var scaleX: Double
    public var scaleY: Double
    public var rotationRadians: Double
    public var opacity: Double

    public init(
        positionX: Double = 0,
        positionY: Double = 0,
        anchorX: Double = 0,
        anchorY: Double = 0,
        scaleX: Double = 1,
        scaleY: Double = 1,
        rotationRadians: Double = 0,
        opacity: Double = 1
    ) {
        self.positionX = positionX
        self.positionY = positionY
        self.anchorX = anchorX
        self.anchorY = anchorY
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.rotationRadians = rotationRadians
        self.opacity = opacity
    }

    public static let identity = LayerTransform()

    public var localMatrix: AffineTransform2D {
        AffineTransform2D.translation(x: positionX, y: positionY)
            .concatenating(.rotation(radians: rotationRadians))
            .concatenating(.scale(x: scaleX, y: scaleY))
            .concatenating(.translation(x: -anchorX, y: -anchorY))
    }

    public static func decomposing(
        _ matrix: AffineTransform2D,
        preservingAnchorX anchorX: Double = 0,
        anchorY: Double = 0,
        opacity: Double = 1,
        epsilon: Double = 1e-12
    ) throws -> LayerTransform {
        guard matrix.isFinite else { throw AffineTransformError.nonFinite }
        let scaleX = hypot(matrix.a, matrix.b)
        guard scaleX > epsilon else { throw AffineTransformError.singular }
        let determinant = matrix.a * matrix.d - matrix.b * matrix.c
        let scaleY = determinant / scaleX
        guard scaleY.isFinite, abs(scaleY) > epsilon else { throw AffineTransformError.singular }
        let rotation = atan2(matrix.b, matrix.a)
        let anchorContributionX = matrix.a * anchorX + matrix.c * anchorY
        let anchorContributionY = matrix.b * anchorX + matrix.d * anchorY
        return LayerTransform(
            positionX: matrix.tx + anchorContributionX,
            positionY: matrix.ty + anchorContributionY,
            anchorX: anchorX,
            anchorY: anchorY,
            scaleX: scaleX,
            scaleY: scaleY,
            rotationRadians: rotation,
            opacity: opacity
        )
    }
}

public struct PixelRGBA: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let clear = PixelRGBA(red: 0, green: 0, blue: 0, alpha: 0)

    public var clamped: PixelRGBA {
        .init(
            red: Self.unit(red),
            green: Self.unit(green),
            blue: Self.unit(blue),
            alpha: Self.unit(alpha)
        )
    }

    public var rec709Luminance: Double {
        0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    static func unit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}
