public func makeSimpleLineDiff(
    old: String,
    new: String,
    oldName: String,
    newName: String
) -> String {
    let oldLines = old.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    let newLines = new.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

    var i = 0, j = 0
    var out: [String] = []
    out.append("--- \(oldName)")
    out.append("+++ \(newName)")

    while i < oldLines.count || j < newLines.count {
        if i < oldLines.count && j < newLines.count && oldLines[i] == newLines[j] {
            // unchanged line: skip to keep diff concise; uncomment to show:
            // out.append("   \(oldLines[i])")
            i += 1; j += 1
        } else if j + 1 < newLines.count, i < oldLines.count, oldLines[i] == newLines[j + 1] {
            // insertion
            out.append(" + \(newLines[j])")
            j += 1
        } else if i + 1 < oldLines.count, j < newLines.count, oldLines[i + 1] == newLines[j] {
            // deletion
            out.append(" - \(oldLines[i])")
            i += 1
        } else {
            // change (replace one line with another)
            if i < oldLines.count { out.append(" - \(oldLines[i])"); i += 1 }
            if j < newLines.count { out.append(" + \(newLines[j])"); j += 1 }
        }
    }
    return out.joined(separator: "\n")
}
