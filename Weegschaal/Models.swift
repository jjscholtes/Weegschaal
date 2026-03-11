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
    var gesynchroniseerdMetHealth: Bool = false

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

// MARK: - Gebruikersprofiel (opgeslagen in UserDefaults)

struct Profiel: Codable {
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
        guard let data = UserDefaults.standard.data(forKey: "profiel"),
              let profiel = try? JSONDecoder().decode(Profiel.self, from: data)
        else { return Profiel() }
        return profiel
    }

    func opslaan() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "profiel")
        }
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
