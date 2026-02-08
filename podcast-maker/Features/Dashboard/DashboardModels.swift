import Foundation

enum DashboardSection: String, CaseIterable, Identifiable {
    case recording
    case podcast
    case settings
    case logs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recording: return "録音"
        case .podcast: return "Podcast"
        case .settings: return "設定"
        case .logs: return "ログ"
        }
    }

    var symbol: String {
        switch self {
        case .recording: return "waveform"
        case .podcast: return "music.note.house"
        case .settings: return "gearshape"
        case .logs: return "doc.plaintext"
        }
    }
}

struct DocumentRow: Identifiable {
    let id: URL
    let url: URL
    let displayTitle: String
    let metadata: DocumentMetadata

    var audioURL: URL {
        url.appendingPathComponent("audio.wav")
    }
}
