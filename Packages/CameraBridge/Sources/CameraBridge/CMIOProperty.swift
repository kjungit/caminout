import CoreMediaIO
import Foundation

/// CMIO C API 속성 읽기 도우미.
enum CMIOProperty {

    static func address(_ selector: UInt32, scope: UInt32 = UInt32(kCMIOObjectPropertyScopeGlobal)) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(selector),
            mScope: CMIOObjectPropertyScope(scope),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
    }

    static func has(_ object: CMIOObjectID, _ selector: UInt32) -> Bool {
        var addr = address(selector)
        return CMIOObjectHasProperty(object, &addr)
    }

    /// 배열 값 (장치 목록, 스트림 목록 등).
    static func objectIDs(_ object: CMIOObjectID, _ selector: UInt32) -> [CMIOObjectID] {
        var addr = address(selector)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(object, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<CMIOObjectID>.size
        var ids = [CMIOObjectID](repeating: 0, count: count)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(object, &addr, 0, nil, size, &used, &ids) == noErr else { return [] }
        return Array(ids.prefix(Int(used) / MemoryLayout<CMIOObjectID>.size))
    }

    static func uint32(_ object: CMIOObjectID, _ selector: UInt32) -> UInt32? {
        var addr = address(selector)
        guard CMIOObjectHasProperty(object, &addr) else { return nil }
        var value: UInt32 = 0
        var used: UInt32 = 0
        let status = CMIOObjectGetPropertyData(object, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &value)
        return status == noErr ? value : nil
    }

    /// 문자열 값. 기본 속성(장치 UID)과 익스텐션의 사용자 정의 속성 모두 CFString으로 온다.
    static func string(_ object: CMIOObjectID, _ selector: UInt32) -> String? {
        var addr = address(selector)
        guard CMIOObjectHasProperty(object, &addr) else { return nil }
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(object, &addr, 0, nil, &size) == noErr, size > 0 else { return nil }
        var value: Unmanaged<CFString>?
        var used: UInt32 = 0
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            CMIOObjectGetPropertyData(object, &addr, 0, nil, size, &used, pointer)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
