import HealthKit
import Foundation
import Combine

final class HealthKitManager: ObservableObject {
    private let store = HKHealthStore()

    @Published var isGeautoriseerd = false

    private let schrijfTypes: Set<HKSampleType> = [
        HKQuantityType(.bodyMass),
        HKQuantityType(.bodyMassIndex),
        HKQuantityType(.bodyFatPercentage),
        HKQuantityType(.leanBodyMass)
    ]

    init() {
        controleerAutorisatie()
    }

    var isHealthKitBeschikbaar: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    private func controleerAutorisatie() {
        guard isHealthKitBeschikbaar else { return }
        let status = store.authorizationStatus(for: HKQuantityType(.bodyMass))
        isGeautoriseerd = status == .sharingAuthorized
    }

    func vraagAutorisatie(completion: @escaping (Bool) -> Void) {
        guard isHealthKitBeschikbaar else {
            completion(false)
            return
        }
        store.requestAuthorization(toShare: schrijfTypes, read: []) { success, _ in
            DispatchQueue.main.async {
                self.isGeautoriseerd = success
                completion(success)
            }
        }
    }

    func synchroniseer(meting: Meting, profiel: Profiel, completion: @escaping (Bool, Error?) -> Void) {
        guard isHealthKitBeschikbaar else {
            completion(false, nil)
            return
        }

        var samples: [HKQuantitySample] = []

        // Gewicht
        let gewichtSample = HKQuantitySample(
            type: HKQuantityType(.bodyMass),
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: meting.gewicht),
            start: meting.datum,
            end: meting.datum
        )
        samples.append(gewichtSample)

        // BMI (berekend met profielhoogte)
        let bmi = meting.bmi ?? profiel.berekenBMI(gewicht: meting.gewicht)
        if bmi > 0 {
            let bmiSample = HKQuantitySample(
                type: HKQuantityType(.bodyMassIndex),
                quantity: HKQuantity(unit: .count(), doubleValue: bmi),
                start: meting.datum,
                end: meting.datum
            )
            samples.append(bmiSample)
        }

        // Vetpercentage
        if let vet = meting.vetpercentage {
            let vetSample = HKQuantitySample(
                type: HKQuantityType(.bodyFatPercentage),
                quantity: HKQuantity(unit: .percent(), doubleValue: vet / 100.0),
                start: meting.datum,
                end: meting.datum
            )
            samples.append(vetSample)
        }

        // Lean body mass (gewicht minus vetmassa)
        if let vet = meting.vetpercentage {
            let leanMass = meting.gewicht * (1.0 - vet / 100.0)
            let leanSample = HKQuantitySample(
                type: HKQuantityType(.leanBodyMass),
                quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: leanMass),
                start: meting.datum,
                end: meting.datum
            )
            samples.append(leanSample)
        }

        store.save(samples) { success, error in
            DispatchQueue.main.async {
                completion(success, error)
            }
        }
    }

    func synchroniseerAlle(metingen: [Meting], profiel: Profiel, completion: @escaping (Int) -> Void) {
        let teSynchroniseren = metingen.filter { !$0.gesynchroniseerdMetHealth }
        guard !teSynchroniseren.isEmpty else {
            completion(0)
            return
        }

        let groep = DispatchGroup()
        var aantalGelukt = 0

        for meting in teSynchroniseren {
            groep.enter()
            synchroniseer(meting: meting, profiel: profiel) { success, _ in
                if success {
                    meting.gesynchroniseerdMetHealth = true
                    aantalGelukt += 1
                }
                groep.leave()
            }
        }

        groep.notify(queue: .main) {
            completion(aantalGelukt)
        }
    }
}
