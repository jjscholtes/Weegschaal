import Foundation
import SwiftData
import SwiftUI

// MARK: - Design tokens (MFP-inspired)

extension Color {
    static let appBlauw    = Color(red: 0/255,   green: 114/255, blue: 188/255)  // #0072BC
    static let vetKleur    = Color(red: 255/255, green: 69/255,  blue: 58/255)   // #FF453A
    static let waterKleur  = Color(red: 0/255,   green: 114/255, blue: 188/255)  // blauw
    static let spierKleur  = Color(red: 48/255,  green: 209/255, blue: 88/255)   // #30D158
    static let botKleur    = Color(red: 175/255, green: 82/255,  blue: 222/255)  // #AF52DE
}

// MARK: - SwiftData model

@Model
final class Meting {
    var id: UUID = UUID()
    var datum: Date
    var gewicht: Double          // kg
    var vetpercentage: Double?   // %
    var waterpercentage: Double? // %
    var spierpercentage: Double? // %
    var botmassa: Double?        // kg equivalent
    var kcal: Int?
    var bmi: Double?
    var persoonId: Int
    var weegschaalBronId: String?
    var gesynchroniseerdMetHealth: Bool = false
    var healthSyncId: String?
    var healthGesynchroniseerdeTypeIds: String?
    var healthSyncDatum: Date?

    init(datum: Date, gewicht: Double, persoonId: Int) {
        self.datum = datum
        self.gewicht = gewicht
        self.persoonId = persoonId
    }

    var heeftLichaamssamenstelling: Bool {
        vetpercentage != nil
    }
}

// MARK: - Tussentijdse data van de weegschaal (vóór opslag in SwiftData)

struct MetingData: Equatable {
    var datum: Date
    var gewicht: Double
    var persoonId: Int
    var vetpercentage: Double?
    var waterpercentage: Double?
    var spierpercentage: Double?
    var botmassa: Double?
    var kcal: Int?
}

extension Meting {
    static func maakWeegschaalBronId(datum: Date, gewicht: Double, persoonId: Int) -> String {
        let timestamp = Int(datum.timeIntervalSince1970.rounded())
        let gewichtCode = Int((gewicht * 10).rounded())
        return "\(persoonId)-\(timestamp)-\(gewichtCode)"
    }

    var fallbackWeegschaalBronId: String {
        weegschaalBronId ?? Self.maakWeegschaalBronId(datum: datum, gewicht: gewicht, persoonId: persoonId)
    }
}

extension MetingData {
    var weegschaalBronId: String {
        Meting.maakWeegschaalBronId(datum: datum, gewicht: gewicht, persoonId: persoonId)
    }
}

enum VerwijderdeWeegschaalMetingen {
    private static let storageKey = "verwijderdeWeegschaalBronIds"

    static func laad() -> Set<String> {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let ids = try? JSONDecoder().decode(Set<String>.self, from: data)
        else {
            return []
        }
        return ids
    }

    static func voegToe(_ bronId: String) {
        var ids = laad()
        ids.insert(bronId)
        slaOp(ids)
    }

    private static func slaOp(_ ids: Set<String>) {
        guard let data = try? JSONEncoder().encode(ids) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

// MARK: - Gebruikersprofiel (opgeslagen in UserDefaults)

struct Profiel: Codable {
    static let storageKey = "profielData"
    private static let legacyStorageKey = "profiel"

    var persoonId: Int = 1
    var lengte: Int = 175        // cm
    var leeftijd: Int = 30
    var geslacht: Geslacht = .man

    enum Geslacht: Int, Codable, CaseIterable, Identifiable {
        case man = 1, vrouw = 2
        var id: Int { rawValue }
        var naam: String { self == .man ? "Man" : "Vrouw" }
    }

    var lenteMeter: Double { Double(lengte) / 100.0 }

    func berekenBMI(gewicht: Double) -> Double {
        let h = lenteMeter
        guard h > 0 else { return 0 }
        return gewicht / (h * h)
    }

    static func laden() -> Profiel {
        let defaults = UserDefaults.standard

        if let data = defaults.data(forKey: storageKey),
           let profiel = try? JSONDecoder().decode(Profiel.self, from: data) {
            return profiel
        }

        if let legacyData = defaults.data(forKey: legacyStorageKey),
           let profiel = try? JSONDecoder().decode(Profiel.self, from: legacyData) {
            if let migratedData = try? JSONEncoder().encode(profiel) {
                defaults.set(migratedData, forKey: storageKey)
            }
            defaults.removeObject(forKey: legacyStorageKey)
            return profiel
        }

        return Profiel()
    }

    func opslaan() {
        if let data = try? JSONEncoder().encode(self) {
            let defaults = UserDefaults.standard
            defaults.set(data, forKey: Self.storageKey)
            defaults.removeObject(forKey: Self.legacyStorageKey)
        }
    }
}

// MARK: - Trend- en outlieranalyse

enum MetingAnalyse {
    static func metingenVoorProfiel(_ metingen: [Meting], persoonId: Int) -> [Meting] {
        metingen
            .filter { $0.persoonId == persoonId }
            .sorted { $0.datum < $1.datum }
    }

    static func trendDelta(metingen: [Meting], dagen: Int) -> Double? {
        let gesorteerd = metingen.sorted { $0.datum < $1.datum }
        guard let laatste = gesorteerd.last else { return nil }
        guard let startDatum = Calendar.current.date(byAdding: .day, value: -dagen, to: laatste.datum) else {
            return nil
        }

        guard let eersteInPeriode = gesorteerd.first(where: { $0.datum >= startDatum && $0.id != laatste.id }) else {
            return nil
        }

        return laatste.gewicht - eersteInPeriode.gewicht
    }

    static func outlierIds(metingen: [Meting]) -> Set<UUID> {
        let gesorteerd = metingen.sorted { $0.datum < $1.datum }
        guard gesorteerd.count >= 2 else { return [] }

        var ids: Set<UUID> = []
        for index in 1..<gesorteerd.count {
            let vorige = gesorteerd[index - 1]
            let huidige = gesorteerd[index]

            let verschil = abs(huidige.gewicht - vorige.gewicht)
            let dagen = max(huidige.datum.timeIntervalSince(vorige.datum) / 86_400, 0.0001)
            let relatief = vorige.gewicht > 0 ? verschil / vorige.gewicht : 0

            let grootAbsoluutVerschil = verschil >= 2.5
            let grootRelatiefVerschil = relatief >= 0.04 && verschil >= 1.5
            if dagen <= 3.0 && (grootAbsoluutVerschil || grootRelatiefVerschil) {
                ids.insert(huidige.id)
            }
        }

        return ids
    }
}

// MARK: - BMI helpers

extension Double {
    var bmiCategorie: String {
        switch self {
        case ..<18.5: return "Ondergewicht"
        case 18.5..<25: return "Normaal"
        case 25..<30: return "Overgewicht"
        default: return "Obesitas"
        }
    }

    var bmiKleur: Color {
        switch self {
        case ..<18.5: return .blue
        case 18.5..<25: return .green
        case 25..<30: return .orange
        default: return .red
        }
    }
}
