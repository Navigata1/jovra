import Foundation

/// The Share Pack's static `index.html` (screens N3): score, stats with their fractions and provenance, and the clip
/// list with notes. No scripts, no external resources, no tracking; it opens from the folder in any browser.
/// Colours are the JOVRA DesignSystem tokens (ColorRole) for light and dark appearance.
enum SharePackViewer {
    private static let rows: [(stat: String, label: String, note: String?)] = [
        ("totalPointsWon", "Points won", nil),
        ("firstServeIn", "First serves in", nil),
        ("firstServePointsWon", "First-serve points won", nil),
        ("secondServePointsWon", "Second-serve points won", "Points after a 1st-serve fault, double faults included"),
        ("breakPointsConverted", "Break points won", nil),
        ("breakPointsSaved", "Break points saved", nil),
        ("aces", "Aces", nil),
        ("doubleFaults", "Double faults", nil),
        ("winners", "Winners", "Aces not included"),
        ("unforcedErrors", "Unforced errors", nil),
    ]

    static func html(document: SessionDocument, rendered: DataExporter.Rendered, clips: [SharePackClip], selectedCount: Int?) throws -> String {
        let lines = try StatsEngine.lines(rendered.timeline, sample: document.sample != nil)
        let byKey = Dictionary(lines.map { ($0.key, $0.stat) }, uniquingKeysWith: { first, _ in first })
        let a = rendered.sideNames[.a] ?? "Side A", b = rendered.sideNames[.b] ?? "Side B"
        let match = rendered.timeline.match
        let winner = match.winner.value.flatMap { Side(rawValue: $0.rawValue) }.flatMap { rendered.sideNames[$0] }
        let result: String
        switch (match.status, winner, match.scoreline.value) {
        case (.completed, let name?, let score?): result = "\(name) won \(score)"
        case (_, _, let score?): result = "In progress · \(score)"
        default: result = "No score recorded"
        }
        var body = ""
        if document.sample != nil {
            body += #"<p class="badge" role="note">Sample · demo data, not real play</p>"#
        }
        body += "<header><h1>\(escape(document.title))</h1><p class=\"meta\">\(escape(dateText(document.createdAt)))</p>"
        body += "<p class=\"result\">\(escape(result))\(match.provisional ? " · provisional" : "")</p></header>"
        body += "<section aria-labelledby=\"stats\"><h2 id=\"stats\">Match stats</h2><table><thead><tr><th scope=\"col\">Stat</th>"
        body += "<th scope=\"col\">\(escape(a))</th><th scope=\"col\">\(escape(b))</th></tr></thead><tbody>"
        for row in rows {
            let left = byKey[StatKey(stat: row.stat, side: .a)], right = byKey[StatKey(stat: row.stat, side: .b)]
            body += "<tr><th scope=\"row\">\(escape(row.label))"
            if let note = row.note { body += "<span class=\"note\">\(escape(note))</span>" }
            body += "</th><td>\(cell(left))</td><td>\(cell(right))</td></tr>"
        }
        if let shots = byKey[StatKey(stat: "shots.total")] {
            body += "<tr><th scope=\"row\">Shots<span class=\"note\">Racket contacts in live play</span></th>"
            body += "<td colspan=\"2\">\(cell(shots))</td></tr>"
        }
        body += "</tbody></table>"
        if let review = reviewText(byKey[StatKey(stat: "review.completion")]) { body += "<p class=\"review\">\(escape(review))</p>" }
        body += "<p class=\"foot\">Percentages are whole numbers rounded half up, with the fraction beside them. A dash means nothing to count yet.</p></section>"
        body += "<section aria-labelledby=\"clips\"><h2 id=\"clips\">Clips</h2>"
        if clips.isEmpty {
            body += "<p class=\"empty\">No clips in this pack. The score, stats and points.csv are here.</p>"
        } else {
            body += "<ol class=\"clips\">"
            for clip in clips {
                body += "<li><a href=\"\(escape(clip.path))\">\(escape(clip.title))</a>"
                if let note = clip.note, !note.isEmpty { body += "<p>\(escape(note))</p>" }
                body += "</li>"
            }
            body += "</ol>"
        }
        body += "</section><section aria-labelledby=\"data\"><h2 id=\"data\">Data</h2><ul class=\"files\">"
        body += "<li><a href=\"match.json\">match.json</a> · the full session record</li>"
        let pointCount = selectedCount ?? rendered.pointRows.count
        body += "<li><a href=\"points.csv\">points.csv</a> · \(pointCount == 1 ? "1 point" : "\(pointCount) points")\(selectedCount == nil ? "" : " chosen for you")</li></ul></section>"
        body += "<footer>Made with JOVRA · Contact hello@islanddevcrew.com</footer>"
        return page(title: document.title, body: body)
    }

