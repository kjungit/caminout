import CamZoomShared
@preconcurrency import CoreMediaIO
import Foundation

/// 화상 앱이 읽는 스트림.
final class SourceStreamSource: NSObject, CMIOExtensionStreamSource, @unchecked Sendable {

    private(set) var stream: CMIOExtensionStream!
    let formats: [CMIOExtensionStreamFormat]
    private unowned let owner: ExtensionDeviceSource
    private let lock = NSLock()
    private var _activeFormatIndex = 0

    init(localizedName: String, streamID: UUID, formats: [CMIOExtensionStreamFormat], owner: ExtensionDeviceSource) {
        self.formats = formats
        self.owner = owner
        super.init()
        stream = CMIOExtensionStream(
            localizedName: localizedName,
            streamID: streamID,
            direction: .source,
            clockType: .hostTime,
            source: self
        )
    }

    var activeFormatIndex: Int {
        get { lock.withLock { _activeFormatIndex } }
        set {
            guard formats.indices.contains(newValue) else { return }
            lock.withLock { _activeFormatIndex = newValue }
            let dims = CMVideoFormatDescriptionGetDimensions(formats[newValue].formatDescription)
            owner.sourceFormatDidChange(OutputFormat(width: dims.width, height: dims.height))
        }
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.streamActiveFormatIndex, .streamFrameDuration]
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let streamProperties = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) {
            streamProperties.activeFormatIndex = activeFormatIndex
        }
        if properties.contains(.streamFrameDuration) {
            streamProperties.frameDuration = OutputFormat.frameDuration
        }
        return streamProperties
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {
        if let index = streamProperties.activeFormatIndex {
            activeFormatIndex = index
        }
    }

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        true
    }

    func startStream() throws {
        owner.sourceDidStart()
    }

    func stopStream() throws {
        owner.sourceDidStop()
    }
}

/// 호스트 앱이 프레임을 넣는 스트림.
final class SinkStreamSource: NSObject, CMIOExtensionStreamSource, @unchecked Sendable {

    private(set) var stream: CMIOExtensionStream!
    let formats: [CMIOExtensionStreamFormat]
    private unowned let owner: ExtensionDeviceSource
    private let lock = NSLock()
    private var client: CMIOExtensionClient?
    private var _activeFormatIndex = 0

    init(localizedName: String, streamID: UUID, formats: [CMIOExtensionStreamFormat], owner: ExtensionDeviceSource) {
        self.formats = formats
        self.owner = owner
        super.init()
        stream = CMIOExtensionStream(
            localizedName: localizedName,
            streamID: streamID,
            direction: .sink,
            clockType: .hostTime,
            source: self
        )
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.streamActiveFormatIndex, .streamFrameDuration, .streamSinkBufferQueueSize,
         .streamSinkBuffersRequiredForStartup, .streamSinkBufferUnderrunCount, .streamSinkEndOfData]
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let streamProperties = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) {
            streamProperties.activeFormatIndex = lock.withLock { _activeFormatIndex }
        }
        if properties.contains(.streamFrameDuration) {
            streamProperties.frameDuration = OutputFormat.frameDuration
        }
        // 큐가 길면 지연이 쌓인다. 앱은 큐가 차면 프레임을 버린다.
        if properties.contains(.streamSinkBufferQueueSize) {
            streamProperties.sinkBufferQueueSize = 3
        }
        if properties.contains(.streamSinkBuffersRequiredForStartup) {
            streamProperties.sinkBuffersRequiredForStartup = 1
        }
        return streamProperties
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {
        if let index = streamProperties.activeFormatIndex, formats.indices.contains(index) {
            lock.withLock { _activeFormatIndex = index }
        }
    }

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        lock.withLock { self.client = client }
        return true
    }

    func startStream() throws {
        guard let client = lock.withLock({ self.client }) else { return }
        owner.sinkDidStart(client: client)
    }

    func stopStream() throws {
        lock.withLock { client = nil }
        owner.sinkDidStop()
    }
}
