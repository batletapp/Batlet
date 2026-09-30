import AppKit

/// Plays the same bundled tones used by battery notifications.
@MainActor
final class AlertSoundPlayer {
    static let shared = AlertSoundPlayer()

    private var activeSound: NSSound?

    private init() {}

    @discardableResult
    func play(_ choice: AlertSound) -> Bool {
        activeSound?.stop()
        activeSound = nil

        guard let fileName = choice.fileName else {
            NSSound.beep()
            return true
        }
        guard let url = Self.url(for: fileName),
              let sound = NSSound(contentsOf: url, byReference: true)
        else {
            NSSound.beep()
            return false
        }
        activeSound = sound
        return sound.play()
    }

    static func url(for fileName: String) -> URL? {
        let name = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        return Bundle.main.url(forResource: name, withExtension: ext)
            ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Sounds")
    }
}