    private static func cell(_ stat: DerivedStat?) -> String {
        guard let stat, let value = stat.value else { return "<span class=\"value\">—</span>" }
        var text: String
        switch value {
        case .count(let n): text = "<span class=\"value\">\(n)</span>"
        case .ratio(let r):
            text = "<span class=\"value\">\(escape(r.display))</span>"
            if r.d > 0 { text += " <span class=\"fraction\">\(r.n) / \(r.d)</span>" }
        }
        if let tag = provenanceText(stat.evidence) { text += "<span class=\"source\">\(escape(tag))</span>" }
        return text
    }

    /// Manual, reviewed and validated numbers carry no per-cell tag (the review line under the table covers them);
    /// an estimate always says so, with its unreviewed count (story 368).
    private static func provenanceText(_ evidence: StatEvidence) -> String? {
        guard evidence.provenance == .estimated else { return nil }
        let n = evidence.unreviewedCount
        return n == 0 ? "Estimated" : "Estimated · includes \(n) unreviewed \(n == 1 ? "point" : "points")"
    }

    private static func reviewText(_ review: DerivedStat?) -> String? {
        guard case .ratio(let r)? = review?.value, r.d > 0 else { return nil }
        let open = r.d - r.n
        if open == 0 { return "All \(r.d) points reviewed." }
        return "\(open) of \(r.d) points \(open == 1 ? "is" : "are") not yet reviewed, so these numbers can still change."
    }

    private static func dateText(_ timestamp: String) -> String {
        let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
                      "November", "December"]
        guard let day = try? CalendarDay(String(timestamp.prefix(10))) else { return "" }
        return "\(months[day.month - 1]) \(day.day), \(day.year)"
    }

    static func escape(_ text: String) -> String {
        var out = ""
        for ch in text {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(ch)
            }
        }
        return out
    }

    private static func page(title: String, body: String) -> String {
        """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="referrer" content="no-referrer">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src 'self'; media-src 'self'">
        <title>\(escape(title)) · JOVRA</title>
        <style>
        :root{--bg:#F4F1E8;--surface:#FBFAF6;--ink:#182F29;--ink2:#4D5853;--line:#DCD7CA;--accent:#4C6610;--editorial:#092A25;--on-editorial:#F4F1E8;--chartreuse:#D7F56A}
        @media (prefers-color-scheme:dark){:root{--bg:#092A25;--surface:#123C33;--ink:#F4F1E8;--ink2:#B4C2BB;--line:#25544A;--accent:#D7F56A;--editorial:#123C33}}
        *{box-sizing:border-box}
        body{margin:0;background:var(--bg);color:var(--ink);font:1rem/1.5 -apple-system,system-ui,"Segoe UI",Roboto,sans-serif;padding:24px 16px 48px}
        main{max-width:720px;margin:0 auto}
        header{background:var(--editorial);color:var(--on-editorial);border-radius:20px;padding:24px;margin-bottom:24px}
        h1{font-size:clamp(1.75rem,1.2rem + 2.5vw,2.5rem);line-height:1.1;margin:0 0 4px;letter-spacing:-.01em}
        h2{font-size:1.125rem;margin:32px 0 12px}
        .meta{margin:0;opacity:.8}
        .result{margin:16px 0 0;font-size:1.25rem;font-weight:600;color:var(--chartreuse)}
        .badge{display:inline-block;margin:0 0 12px;padding:4px 12px;border-radius:999px;border:1.5px solid var(--ink);font-weight:600;font-size:.875rem}
        table{width:100%;border-collapse:collapse;background:var(--surface);border-radius:16px;overflow:hidden}
        th,td{text-align:left;padding:12px 14px;border-bottom:1px solid var(--line);vertical-align:top}
        thead th{font-size:.8125rem;text-transform:uppercase;letter-spacing:.06em;color:var(--ink2)}
        tbody th{font-weight:500}
        tbody tr:last-child th,tbody tr:last-child td{border-bottom:0}
        .value{font-weight:700;font-variant-numeric:tabular-nums}
        .fraction{color:var(--ink2);font-variant-numeric:tabular-nums;white-space:nowrap}
        .note,.source{display:block;font-size:.8125rem;color:var(--ink2);font-weight:400}
        .source{color:var(--accent)}
        .foot,.empty{color:var(--ink2);font-size:.875rem}
        .review{margin:12px 0 0;font-weight:600}
        .clips,.files{padding-left:20px}
        .clips li,.files li{margin:8px 0}
        a{color:var(--accent);text-underline-offset:3px}
        a:focus-visible{outline:3px solid var(--accent);outline-offset:2px;border-radius:4px}
        footer{margin-top:40px;color:var(--ink2);font-size:.875rem}
        @media (max-width:480px){th,td{padding:10px 8px}}
        </style>
        </head>
        <body><main>
        \(body)
        </main></body>
        </html>

        """
    }
}
