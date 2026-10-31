import Darwin
import Foundation

setbuf(stdout, nil)

struct SmokeFailure: Error { let message: String }
let ffmpeg = ProcessInfo.processInfo.environment["PULLR_TEST_FFMPEG"] ?? "/opt/homebrew/bin/ffmpeg"
let ffprobe = URL(fileURLWithPath: ffmpeg).deletingLastPathComponent().appendingPathComponent("ffprobe").path
let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Pullr-HEVC-smoke-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }

func run(_ executable: String, _ arguments: [String]) throws -> Data {
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw SmokeFailure(message: String(decoding: output, as: UTF8.self))
    }
    return output
}

func download(paths: [URL], liveURL: String? = nil, encoder: String = ffmpeg) throws -> String {
    let service = YTDLPService(), finished = DispatchSemaphore(value: 0)
    var result: Result<YTDLPResult, Error>?, finalPath: String?
    let executable: String, arguments: [String]
    if let liveURL {
        let request = DownloadCommandRequest(url: liveURL, preset: ExportPreset.defaultPresets[0], outputFolder: directory.path, namingTemplate: "youtube-smoke.%(ext)s", playlistOptions: PlaylistOptions(), ffmpegPath: ffmpeg, advancedArguments: ["--no-playlist", "--socket-timeout", "20", "--retries", "1"])
        executable = URL(fileURLWithPath: ffmpeg).deletingLastPathComponent().appendingPathComponent("yt-dlp").path
        arguments = try CommandBuilder.buildArguments(for: request)
    } else {
        executable = "/bin/echo"
        arguments = [paths.map { YTDLPService.outputPathPrefix + $0.path }.joined(separator: "\n")]
    }
    service.start(ytDLPPath: executable, arguments: arguments, hevcFFmpegPath: encoder, eventHandler: { event in
        if case .outputPath(let path) = event { finalPath = path }
        if case .log(let line) = event, liveURL != nil { print(line) }
    }, completion: { value in result = value; finished.signal() })
    guard finished.wait(timeout: .now() + (liveURL == nil ? 15 : 180)) == .success else {
        service.cancel()
        throw SmokeFailure(message: "Download or conversion timed out")
    }
    guard let result, try result.get().exitCode == 0, let finalPath else {
        throw SmokeFailure(message: "Download did not complete with a final output path")
    }
    return finalPath
}

func verifyHTTPDownload(source: URL) throws {
    let server = Process(), portPipe = Pipe()
    server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    server.arguments = ["-u", "-c", "import http.server,functools,sys; s=http.server.ThreadingHTTPServer(('127.0.0.1',0),functools.partial(http.server.SimpleHTTPRequestHandler,directory=sys.argv[1])); print(s.server_port,flush=True); s.serve_forever()", directory.path]
    server.standardOutput = portPipe
    server.standardError = FileHandle.nullDevice
    try server.run()
    defer {
        server.terminate()
        server.waitUntilExit()
    }
    var line = Data()
    while let byte = try portPipe.fileHandleForReading.read(upToCount: 1), !byte.isEmpty, byte[0] != 10 { line.append(byte) }
    guard let port = Int(String(decoding: line, as: UTF8.self)) else { throw SmokeFailure(message: "Local fixture server did not start") }
    try verifyHEVC(download(paths: [], liveURL: "http://127.0.0.1:\(port)/\(source.lastPathComponent)"))
    print("Real local HTTP download through yt-dlp and H.265 conversion passed.")
}

func verifyCancellation(source: URL) throws {
    let original = try Data(contentsOf: source)
    let wrapper = directory.appendingPathComponent("slow-ffmpeg")
    try "#!/bin/sh\nexec '\(ffmpeg.replacingOccurrences(of: "'", with: "'\\''"))' -re \"$@\"\n".write(to: wrapper, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: wrapper.path)
    let service = YTDLPService(), done = DispatchSemaphore(value: 0), started = DispatchSemaphore(value: 0)
    var result: Result<YTDLPResult, Error>?
    service.start(ytDLPPath: "/bin/echo", arguments: [YTDLPService.outputPathPrefix + source.path], hevcFFmpegPath: wrapper.path, eventHandler: { event in
        if case .status(.converting) = event {
            DispatchQueue.global().async {
                for _ in 0..<200 {
                    if ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).contains(where: { $0.hasPrefix(".pullr-hevc-") }) {
                        started.signal()
                        service.cancel()
                        return
                    }
                    Thread.sleep(forTimeInterval: 0.01)
                }
                service.cancel()
            }
        }
    }, completion: { value in result = value; done.signal() })
    guard done.wait(timeout: .now() + 5) == .success,
          started.wait(timeout: .now()) == .success,
          case .failure(let error as YTDLPServiceError) = result,
          case .cancelled = error,
          try Data(contentsOf: source) == original
    else { service.cancel(); throw SmokeFailure(message: "Cancelling a real conversion must promptly preserve the original source") }
    print("Real ffmpeg conversion cancellation preserved every source byte.")
}

