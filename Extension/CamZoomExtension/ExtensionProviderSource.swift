import CamZoomShared
@preconcurrency import CoreMediaIO
import Foundation

/// 익스텐션의 최상위 객체. 장치 하나를 등록한다.
final class ExtensionProviderSource: NSObject, CMIOExtensionProviderSource, @unchecked Sendable {

    private(set) var provider: CMIOExtensionProvider!
    private var deviceSource: ExtensionDeviceSource!

    init(clientQueue: DispatchQueue?) {
        super.init()
        provider = CMIOExtensionProvider(source: self, clientQueue: clientQueue)
        deviceSource = ExtensionDeviceSource(localizedName: CameraIdentity.deviceName)
        do {
            try provider.addDevice(deviceSource.device)
        } catch {
            fatalError("가상 카메라 장치를 등록하지 못했습니다: \(error)")
        }
    }

    func connect(to client: CMIOExtensionClient) throws {}

    func disconnect(from client: CMIOExtensionClient) {}

    var availableProperties: Set<CMIOExtensionProperty> {
        [.providerManufacturer]
    }

    func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
        let providerProperties = CMIOExtensionProviderProperties(dictionary: [:])
        if properties.contains(.providerManufacturer) {
            providerProperties.manufacturer = CameraIdentity.manufacturer
        }
        return providerProperties
    }

    func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {}
}
