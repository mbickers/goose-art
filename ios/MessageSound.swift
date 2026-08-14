import AVFAudio
import UIKit

enum MessageSound {
    static let enabledDefaultsKey = "soundEffectsEnabled"

    // AVAudioPlayer on a .playback session rather than System Sound Services: a system sound
    // is muted by the ring/silent switch, and this sound is app audio the user asked for.
    // .mixWithOthers so it lands over whatever else is playing instead of pausing it
    private static let player: AVAudioPlayer = {
        try! AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        let url = Bundle.main.url(forResource: "message", withExtension: "caf")!
        let player = try! AVAudioPlayer(contentsOf: url)
        player.prepareToPlay()
        return player
    }()

    private static var enabled: Bool {
        UserDefaults.standard.object(forKey: enabledDefaultsKey) as? Bool ?? true
    }

    static func playIfForeground() {
        guard enabled, UIApplication.shared.applicationState == .active else { return }
        player.currentTime = 0
        player.play()
    }
}
