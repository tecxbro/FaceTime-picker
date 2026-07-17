#if !os(macOS)
import Foundation

@main
struct UnsupportedPlatformMain {
  static func main() {
    FileHandle.standardError.write(Data("FaceTimePicker can only run on macOS.\n".utf8))
    exit(1)
  }
}
#endif
