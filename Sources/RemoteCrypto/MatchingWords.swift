import Foundation

/// Four short words from a digest, for people to compare on two screens (MacPeek Remote uses them to approve a new
/// console of an account). If they match, nobody is in the middle.
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
