import XCTest
@testable import CamZoomCore

final class SettingsStoreTests: XCTestCase {

    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CamZoomCoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore(delay: TimeInterval = 0.05) -> SettingsStore {
        SettingsStore(directory: directory, saveDelay: delay)
    }

    func testLoadWithoutFileReturnsDefault() {
        XCTAssertEqual(makeStore().load(), AppSettings())
    }

    func testSaveThenLoadReturnsSameValues() {
        let store = makeStore()
        var settings = AppSettings()
        settings.crop = CropState(zoom: 2.5, centerX: 0.3, centerY: 0.7, aspect: .square, mirrored: true, rotation: .right)
        settings.output.fitMode = .fill
        settings.output.input = .colorBars
        settings.preferences.appearance = .dark

        store.saveNow(settings)

        XCTAssertEqual(makeStore().load(), settings)
    }

    func testScheduledSaveKeepsOnlyLastValueAndFlushWrites() {
        let store = makeStore(delay: 10)
        var settings = AppSettings()
        settings.crop.zoom = 2
        store.scheduleSave(settings)
        settings.crop.zoom = 3
        store.scheduleSave(settings)

        XCTAssertFalse(FileManager.default.fileExists(atPath: store.settingsURL.path))
        store.flush()

        XCTAssertEqual(makeStore().load().crop.zoom, 3)
    }

    func testScheduledSaveWritesAfterDelay() {
        let store = makeStore(delay: 0.05)
        var settings = AppSettings()
        settings.crop.zoom = 4
        store.scheduleSave(settings)

        let deadline = Date().addingTimeInterval(2)
        while !FileManager.default.fileExists(atPath: store.settingsURL.path), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertEqual(makeStore().load().crop.zoom, 4)
    }

    func testBrokenFileIsQuarantinedAndDefaultsReturned() throws {
        let store = makeStore()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: store.settingsURL)

        XCTAssertEqual(store.load(), AppSettings())
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.settingsURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.settingsURL.appendingPathExtension("broken").path))
    }

    func testMissingFieldsFallBackToDefaultsAndUnknownFieldsAreIgnored() throws {
        let store = makeStore()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let json = #"{"schemaVersion":1,"crop":{"zoom":2.2,"aspect":"square"},"futureField":{"x":1}}"#
        try Data(json.utf8).write(to: store.settingsURL)

        let settings = store.load()

        XCTAssertEqual(settings.crop.zoom, 2.2)
        XCTAssertEqual(settings.crop.aspect, .square)
        XCTAssertEqual(settings.crop.centerX, 0.5)
        XCTAssertEqual(settings.crop.rotation, .none)
        XCTAssertEqual(settings.output, OutputSettings())
    }

    func testOutOfRangeValuesAreSanitizedOnLoad() throws {
        let store = makeStore()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"schemaVersion":1,"crop":{"zoom":99,"centerX":-3}}"#.utf8).write(to: store.settingsURL)

        let crop = store.load().crop
        XCTAssertEqual(crop.zoom, CropState.zoomRange.upperBound)
        XCTAssertEqual(crop.centerX, 0)
    }

    func testPresetsRoundTripAndDelete() {
        let store = makeStore()
        let a = Preset(name: "눈코 확대", crop: CropState(zoom: 2.2, aspect: .square))
        let b = Preset(name: "기본", crop: CropState())
        store.save(a)
        store.save(b)

        XCTAssertEqual(store.loadPresets().map(\.name), ["기본", "눈코 확대"])

        store.deletePreset(id: a.id)
        XCTAssertEqual(store.loadPresets(), [b])
    }
}

final class SettingsMigrationTests: XCTestCase {

    func testCurrentVersionPassesThrough() throws {
        let data = Data(#"{"schemaVersion":1,"crop":{"zoom":2}}"#.utf8)
        let migrated = try SettingsMigration.migrate(data)
        let settings = try JSONDecoder().decode(AppSettings.self, from: migrated)
        XCTAssertEqual(settings.crop.zoom, 2)
    }

    func testOlderVersionIsRaisedToTarget() throws {
        let data = Data(#"{"schemaVersion":0}"#.utf8)
        let migrated = try SettingsMigration.migrate(data, to: 1)
        let json = try JSONSerialization.jsonObject(with: migrated) as? [String: Any]
        XCTAssertEqual(json?["schemaVersion"] as? Int, 1)
    }

    func testMissingVersionThrows() {
        XCTAssertThrowsError(try SettingsMigration.migrate(Data(#"{"crop":{}}"#.utf8)))
    }
}
