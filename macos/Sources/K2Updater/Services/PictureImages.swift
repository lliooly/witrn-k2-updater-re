import Foundation
import CoreGraphics
import K2Core

struct ImageImport: Identifiable {
    let id = UUID()
    let source: CGImage
    let kind: PictureResource
}
