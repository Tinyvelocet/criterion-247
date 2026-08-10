import Foundation

public struct CriterionParseError: Error, CustomStringConvertible, Sendable {
    public let description: String
    public init(_ description: String) { self.description = description }
}

/// Convenience: find first capture group of a regex in a string.
func firstCapture(_ html: String, pattern: String, options: NSRegularExpression.Options = []) -> String? {
    guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
    let range = NSRange(html.startIndex..., in: html)
    guard let m = re.firstMatch(in: html, range: range), m.numberOfRanges > 1,
          let r = Range(m.range(at: 1), in: html) else { return nil }
    return String(html[r])
}

/// Parses the server-rendered "What's On Now" page.
/// HTML structure observed (v1.133):
///   <h2 class="whatson__title">The Housemaid</h2>
///   <a href="https://www.criterionchannel.com/events/criterion-24-7" class="...--live">Watch Live</a>
///   <a href="https://www.criterionchannel.com/the-housemaid" class="...--more">More</a>
///   <p class="whatson__eyebrow">Next film starts in: <span class="whatson__eyebrow--bold">10 minutes</span></p>
public enum CriterionClient {
    public static let baseURL = URL(string: "https://whatsonnow.criterionchannel.com/")!

    public static func parseNowPlaying(_ html: String, fetchedAt: Date) throws -> NowPlayingLine {
        // 1. Title.
        guard let title = firstCapture(
            html, pattern: #"<h2 class="whatson__title">\s*(.*?)\s*</h2>"#
        ), !title.isEmpty else {
            throw CriterionParseError("Could not find the current film title in the page.")
        }

        // 2. Slug — film page path from the "More" link.
        // The page always contains at least one link to the film page
        // like https://www.criterionchannel.com/the-housemaid, distinct from
        // the /events/criterion-24-7 live-watch link.
        var slug = firstCapture(
            html,
            pattern: #"criterionchannel\.com/(?!events|assets)([a-z0-9\-]+)""#
        ) ?? ""
        if slug.isEmpty || slug.hasPrefix("criterion-24-7") { slug = "" }

        // 3. Minutes until the next film.
        let minutes = Int(
            firstCapture(
                html,
                pattern: #"(?:next film starts in:)?\s*([0-9]+)\s*minute"#,
                options: [.caseInsensitive]
            ) ?? "0"
        ) ?? 0

        return NowPlayingLine(
            title: htmlDecode(title),
            slug: htmlDecode(slug),
            minutesUntilNext: minutes,
            fetchedAt: fetchedAt
        )
    }
}

func htmlDecode(_ s: String) -> String {
    // Minimal decoding for the entities Criterion uses (apostrophes, &, quotes, ellipses).
    var out = s
    let table = [
        "&amp;": "&", "&lt;": "<", "&gt;": ">",
        "&quot;": "\"", "&#39;": "'", "&apos;": "'",
    ]
    for (k, v) in table { out = out.replacingOccurrences(of: k, with: v) }
    return out
}