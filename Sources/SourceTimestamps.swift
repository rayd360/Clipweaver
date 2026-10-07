import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SourceTimestamp: Identifiable {
    var number: Int
    var filename: String
    var reviewFilename: String
    var start: Double
    var end: Double
    var note: String?
    var id: Int { number }
    var duration: Double { end - start }
}

extension Project {
    func sourceTimestamps(for edit: EditPlan) throws -> [SourceTimestamp] {
        try edit.validate(self)
        return try edit.clips.enumerated().map { index, clip in
            if let source = sources.first(where: { $0.id == clip.sourceId }) {
                return SourceTimestamp(number: index + 1, filename: source.timestampFilename, reviewFilename: source.filename, start: clip.start, end: clip.end, note: clip.note)
            }
            guard let master = combinedMasters?.first(where: { $0.source.id == clip.sourceId }),
                  let part = master.parts.first(where: { clip.start >= $0.start - 0.000001 && clip.start < $0.end - 0.000001 && clip.end <= $0.end + 0.000001 }) else {
                throw WeaverError("Could not map this selection to its original source file.")
            }
            let source = sources.first(where: { $0.id == part.sourceId })
            return SourceTimestamp(number: index + 1, filename: source?.timestampFilename ?? part.filename, reviewFilename: source?.filename ?? part.filename, start: max(0, clip.start - part.start), end: clip.end - part.start, note: clip.note)
        }
    }
    func sourceTimestampText(for edit: EditPlan) throws -> String {
        let rows = try sourceTimestamps(for: edit)
        var lines = ["Source timestamps — \(edit.title)", "Elapsed time in each original file. End time is exclusive."]
        if usesCameraReviews { lines.append("Use the OSV filenames and these times in DJI Studio. LRF files are camera previews.") }
        lines.append("")
        for row in rows {
            lines.append("\(row.number). \(row.filename) | \(clockText(row.start)) → \(clockText(row.end)) | \(num(row.start))–\(num(row.end)) seconds")
            if let note = row.note, !note.isEmpty { lines.append("   \(note)") }
        }
        return lines.joined(separator: "\n") + "\n"
    }
    func sourceTimestampCSV(for edit: EditPlan) throws -> String {
        func quoted(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let rows = try sourceTimestamps(for: edit)
        let header = "Selection,Choice,Original file,Review file,Start time,End time,Start seconds,End seconds,Duration seconds,Activity note"
        return ([header] + rows.map { row in
            [String(row.number), quoted(edit.title), quoted(row.filename), quoted(row.reviewFilename), clockText(row.start), clockText(row.end), num(row.start), num(row.end), num(row.duration), quoted(row.note ?? "")].joined(separator: ",")
        }).joined(separator: "\r\n") + "\r\n"
    }
}

extension Studio {
    var selectedSourceTimestamps: [SourceTimestamp] {
        guard let project, let plan else { return [] }
        return (try? project.sourceTimestamps(for: plan)) ?? []
    }
    func copySourceTimestamps() {
        guard let project, let plan else { return }
        do {
            let text = try project.sourceTimestampText(for: plan)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            status = "Source timestamps copied for \(plan.title)"
        } catch { self.error = error.localizedDescription }
    }
    func saveSourceTimestamps() {
        guard let project, let plan else { return }
        do {
            let csv = try project.sourceTimestampCSV(for: plan)
            let panel = NSSavePanel()
            panel.title = "Save source timestamps"
            panel.allowedContentTypes = [.commaSeparatedText]
            panel.nameFieldStringValue = cleanName(plan.title) + " — timestamps.csv"
            guard panel.runModal() == .OK, let destination = panel.url else { return }
            try csv.write(to: destination, atomically: true, encoding: .utf8)
            status = "Source timestamps saved: \(destination.lastPathComponent)"
        } catch { self.error = error.localizedDescription }
    }
    func prepareChoicePreviews() {
        if project?.usesCameraReviews == true { status = "Source timestamps ready. Select a choice below; build previews if you want to watch the selections." }
        else { renderChoices() }
    }
}

extension StudioView {
    var sourceTimestampsPanel: some View {
        card {
            label("SOURCE TIMESTAMPS")
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.plan?.title ?? "Selected moments").font(.title2)
                    Text(model.project?.usesCameraReviews == true ? "Find these OSV files and time ranges in DJI Studio. Each file starts at 00:00:00; end time is exclusive." : "These times refer to each original file, including selections from a combined review. End time is exclusive.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    Button("Copy timestamps", action: model.copySourceTimestamps)
                    Button("Save timestamps…", action: model.saveSourceTimestamps)
                }.disabled(model.selectedSourceTimestamps.isEmpty)
            }
            ForEach(model.selectedSourceTimestamps) { row in
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(row.number). \(row.filename)").font(.headline).textSelection(.enabled)
                    HStack(spacing: 24) {
                        Text("Start  \(clockText(row.start))")
                        Text("End  \(clockText(row.end))")
                        Text("Length  \(clockText(row.duration))").foregroundStyle(.secondary)
                    }.font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    if let note = row.note, !note.isEmpty { Text(note).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(Color.white.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
