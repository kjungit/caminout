import CamZoomShared
import CoreMediaIO
import Foundation

/// 시스템에 설치된 우리 가상 카메라의 CMIO 객체 ID.
public struct VirtualCameraDevice: Equatable, Sendable {
    public let deviceID: CMIOObjectID
    public let sinkStreamID: CMIOStreamID
    public let sourceStreamID: CMIOStreamID?
}

public enum VirtualCameraLocator {

    /// CamZoomShared에 정해 둔 장치 UID로 가상 카메라를 찾고, 그 장치의 sink 스트림을 고른다 (설계서 6장 앱 쪽 1번).
    public static func find(uid: String = CameraIdentity.deviceUID) -> VirtualCameraDevice? {
        let devices = CMIOProperty.objectIDs(CMIOObjectID(kCMIOObjectSystemObject), UInt32(kCMIOHardwarePropertyDevices))
        guard let device = devices.first(where: {
            CMIOProperty.string($0, UInt32(kCMIODevicePropertyDeviceUID)) == uid
        }) else { return nil }

        let streams = CMIOProperty.objectIDs(device, UInt32(kCMIODevicePropertyStreams))
        guard !streams.isEmpty else { return nil }

        // 방향 1 = 장치로 들어가는 스트림(sink), 0 = 장치에서 나가는 스트림(source).
        let directions = streams.map { CMIOProperty.uint32($0, UInt32(kCMIOStreamPropertyDirection)) }
        let sink = zip(streams, directions).first(where: { $0.1 == 1 })?.0
            ?? (streams.count > 1 ? streams[1] : nil)
        let source = zip(streams, directions).first(where: { $0.1 == 0 })?.0 ?? streams.first
        guard let sink else { return nil }
        return VirtualCameraDevice(deviceID: device, sinkStreamID: sink, sourceStreamID: source == sink ? nil : source)
    }

    /// 시스템의 모든 카메라 장치 이름과 UID. 진단용.
    public static func allDevices() -> [(name: String, uid: String)] {
        CMIOProperty.objectIDs(CMIOObjectID(kCMIOObjectSystemObject), UInt32(kCMIOHardwarePropertyDevices)).map {
            (
                CMIOProperty.string($0, UInt32(kCMIOObjectPropertyName)) ?? "?",
                CMIOProperty.string($0, UInt32(kCMIODevicePropertyDeviceUID)) ?? "?"
            )
        }
    }
}
