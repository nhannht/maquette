import Foundation

// The run's reference images. One primary view drives the subject cutout the
// judge leans on and the comparison sheet's hero slot; up to maxExtras further
// views of the SAME object sharpen the brief, the spec, and the judge's read
// of hidden sides. Labels are short user words ("back", "open lid") burned
// into the sheet so the vision model cannot mistake a view for a second object.

public struct ReferenceImage: Equatable, Sendable {
    public var path: String
    public var label: String?

    public init(path: String, label: String? = nil) {
        self.path = path
        self.label = label
    }
}

public struct ReferenceSet: Equatable, Sendable {
    public static let maxExtras = 3

    public var primary: ReferenceImage
    public var extras: [ReferenceImage]

    public init(primary: ReferenceImage, extras: [ReferenceImage] = []) {
        self.primary = primary
        self.extras = Array(extras.prefix(Self.maxExtras))
    }

    /// Primary first - the order every consumer (lift, prompts, sheet) uses.
    public var all: [ReferenceImage] { [primary] + extras }
}
