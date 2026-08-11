import AudioToolbox
import UIKit

// System Sound Services rather than AVAudioPlayer: this is a short alert, so it needs
// no audio session of its own, and it follows the ring/silent switch like a message tone
enum MessageSound {
    static let enabledDefaultsKey = "soundEffectsEnabled"

    private static let soundId: SystemSoundID = {
        let url = Bundle.main.url(forResource: "message", withExtension: "caf")!
        var soundId: SystemSoundID = 0
        AudioServicesCreateSystemSoundID(url as CFURL, &soundId)
        return soundId
    }()

    // read rather than stored, so the setting takes effect on the next sound instead of
    // the next launch. bool(forKey:) is no good here: unset has to mean on, not off
    private static var enabled: Bool {
        UserDefaults.standard.object(forKey: enabledDefaultsKey) as? Bool ?? true
    }

    static func playIfForeground() {
        guard enabled, UIApplication.shared.applicationState == .active else { return }
        AudioServicesPlaySystemSound(soundId)
    }
}