func verifyKeptPlaylistCancellation(paths: [URL]) throws {
    let service = YTDLPService(), done = DispatchSemaphore(value: 0)
    var keptCount = 0, result: Result<YTDLPResult, Error>?
    service.start(ytDLPPath: "/bin/echo", arguments: [paths.map { YTDLPService.outputPathPrefix + $0.path }.joined(separator: "\n")], hevcFFmpegPath: "/usr/bin/false", eventHandler: { event in
        if case .log(let line) = event, line.hasPrefix("Keeping existing H.265") {
            keptCount += 1
            if keptCount == 1 { service.cancel() }
        }
    }, completion: { value in result = value; done.signal() })
    guard done.wait(timeout: .now() + 5) == .success,
          case .failure(let error as YTDLPServiceError) = result,
          case .cancelled = error,
          keptCount == 1
    else { service.cancel(); throw SmokeFailure(message: "Cancelled HEVC playlist continued inspecting later entries") }
    print("Cancellation stops an already-HEVC playlist before the next entry.")
}

func verifyHEVC(_ path: String) throws {
    let data = try run(ffprobe, ["-v", "error", "-show_entries", "stream=codec_name,codec_tag_string", "-of", "json", path])
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let streams = json["streams"] as? [[String: Any]],
          streams.contains(where: { $0["codec_name"] as? String == "hevc" && $0["codec_tag_string"] as? String == "hvc1" }),
          streams.contains(where: { $0["codec_name"] as? String == "aac" })
    else { throw SmokeFailure(message: "Output must contain H.265/hvc1 video and AAC audio") }
    print("Verified H.265/hvc1 video + AAC audio: \(path)")
}

do {
    if let liveURL = ProcessInfo.processInfo.environment["PULLR_TEST_YOUTUBE_URL"] {
        try verifyHEVC(download(paths: [], liveURL: liveURL))
    } else {
        let source = directory.appendingPathComponent("MP4 ü 'quoted'.mp4")
        _ = try run(ffmpeg, ["-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc2=size=320x180:rate=24", "-f", "lavfi", "-i", "sine=frequency=440", "-t", "0.6", "-c:v", "libx264", "-c:a", "aac", source.path])
        let httpSource = directory.appendingPathComponent("http-source.mp4")
        try FileManager.default.copyItem(at: source, to: httpSource)
        let cancelSource = directory.appendingPathComponent("cancel-source.mp4")
        try FileManager.default.copyItem(at: source, to: cancelSource)
        let hardwareOutput = directory.appendingPathComponent("hardware-only.mp4")
        var hardwareArguments = YTDLPService.hevcArguments(input: source.path, output: hardwareOutput.path)
        hardwareArguments[hardwareArguments.firstIndex(of: "-allow_sw")! + 1] = "0"
        _ = try run(ffmpeg, hardwareArguments)
        try verifyHEVC(hardwareOutput.path)
        print("Hardware-only VideoToolbox encoding passed with software fallback disabled.")
        let other = directory.appendingPathComponent("second.mkv")
        _ = try run(ffmpeg, ["-hide_banner", "-loglevel", "error", "-i", source.path, "-c", "copy", other.path])
        let final = try download(paths: [source, other])
        try verifyHEVC(source.path)
        try verifyHEVC(final)
        guard !FileManager.default.fileExists(atPath: other.path) else { throw SmokeFailure(message: "Converted MKV should be replaced by its MP4") }
        let encoded = try Data(contentsOf: source)
        _ = try download(paths: [source], encoder: "/usr/bin/false")
        guard try Data(contentsOf: source) == encoded else { throw SmokeFailure(message: "An existing H.265 MP4 was needlessly re-encoded") }
        print("Existing H.265 MP4 retained byte-for-byte without an encoder invocation.")
        try verifyKeptPlaylistCancellation(paths: [source, hardwareOutput, URL(fileURLWithPath: final)])
        try verifyHTTPDownload(source: httpSource)
        try verifyCancellation(source: cancelSource)

        let invalid = directory.appendingPathComponent("invalid.mp4")
        let original = Data("invalid source fixture".utf8)
        try original.write(to: invalid)
        do {
            _ = try download(paths: [invalid])
            throw SmokeFailure(message: "Invalid video unexpectedly succeeded")
        } catch YTDLPServiceError.conversionFailed {
            guard try Data(contentsOf: invalid) == original else { throw SmokeFailure(message: "Failed conversion changed the source") }
        }
        guard !(try FileManager.default.contentsOfDirectory(atPath: directory.path)).contains(where: { $0.hasPrefix(".pullr-hevc-") }) else {
            throw SmokeFailure(message: "Conversion left partial temporary files")
        }
        print("Playlist outputs, MP4 replacement, quoted paths, failure preservation, and cleanup passed.")
    }
} catch {
    print("HEVC smoke failed: \(error)")
    try? FileManager.default.removeItem(at: directory)
    exit(1)
}
