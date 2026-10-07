import AppKit
import Foundation

if let i=CommandLine.arguments.firstIndex(of:"--camera-review-test"),i+1<CommandLine.arguments.count {
    do {try runCameraReviewTests(URL(fileURLWithPath:CommandLine.arguments[i+1]),realReview:i+2<CommandLine.arguments.count ? URL(fileURLWithPath:CommandLine.arguments[i+2]):nil);exit(0)} catch {fputs("FAIL: \(error.localizedDescription)\n",stderr);exit(1)}
}
if let i=CommandLine.arguments.firstIndex(of:"--v6-test"),i+2<CommandLine.arguments.count {
    do {try runVersionSixTests(URL(fileURLWithPath:CommandLine.arguments[i+1]),reported:URL(fileURLWithPath:CommandLine.arguments[i+2]));exit(0)} catch {fputs("FAIL: \(error.localizedDescription)\n",stderr);exit(1)}
}
if let i=CommandLine.arguments.firstIndex(of:"--v5-test"),i+2<CommandLine.arguments.count {
    do {try runVersionFiveTests(URL(fileURLWithPath:CommandLine.arguments[i+1]),reported:URL(fileURLWithPath:CommandLine.arguments[i+2]));exit(0)} catch {fputs("FAIL: \(error.localizedDescription)\n",stderr);exit(1)}
}
if let i=CommandLine.arguments.firstIndex(of:"--v4-test"),i+1<CommandLine.arguments.count {
    do {try runVersionFourTests(URL(fileURLWithPath:CommandLine.arguments[i+1]));exit(0)} catch {fputs("FAIL: \(error.localizedDescription)\n",stderr);exit(1)}
}
if let i=CommandLine.arguments.firstIndex(of:"--global-test"),i+1<CommandLine.arguments.count {
    do {try runGlobalTests(URL(fileURLWithPath:CommandLine.arguments[i+1]));exit(0)} catch {fputs("FAIL: \(error.localizedDescription)\n",stderr);exit(1)}
}
if let i=CommandLine.arguments.firstIndex(of:"--caption-test"),i+1<CommandLine.arguments.count {
    do {try runCaptionTests(base:URL(fileURLWithPath:CommandLine.arguments[i+1]));exit(0)} catch {fputs("FAIL: \(error.localizedDescription)\n",stderr);exit(1)}
}
if CommandLine.arguments.contains("--sample-workflow") {
    do {try sampleWorkflow();exit(0)} catch {fputs("FAIL: \(error.localizedDescription)\n",stderr);exit(1)}
}

if CommandLine.arguments.contains("--self-test") {
    do { try runSelfTests(); exit(0) } catch { fputs("FAIL: \(error.localizedDescription)\n",stderr); exit(1) }
}
let app=NSApplication.shared
app.setActivationPolicy(.regular)
let delegate=AppDelegate()
app.delegate=delegate
app.run()
