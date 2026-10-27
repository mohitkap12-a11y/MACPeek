import Foundation

/// The six digits a Mac shows when someone chooses "Show pairing code". They prove the person pairing can see that Mac's
/// screen. The code is short-lived and allows only a few attempts; the matching words protect the connection itself.
public struct PairingCode: Equatable, Sendable {
    public static let lifetime: TimeInterval = 300
    public static let maximumAttempts = 3

    public let digits: String
    public let expiresAt: Date

    public init(digits: String, expiresAt: Date) {
        self.digits = digits
        self.expiresAt = expiresAt
    }

    /// A uniformly random code from the system's secure generator.
    public static func generate(now: Date = Date()) -> PairingCode {
        var generator = SystemRandomNumberGenerator()
        let value = Int.random(in: 0..<1_000_000, using: &generator)
        return PairingCode(digits: String(format: "%06d", value), expiresAt: now.addingTimeInterval(lifetime))
    }

    /// "482 913".
    public var formatted: String { "\(digits.prefix(3)) \(digits.suffix(3))" }

    public func isExpired(at now: Date = Date()) -> Bool { now >= expiresAt }

    /// What someone typed, as six digits, or nil. Spaces and dashes are ignored: "482 913" and "482-913" both work.
    public static func normalized(_ typed: String) -> String? {
        let digits = typed.filter { !$0.isWhitespace && $0 != "-" }
        guard digits.count == 6, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return digits
    }
}

/// The words both screens show while pairing. If they match, nobody is in the middle of the connection.
public enum MatchingWords {
    public static let count = 4

    /// Four words, one per byte of `digest`.
    public static func words(for digest: Data) -> [String] {
        digest.prefix(count).map { list[Int($0)] }
    }

    /// 256 short, common, distinct words: one per byte value.
    public static let list: [String] = [
        "acorn", "actor", "album", "amber", "anchor", "apple", "apron", "arrow", "atlas", "autumn", "badge", "bagel",
        "bamboo", "banjo", "barrel", "basil", "beach", "beacon", "beaver", "berry", "bison", "blanket", "blossom", "boat",
        "bolt", "bonnet", "border", "bottle", "branch", "bread", "breeze", "brick", "bridge", "brook", "bubble", "bucket",
        "buffalo", "butter", "button", "cabin", "cactus", "camel", "camera", "candle", "canoe", "canyon", "carpet", "carrot",
        "castle", "cedar", "cello", "chalk", "cherry", "chess", "circle", "citrus", "cliff", "clock", "cloud", "clover",
        "cobalt", "coconut", "comet", "compass", "copper", "coral", "cotton", "crayon", "cricket", "crystal", "cup", "cupboard",
        "daisy", "dawn", "desert", "diamond", "dinner", "dolphin", "donkey", "dragon", "drum", "eagle", "echo", "eclipse",
        "elbow", "ember", "engine", "falcon", "feather", "fern", "fiddle", "fig", "flame", "flute", "forest", "fossil",
        "fountain", "fox", "galaxy", "garden", "garlic", "gecko", "ginger", "glacier", "globe", "goose", "granite", "grape",
        "gravel", "guitar", "hammer", "harbor", "harvest", "hazel", "helmet", "heron", "hill", "honey", "horizon", "iceberg",
        "igloo", "island", "ivory", "jacket", "jasmine", "jelly", "jungle", "kayak", "kettle", "kitten", "koala", "ladder",
        "lagoon", "lantern", "lemon", "lentil", "library", "lily", "lizard", "lobster", "magnet", "mango", "maple", "marble",
        "meadow", "melon", "mirror", "mitten", "moon", "mosaic", "mountain", "muffin", "nectar", "needle", "nest", "nickel",
        "noodle", "nutmeg", "oasis", "ocean", "olive", "onion", "orange", "orbit", "orchid", "otter", "owl", "oyster",
        "paddle", "palace", "panda", "paper", "parrot", "peach", "peanut", "pebble", "pencil", "penguin", "pepper", "piano",
        "pickle", "pillow", "pine", "planet", "plum", "pocket", "pony", "poppy", "puzzle", "quartz", "quilt", "rabbit",
        "radish", "rainbow", "raven", "ribbon", "river", "robin", "rocket", "saddle", "saffron", "salmon", "sandal", "satin",
        "scarf", "shadow", "shell", "silver", "sketch", "sled", "socket", "sparrow", "spider", "spoon", "spruce", "squirrel",
        "stable", "star", "stone", "sugar", "summit", "sunset", "swan", "table", "tablet", "teapot", "thistle", "thunder",
        "tiger", "timber", "tomato", "topaz", "torch", "tractor", "tulip", "tundra", "turtle", "umbrella", "valley", "velvet",
        "violin", "volcano", "wagon", "walnut", "walrus", "willow", "window", "winter", "wizard", "wolf", "yarn", "zebra",
        "zipper", "basket", "cookie", "dune",
    ]
}
