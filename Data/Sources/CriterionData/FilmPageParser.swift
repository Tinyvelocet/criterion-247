import Foundation

/// Parses a Criterion Channel film page into `FilmInfo`.
/// Observed format of the meta description (single line, `\n`-separated):
///   <optional series blurb>
///   Directed by Kim Ki-young • 1960 • South Korea
///   Starring Kim Jin-kyu, Ju Jung-nyeo, Lee Eun-shim
///   <blank>
///   <synopsis paragraphs…>
/// Poster keyframe from `og:image`; slash-path from `rel=canonical`.
public enum FilmPageParser {
    public static func parse(_ html: String, title: String? = nil) throws -> FilmInfo {
        guard let desc = metaContent(html, name: "description") else {
            throw CriterionParseError("Film page has no meta description.")
        }
        let lines = desc.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)

        var info = FilmInfo(title: title ?? "")

        // Locate the "Directed by …" line; everything else is derived around it.
        guard let dIndex = lines.firstIndex(where: { $0.hasPrefix("Directed by") }) else {
            // Some pages may omit the director line; still take synopsis/poster.
            info.synopsis = lines.joined(separator: "\n")
            return applyMetadata(info, html: html)
        }

        let byLine = lines[dIndex]
        info.director = (valueAfterPrefix(byLine, prefix: "Directed by") ?? "")
            .split(separator: "•").first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        (info.year, info.country) = parseYearCountry(byLine)

        // Cast on the line after "Directed by".
        if dIndex + 1 < lines.count, lines[dIndex + 1].hasPrefix("Starring") {
            let castStr = valueAfterPrefix(lines[dIndex + 1], prefix: "Starring") ?? ""
            info.cast = castStr.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
        }

        // Synopsis: the remainder of the description after the cast line.
        let synopsisStart = dIndex + 1 + (info.cast.isEmpty ? 0 : 1)
        if synopsisStart < lines.count {
            info.synopsis = lines[synopsisStart...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return applyMetadata(info, html: html)
    }

    // MARK: - helpers

    private static func applyMetadata(_ info: FilmInfo, html: String) -> FilmInfo {
        var info = info
        info.posterURL = metaContent(html, property: "og:image")
        if info.slug == nil {
            info.slug = canonicalSlug(html)
        }
        if info.sourceFetchURL == nil {
            info.sourceFetchURL = metaContent(html, property: "og:url")
        }
        return info
    }

    private static func metaContent(_ html: String, name: String? = nil, property: String? = nil) -> String? {
        let attr = name.map { "name=\"\($0)\"" } ?? property.map { "property=\"\($0)\"" } ?? ""
        guard !attr.isEmpty else { return nil }
        let pattern = "<meta[^>]*\(attr)[^>]*content=\"([^\"]*)\"[^>]*>"
        if let capture = firstCapture(html, pattern: pattern) {
            return htmlDecode(capture)
        }
        // Fallback: attribute order swapped.
        let alt = "<meta[^>]*content=\"([^\"]*)\"[^>]*\(attr)[^>]*>"
        return firstCapture(html, pattern: alt).map(htmlDecode)
    }

    private static func canonicalSlug(_ html: String) -> String? {
        guard let slashPath = firstCapture(html, pattern: #"<link rel="canonical" href="https://www.criterionchannel.com/([a-z0-9\-]+)""#) else {
            return nil
        }
        return htmlDecode(slashPath)
    }

    /// "Director name" -> "Director name". Returns remainder after prefix, or nil.
    private static func valueAfterPrefix(_ line: String, prefix: String) -> String? {
        guard line.hasPrefix(prefix) else { return nil }
        let rest = line.dropFirst(prefix.count)
        return rest.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extracts "1960" and "South Korea" from a line like "Directed by Kim Ki-young • 1960 • South Korea".
    private static func parseYearCountry(_ line: String) -> (Int?, String?) {
        var year: Int? = nil
        var country: String? = nil
        // After "•" separators, find a 4-digit year and a trailing country token.
        let afterDirector = line.split(separator: "•").dropFirst().map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for (i, p) in afterDirector.enumerated() {
            if let y = Int(p), y >= 1900, y <= 2100 {
                year = y
                // The country usually sits right after the year.
                if i + 1 < afterDirector.count, !afterDirector[i + 1].isEmpty {
                    country = afterDirector[i + 1]
                }
            }
        }
        return (year, country)
    }
}