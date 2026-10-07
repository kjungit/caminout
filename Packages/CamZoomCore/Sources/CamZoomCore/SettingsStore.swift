import Foundation
import os

/// 설정·프리셋을 `Application Support/CamZoom/` 아래 JSON 파일로 저장한다 (설계서 8.2, ADR-09).
///
/// - `settings.json`: 현재 상태 전체. 변경 후 0.5초 동안 추가 변경이 없으면 한 번에 쓴다.
/// - `presets/<id>.json`: 프리셋 하나당 파일 하나.
/// - 해석에 실패한 파일은 `.broken`을 붙여 옮겨 두고 기본값으로 시작한다. 설정 파일 때문에 앱이 죽지 않게 하기 위해서다.
public final class SettingsStore: @unchecked Sendable {

    public static let folderName = "CamZoom"
    public static let settingsFileName = "settings.json"
    public static let presetsFolderName = "presets"

    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(folderName, isDirectory: true)
    }

    public let directory: URL
    public let saveDelay: TimeInterval

    // 파일 입출력은 전부 이 큐에서만 한다. pendingSave도 이 큐에서만 읽고 쓴다.
    private let ioQueue = DispatchQueue(label: "com.kjungit.caminout.settings-io", qos: .utility)
    private var pendingSave: DispatchWorkItem?
    private var pendingSettings: AppSettings?
    private let logger = Logger(subsystem: "com.kjungit.caminout", category: "settings")

    public init(directory: URL = SettingsStore.defaultDirectory, saveDelay: TimeInterval = 0.5) {
        self.directory = directory
        self.saveDelay = saveDelay
    }

    public var settingsURL: URL { directory.appendingPathComponent(Self.settingsFileName) }
    public var presetsDirectory: URL { directory.appendingPathComponent(Self.presetsFolderName, isDirectory: true) }

    // MARK: - settings.json

    /// 저장된 설정을 읽는다. 파일이 없으면 기본값, 깨져 있으면 `.broken`으로 옮기고 기본값.
    public func load() -> AppSettings {
        ioQueue.sync { loadLocked() }
    }

    /// 0.5초 뒤에 저장한다. 그 사이에 다시 부르면 마지막 값만 저장된다.
    public func scheduleSave(_ settings: AppSettings) {
        ioQueue.async { [self] in
            pendingSave?.cancel()
            pendingSettings = settings
            let work = DispatchWorkItem { [self] in
                writePendingLocked()
            }
            pendingSave = work
            ioQueue.asyncAfter(deadline: .now() + saveDelay, execute: work)
        }
    }

    /// 예약된 저장을 즉시 실행한다. 앱 종료 직전에 부른다.
    public func flush() {
        ioQueue.sync { writePendingLocked() }
    }

    /// 바로 저장한다.
    public func saveNow(_ settings: AppSettings) {
        ioQueue.sync {
            pendingSave?.cancel()
            pendingSave = nil
            pendingSettings = nil
            writeLocked(settings)
        }
    }

    // MARK: - presets

    public func loadPresets() -> [Preset] {
        ioQueue.sync {
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: presetsDirectory, includingPropertiesForKeys: nil
            )) ?? []
            return urls
                .filter { $0.pathExtension == "json" }
                .compactMap { url -> Preset? in
                    do {
                        let data = try SettingsMigration.migrate(Data(contentsOf: url), to: Preset.currentSchemaVersion)
                        return try JSONDecoder().decode(Preset.self, from: data)
                    } catch {
                        quarantine(url, error: error)
                        return nil
                    }
                }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    public func save(_ preset: Preset) {
        ioQueue.sync {
            write(preset, to: presetsDirectory.appendingPathComponent("\(preset.id.uuidString).json"))
        }
    }

    public func deletePreset(id: UUID) {
        ioQueue.sync {
            try? FileManager.default.removeItem(at: presetsDirectory.appendingPathComponent("\(id.uuidString).json"))
        }
    }

    // MARK: - 내부

    private func loadLocked() -> AppSettings {
        let url = settingsURL
        guard FileManager.default.fileExists(atPath: url.path) else { return AppSettings() }
        do {
            let data = try SettingsMigration.migrate(Data(contentsOf: url))
            var settings = try JSONDecoder().decode(AppSettings.self, from: data)
            settings.schemaVersion = AppSettings.currentSchemaVersion
            settings.crop = settings.crop.sanitized
            return settings
        } catch {
            quarantine(url, error: error)
            return AppSettings()
        }
    }

    private func writePendingLocked() {
        pendingSave?.cancel()
        pendingSave = nil
        guard let settings = pendingSettings else { return }
        pendingSettings = nil
        writeLocked(settings)
    }

    private func writeLocked(_ settings: AppSettings) {
        write(settings, to: settingsURL)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(value).write(to: url, options: .atomic)
        } catch {
            logger.error("설정 저장 실패 \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func quarantine(_ url: URL, error: Error) {
        let broken = url.appendingPathExtension("broken")
        try? FileManager.default.removeItem(at: broken)
        try? FileManager.default.moveItem(at: url, to: broken)
        logger.error("설정 파일 해석 실패, \(broken.lastPathComponent, privacy: .public)로 옮김: \(String(describing: error), privacy: .public)")
    }
}
