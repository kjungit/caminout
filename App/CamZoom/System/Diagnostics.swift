import CamZoomCore
import CamZoomShared
import Foundation
import MetricKit
import os
import OSLog

/// MetricKit 진단을 받아 기기 안에 JSON으로 남긴다 (G13).
///
/// 분석 SDK나 서버 전송은 쓰지 않는다. 사용자가 "진단 정보 내보내기"로 직접 묶어서 첨부한다.
/// MetricKit은 하루에 한 번 정도, 앱이 다음에 실행될 때 지난 진단을 넘겨준다.
final class DiagnosticsCollector: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let folderName = "Diagnostics"
    /// 오래된 파일부터 지워 이 개수만 남긴다.
    static let maxFiles = 30

    static var defaultDirectory: URL {
        SettingsStore.defaultDirectory.appendingPathComponent(folderName, isDirectory: true)
    }

    let directory: URL
    // 파일 쓰기는 이 큐에서만 한다. MetricKit 콜백은 임의의 스레드에서 온다.
    private let ioQueue = DispatchQueue(label: "com.kjungit.caminout.diagnostics", qos: .utility)
    private let logger = Logger(subsystem: "com.kjungit.caminout", category: "diagnostics")

    init(directory: URL = DiagnosticsCollector.defaultDirectory) {
        self.directory = directory
        super.init()
    }

    func start() {
        MXMetricManager.shared.add(self)
        // 구독 전에 도착해 있던 진단도 남긴다.
        didReceive(MXMetricManager.shared.pastDiagnosticPayloads)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            save(payload.jsonRepresentation(), kind: "diagnostic", ending: payload.timeStampEnd)
        }
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            save(payload.jsonRepresentation(), kind: "metric", ending: payload.timeStampEnd)
        }
    }

    private func save(_ json: Data, kind: String, ending: Date) {
        ioQueue.async { [self] in
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let stamp = ISO8601DateFormatter.fileSafe.string(from: ending)
                let url = directory.appendingPathComponent("\(kind)-\(stamp).json")
                try json.write(to: url, options: .atomic)
                logger.info("MetricKit \(kind, privacy: .public) 저장: \(url.lastPathComponent, privacy: .public)")
                prune()
            } catch {
                logger.error("MetricKit \(kind, privacy: .public) 저장 실패: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// ioQueue.
    private func prune() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        guard files.count > Self.maxFiles else { return }
        let sorted = files.sorted { modified($0) > modified($1) }
        for url in sorted.dropFirst(Self.maxFiles) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}

/// 지원 요청에 첨부할 진단 묶음(zip)을 만든다 (설계서 2장 로그, G13).
///
/// 담는 것: 앱 정보, 설정 파일, 이번 실행의 앱 로그, MetricKit 진단. 영상·이미지는 담지 않는다.
/// 홈 폴더 경로는 `~`로 바꿔 맥 사용자 이름이 들어가지 않게 한다 (개인정보 처리 방침).
enum DiagnosticsExporter {
    static let logSubsystemPrefix = "com.kjungit.caminout"

    /// `summary`는 주 스레드에서 모은 앱 상태 텍스트. 로그 읽기와 압축은 오래 걸릴 수 있어 주 스레드 밖에서 부른다.
    static func export(summary: String, to destination: URL) throws {
        let fm = FileManager.default
        let stamp = ISO8601DateFormatter.fileSafe.string(from: Date())
        let staging = fm.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("\(CameraIdentity.productName)-진단-\(stamp)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging.deletingLastPathComponent()) }

        try writeMasked(summary, to: staging.appendingPathComponent("info.txt"))
        try writeMasked(appLog(), to: staging.appendingPathComponent("app-log.txt"))

        let settings = SettingsStore.defaultDirectory.appendingPathComponent(SettingsStore.settingsFileName)
        if let text = try? String(contentsOf: settings, encoding: .utf8) {
            try writeMasked(text, to: staging.appendingPathComponent(SettingsStore.settingsFileName))
        }
        let diagnostics = DiagnosticsCollector.defaultDirectory
        let payloads = (try? fm.contentsOfDirectory(at: diagnostics, includingPropertiesForKeys: nil)) ?? []
        if !payloads.isEmpty {
            let folder = staging.appendingPathComponent(DiagnosticsCollector.folderName, isDirectory: true)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            for url in payloads {
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                try writeMasked(text, to: folder.appendingPathComponent(url.lastPathComponent))
            }
        }

        try zip(staging, to: destination)
    }

    /// 홈 폴더 경로를 `~`로 바꾼다. JSON은 `/`를 `\/`로 적으므로 그 형태도 바꾼다.
    static func maskingHome(_ text: String, home: String = NSHomeDirectory()) -> String {
        guard home.count > 1 else { return text }
        let escaped = home.replacingOccurrences(of: "/", with: "\\/")
        return text
            .replacingOccurrences(of: home, with: "~")
            .replacingOccurrences(of: escaped, with: "~")
    }

    private static func writeMasked(_ text: String, to url: URL) throws {
        try maskingHome(text).write(to: url, atomically: true, encoding: .utf8)
    }

    /// 이번 실행 동안의 앱 로그. 다른 프로세스(익스텐션) 로그는 관리자 권한이 있어야 읽을 수 있어 넣지 않는다.
    static func appLog() throws -> String {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let entries = try store.getEntries(
            at: store.position(timeIntervalSinceLatestBoot: 0),
            matching: NSPredicate(format: "subsystem BEGINSWITH %@", logSubsystemPrefix)
        )
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var lines: [String] = []
        for case let entry as OSLogEntryLog in entries {
            lines.append("\(formatter.string(from: entry.date)) [\(entry.category)] \(entry.level.label) \(entry.composedMessage)")
        }
        return lines.isEmpty ? "(로그 없음)\n" : lines.joined(separator: "\n") + "\n"
    }

    /// 폴더를 zip으로 묶는다. NSFileCoordinator의 업로드용 읽기가 임시 zip을 만들어 준다.
    private static func zip(_ folder: URL, to destination: URL) throws {
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinationError) { zipURL in
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: zipURL, to: destination)
            } catch {
                copyError = error
            }
        }
        if let error = coordinationError ?? copyError { throw error }
    }
}

private extension OSLogEntryLog.Level {
    var label: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .notice: return "NOTICE"
        case .error: return "ERROR"
        case .fault: return "FAULT"
        case .undefined: return "-"
        @unknown default: return "-"
        }
    }
}

private extension ISO8601DateFormatter {
    /// 파일 이름에 쓸 수 있는 형식 (콜론 없음).
    static var fileSafe: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
        formatter.timeZone = .current
        return formatter
    }
}
