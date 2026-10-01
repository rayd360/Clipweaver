import Foundation
import AVFoundation

extension Engine {
    /// Produce a full-resolution editing intermediate from the original HDR source.
    /// Apple performs tone mapping before the final SDR encodes, never from an AI review copy.
    func editingSource(_ source: SourceClip, temporaryFolder: URL, job: JobControl) throws -> SourceClip {
        guard source.media.hdr else { return source }
        try job.check()
        let input = AVURLAsset(url: URL(fileURLWithPath:source.originalPath))
        guard let session = AVAssetExportSession(asset:input,presetName:AVAssetExportPresetAppleProRes422LPCM) else { throw WeaverError("This Mac could not prepare HDR footage for editing.") }
        let composition = AVMutableVideoComposition(propertiesOf:input)
        composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        composition.renderSize = CGSize(width:source.media.width,height:source.media.height)
        let parts = source.media.fps.split(separator:"/").compactMap {Int32($0)}
        composition.frameDuration = parts.count == 2 ? CMTime(value:CMTimeValue(parts[1]),timescale:parts[0]) : CMTime(seconds:1/source.media.fpsValue,preferredTimescale:600000)
        session.videoComposition = composition
        session.timeRange = CMTimeRange(start:CMTime(seconds:max(0,source.media.videoStart),preferredTimescale:600000),duration:CMTime(seconds:source.media.duration,preferredTimescale:600000))
        try fm.createDirectory(at:temporaryFolder,withIntermediateDirectories:true)
        let output = temporaryFolder.appendingPathComponent("\(source.id)-SDR.mov")
        session.outputURL = output; session.outputFileType = .mov
        session.shouldOptimizeForNetworkUse = false
        let done = DispatchSemaphore(value:0)
        session.exportAsynchronously {done.signal()}
        while done.wait(timeout:.now()+0.2) == .timedOut {
            do {try job.check()} catch {session.cancelExport();throw error}
        }
        try job.check()
        guard session.status == .completed else {throw WeaverError("HDR conversion failed for \(source.filename): \(session.error?.localizedDescription ?? "Unknown conversion error")")}
        let media = try probe(output,tools:tools,job:job)
        guard !media.hdr, media.width == source.media.width, media.height == source.media.height, abs(media.fpsValue-source.media.fpsValue)<0.02, abs(media.duration-source.media.duration)<max(0.15,2/source.media.fpsValue) else {throw WeaverError("HDR preparation did not preserve the source dimensions, frame rate, or timeline.")}
        var result = source; result.originalPath=output.path; result.media=media
        return result
    }
}
