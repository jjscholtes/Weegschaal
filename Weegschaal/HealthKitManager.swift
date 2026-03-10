import HealthKit
import Foundation
import Combine

enum HealthKitFout: LocalizedError {
    case nietBeschikbaar
    case geenToestemming
    case onvoldoendeToestemmingVoorBijwerken
    case verwijderenMislukt

    var errorDescription: String? {
        switch self {
        case .nietBeschikbaar:
            return "Apple Health is niet beschikbaar op dit apparaat. Gebruik een fysieke iPhone."
        case .geenToestemming:
            return "Geen toegang tot Apple Health. Geef schrijf-toegang in de Gezondheid-app of Instellingen."
        case .onvoldoendeToestemmingVoorBijwerken:
            return "Niet alle eerder gesynchroniseerde Apple Health-metrics zijn nog geautoriseerd. Geef opnieuw volledige toegang om deze meting te bewerken of verwijderen."
        case .verwijderenMislukt:
            return "Bestaande Apple Health-data kon niet worden bijgewerkt."
        }
    }
}

enum HealthKitStatus: Equatable {
    case nietBeschikbaar
    case nietBepaald
    case geweigerd
    case gedeeltelijk
    case geautoriseerd

    var label: String {
        switch self {
        case .nietBeschikbaar: return "Niet beschikbaar"
        case .nietBepaald: return "Nog niet gevraagd"
        case .geweigerd: return "Geweigerd"
        case .gedeeltelijk: return "Gedeeltelijk"
        case .geautoriseerd: return "Actief"
        }
    }

    var detail: String {
        switch self {
        case .nietBeschikbaar:
            return "Apple Health is niet beschikbaar op dit apparaat."
        case .nietBepaald:
            return "Toestemming voor schrijven van metingen is nog niet gevraagd."
        case .geweigerd:
            return "Toegang geweigerd. Zet rechten aan in de Gezondheid-app of Instellingen."
        case .gedeeltelijk:
            return "Slechts een deel van de HealthKit schrijftypes is geautoriseerd."
        case .geautoriseerd:
            return "Alle gekoppelde metingen kunnen naar Apple Health worden geschreven."
        }
    }
}

final class HealthKitManager: ObservableObject {
    private let store = HKHealthStore()
    private let syncMetadataKey = "weegschaal.measurement.id"

    @Published var isGeautoriseerd = false
    @Published private(set) var status: HealthKitStatus = .nietBepaald

    private let schrijfTypeIds: [HKQuantityTypeIdentifier] = [
        .bodyMass,
        .bodyMassIndex,
        .bodyFatPercentage,
        .leanBodyMass
    ]

    private var schrijfTypes: Set<HKSampleType> {
        Set(schrijfTypeIds.compactMap { HKObjectType.quantityType(forIdentifier: $0) })
    }

    init() {
        controleerAutorisatie()
    }

    var isHealthKitBeschikbaar: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func verversStatus() {
        controleerAutorisatie()
    }

    private func controleerAutorisatie() {
        guard isHealthKitBeschikbaar else {
            isGeautoriseerd = false
            status = .nietBeschikbaar
            return
        }

        let statussen = schrijfTypeIds.compactMap { id -> HKAuthorizationStatus? in
            guard let type = HKObjectType.quantityType(forIdentifier: id) else { return nil }
            return store.authorizationStatus(for: type)
        }

        let aantalAuthorized = statussen.filter { $0 == .sharingAuthorized }.count
        let aantalDenied = statussen.filter { $0 == .sharingDenied }.count

        if aantalAuthorized == statussen.count, !statussen.isEmpty {
            status = .geautoriseerd
            isGeautoriseerd = true
        } else if aantalAuthorized > 0 {
            status = .gedeeltelijk
            isGeautoriseerd = true
        } else if aantalDenied == 0 && aantalAuthorized == 0 {
            status = .nietBepaald
            isGeautoriseerd = false
        } else if aantalDenied > 0 {
            status = .geweigerd
            isGeautoriseerd = false
        } else {
            status = .gedeeltelijk
            isGeautoriseerd = false
        }
    }

