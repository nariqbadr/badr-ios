import Foundation
import SwiftUI
#if canImport(AlarmKit)
import AlarmKit
#endif

/// «يرنّ حتى في الصامت»: on iOS 26 the adhan at each prayer is also a system alarm (AlarmKit) with the chosen adhan's sound,
/// which rings through the silent switch and Focus, stopped with one tap — the next two days, set again each time the app opens.
enum SilentAlarms {
    private static let key = "silentAlarmIds"

    @MainActor static func authorize() async -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            let m = AlarmManager.shared
            switch m.authorizationState {
            case .authorized: return true
            case .denied: return false
            default: break
            }
            return (try? await m.requestAuthorization()) == .authorized
        }
        #endif
        return false
    }

    /// replaces the app's alarms with these prayers' (none = all taken away)
    @MainActor static func sync(_ list: [PrayerTime]) {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            let m = AlarmManager.shared
            let old = (UserDefaults.standard.stringArray(forKey: key) ?? []).compactMap(UUID.init(uuidString:))
            for id in old { try? m.cancel(id: id) }
            guard !list.isEmpty, m.authorizationState == .authorized else { UserDefaults.standard.set([String](), forKey: key); return }
            var ids: [String] = []
            for p in list {
                let id = UUID()
                let alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: tr("حان الآن موعد صلاة {0}", p.name)),
                                                    stopButton: AlarmButton(text: LocalizedStringResource(stringLiteral: tr("إيقاف")), textColor: .white, systemImageName: "stop.circle"))
                let attrs = AlarmAttributes<AdhanAlarm>(presentation: AlarmPresentation(alert: alert), metadata: AdhanAlarm(prayer: p.key), tintColor: Color(red: 0.79, green: 0.64, blue: 0.36))
                let sound = Adhan.soundName(p.key == "fajr") ?? "adhan.caf"
                let cfg = AlarmManager.AlarmConfiguration<AdhanAlarm>(schedule: .fixed(p.time), attributes: attrs, sound: .named(sound))
                Task { _ = try? await m.schedule(id: id, configuration: cfg) }
                ids.append(id.uuidString)
            }
            UserDefaults.standard.set(ids, forKey: key)
        }
        #endif
    }
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
struct AdhanAlarm: AlarmMetadata { var prayer: String }
#endif
