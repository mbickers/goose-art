import AudioToolbox
import UIKit

// System Sound Services rather than AVAudioPlayer: this is a short alert, so it needs
// no audio session of its own, and it follows the ring/silent switch like a message tone
enum MessageSound {
    private static let soundId: SystemSoundID = {
        let url = Bundle.main.url(forResource: "message", withExtension: "caf")!
        var soundId: SystemSoundID = 0
        AudioServicesCreateSystemSoundID(url as CFURL, &soundId)
        return soundId
    }()

    static func playIfForeground() {
        guard UIApplication.shared.applicationState == .active else { return }
        AudioServicesPlaySystemSound(soundId)
    }
}