    func vraagAutorisatie(completion: @escaping (Bool, String?) -> Void) {
        guard isHealthKitBeschikbaar else {
            isGeautoriseerd = false
            completion(false, HealthKitFout.nietBeschikbaar.localizedDescription)
            return
        }

        store.requestAuthorization(toShare: schrijfTypes, read: schrijfTypes) { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.controleerAutorisatie()

                if let error = error {
                    completion(false, error.localizedDescription)
                    return
                }

                if success, self.isGeautoriseerd {
                    completion(true, nil)
                } else {
                    completion(false, HealthKitFout.geenToestemming.localizedDescription)
                }
            }
        }
    }

    func vraagAutorisatie(completion: @escaping (Bool) -> Void) {
        vraagAutorisatie { success, _ in
            completion(success)
        }
    }

    func synchroniseer(meting: Meting, profiel: Profiel, completion: @escaping (Bool, Error?) -> Void) {
        guard isHealthKitBeschikbaar else {
            completion(false, HealthKitFout.nietBeschikbaar)
            return
        }
        guard isGeautoriseerd else {
            completion(false, HealthKitFout.geenToestemming)
            return
        }

        let syncId = meting.healthSyncId ?? meting.id.uuidString
        let identifiers = identifiersVoorSynchronisatie(van: meting)
        let geautoriseerdeIdentifiers = identifiers.filter { schrijfStatus(for: $0) == .sharingAuthorized }
        let metadata: [String: Any] = [
            syncMetadataKey: syncId,
            HKMetadataKeySyncIdentifier: syncId,
            HKMetadataKeySyncVersion: 1
        ]

        var samples: [HKQuantitySample] = []

        if geautoriseerdeIdentifiers.contains(.bodyMass) {
            let gewichtSample = HKQuantitySample(
                type: HKQuantityType(.bodyMass),
                quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: meting.gewicht),
                start: meting.datum,
                end: meting.datum,
                metadata: metadata
            )
            samples.append(gewichtSample)
        }

        let bmi = meting.bmi ?? profiel.berekenBMI(gewicht: meting.gewicht)
        if bmi > 0, geautoriseerdeIdentifiers.contains(.bodyMassIndex) {
            let bmiSample = HKQuantitySample(
                type: HKQuantityType(.bodyMassIndex),
                quantity: HKQuantity(unit: .count(), doubleValue: bmi),
                start: meting.datum,
                end: meting.datum,
                metadata: metadata
            )
            samples.append(bmiSample)
        }

        if let vet = meting.vetpercentage, geautoriseerdeIdentifiers.contains(.bodyFatPercentage) {
            let vetSample = HKQuantitySample(
                type: HKQuantityType(.bodyFatPercentage),
                quantity: HKQuantity(unit: .percent(), doubleValue: vet / 100.0),
                start: meting.datum,
                end: meting.datum,
                metadata: metadata
            )
            samples.append(vetSample)
        }

        if let vet = meting.vetpercentage, geautoriseerdeIdentifiers.contains(.leanBodyMass) {
            let leanMass = meting.gewicht * (1.0 - vet / 100.0)
            let leanSample = HKQuantitySample(
                type: HKQuantityType(.leanBodyMass),
                quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: leanMass),
                start: meting.datum,
                end: meting.datum,
                metadata: metadata
            )
            samples.append(leanSample)
        }

        guard !samples.isEmpty else {
            completion(false, HealthKitFout.geenToestemming)
            return
        }

        let slaOp: () -> Void = { [weak self] in
            self?.store.save(samples) { success, error in
                DispatchQueue.main.async {
                    if success {
                        meting.healthSyncId = syncId
                        meting.healthGesynchroniseerdeTypeIds = geautoriseerdeIdentifiers.map(\.rawValue).joined(separator: ",")
                        meting.healthSyncDatum = meting.datum
                        meting.gesynchroniseerdMetHealth = true
                    }
                    completion(success, error)
                }
            }
        }

        if heeftBestaandeHealthData(voor: meting) {
            let identifiersVoorUpdate = identifiersVoorVerwijderen(van: meting)
            guard heeftVolledigeSchrijftoestemming(voor: identifiersVoorUpdate) else {
                completion(false, HealthKitFout.onvoldoendeToestemmingVoorBijwerken)
                return
            }

            verwijderGesynchroniseerdeData(voor: meting) { success, error in
                if success {
                    slaOp()
                } else {
                    completion(false, error)
                }
            }
            return
        }

        slaOp()
    }

    func verwijderGesynchroniseerdeData(voor meting: Meting, completion: @escaping (Bool, Error?) -> Void) {
        guard isHealthKitBeschikbaar else {
            completion(false, HealthKitFout.nietBeschikbaar)
            return
        }

        let identifiers = identifiersVoorVerwijderen(van: meting)
        guard !identifiers.isEmpty else {
            completion(true, nil)
            return
        }

        guard heeftVolledigeSchrijftoestemming(voor: identifiers) else {
            completion(false, HealthKitFout.onvoldoendeToestemmingVoorBijwerken)
            return
        }

        let syncDatum = meting.healthSyncDatum ?? meting.datum
        let legacyPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(from: HKSource.default()),
            HKQuery.predicateForSamples(
                withStart: syncDatum.addingTimeInterval(-1),
                end: syncDatum.addingTimeInterval(1),
                options: [.strictStartDate]
            )
        ])

        let predicate: NSPredicate
        if let syncId = meting.healthSyncId {
            let metadataPredicate = HKQuery.predicateForObjects(withMetadataKey: syncMetadataKey, allowedValues: [syncId])
            predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [metadataPredicate, legacyPredicate])
        } else {
            predicate = legacyPredicate
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var eersteFout: Error?

        for identifier in identifiers {
            guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { continue }
            group.enter()
            store.deleteObjects(of: type, predicate: predicate) { success, _, error in
                if !success {
                    lock.lock()
                    if eersteFout == nil {
                        eersteFout = error ?? HealthKitFout.verwijderenMislukt
                    }
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            if let eersteFout {
                completion(false, eersteFout)
                return
            }

            meting.gesynchroniseerdMetHealth = false
            meting.healthGesynchroniseerdeTypeIds = nil
            meting.healthSyncId = nil
            meting.healthSyncDatum = nil
            completion(true, nil)
        }
    }

    // Sync sequentieel om SwiftData threading-problemen te vermijden.
    // De aanroeper is verantwoordelijk voor het bijwerken van gesynchroniseerdMetHealth.
    func synchroniseerAlle(
        metingen: [Meting],
        profiel: Profiel,
        onEen: @escaping (Meting, Bool) -> Void,
        completion: @escaping (_ aantalGelukt: Int, _ totaal: Int) -> Void
    ) {
        let teSynchroniseren = metingen.filter { !$0.gesynchroniseerdMetHealth }
        guard !teSynchroniseren.isEmpty else {
            completion(0, 0)
            return
        }

        syncVolgende(
            lijst: teSynchroniseren,
            profiel: profiel,
            index: 0,
            aantalGelukt: 0,
            onEen: onEen
        ) { aantal in
            completion(aantal, teSynchroniseren.count)
        }
    }

    private func syncVolgende(
        lijst: [Meting],
        profiel: Profiel,
        index: Int,
        aantalGelukt: Int,
        onEen: @escaping (Meting, Bool) -> Void,
        completion: @escaping (Int) -> Void
    ) {
        guard index < lijst.count else { completion(aantalGelukt); return }
        let meting = lijst[index]
        synchroniseer(meting: meting, profiel: profiel) { [weak self] success, _ in
            onEen(meting, success)
            self?.syncVolgende(
                lijst: lijst, profiel: profiel,
                index: index + 1,
                aantalGelukt: aantalGelukt + (success ? 1 : 0),
                onEen: onEen, completion: completion
            )
        }
    }

    private func schrijfStatus(for identifier: HKQuantityTypeIdentifier) -> HKAuthorizationStatus {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            return .sharingDenied
        }
        return store.authorizationStatus(for: type)
    }

    private func identifiersVoorSynchronisatie(van meting: Meting) -> [HKQuantityTypeIdentifier] {
        var identifiers: [HKQuantityTypeIdentifier] = [.bodyMass, .bodyMassIndex]
        if meting.vetpercentage != nil {
            identifiers.append(.bodyFatPercentage)
            identifiers.append(.leanBodyMass)
        }
        return identifiers
    }

    private func identifiersVoorVerwijderen(van meting: Meting) -> [HKQuantityTypeIdentifier] {
        let opgeslagenIdentifiers = meting.healthGesynchroniseerdeTypeIds?
            .split(separator: ",")
            .map(String.init)
            .compactMap(HKQuantityTypeIdentifier.init(rawValue:)) ?? []

        if !opgeslagenIdentifiers.isEmpty {
            return opgeslagenIdentifiers
        }

        return identifiersVoorSynchronisatie(van: meting)
    }

    private func heeftVolledigeSchrijftoestemming(voor identifiers: [HKQuantityTypeIdentifier]) -> Bool {
        identifiers.allSatisfy { schrijfStatus(for: $0) == .sharingAuthorized }
    }

    private func heeftBestaandeHealthData(voor meting: Meting) -> Bool {
        meting.gesynchroniseerdMetHealth || meting.healthSyncId != nil || meting.healthSyncDatum != nil
    }
}
