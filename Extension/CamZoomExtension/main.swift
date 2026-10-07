@preconcurrency import CoreMediaIO
import Foundation

// 카메라 익스텐션 진입점. macOS가 화상 앱의 요청에 따라 띄운다.
let providerSource = ExtensionProviderSource(clientQueue: nil)
CMIOExtensionProvider.startService(provider: providerSource.provider)
CFRunLoopRun()
