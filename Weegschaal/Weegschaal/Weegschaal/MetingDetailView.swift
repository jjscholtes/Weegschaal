import SwiftUI

struct MetingDetailView: View {
    let meting: Meting
    let profiel: Profiel
    let vorigeGewicht: Double?
    let isOutlier: Bool

    @EnvironmentObject var healthKit: HealthKitManager
    @Environment(\.dismiss) var dismiss
    @State private var healthAlert = false
    @State private var healthBericht = ""
    @State private var toonBewerkSheet = false

    private var bmi: Double { meting.bmi ?? profiel.berekenBMI(gewicht: meting.gewicht) }
    private var verschil: Double? { vorigeGewicht.map { meting.gewicht - $0 } }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        heroKaart
                        if isOutlier {
                            outlierKaart
                        }
                        if meting.heeftLichaamssamenstelling {
                            lichaamsKaart
                        }
                        healthKnop
                    }
                    .padding(16)
                }
            }
            .navigationTitle(meting.datum.formatted(.dateTime.day().month(.wide).year()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Bewerk") { toonBewerkSheet = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sluiten") { dismiss() }
                }
            }
            .sheet(isPresented: $toonBewerkSheet) {
                MetingBewerkenView(meting: meting, profiel: profiel)
            }
            .alert("Apple Health", isPresented: $healthAlert) {
                Button("OK") {}
            } message: {
                Text(healthBericht)
            }
        }
    }

    // MARK: - Hero kaart

    private var heroKaart: some View {
        VStack(spacing: 16) {
            // Tijdstip
            Text(meting.datum.formatted(.dateTime.weekday(.wide).hour().minute()))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Gewicht
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(String(format: "%.1f", meting.gewicht))
                    .font(.system(size: 72, weight: .bold))
                    .monospacedDigit()
                Text("kg")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)
            }

            // Trend t.o.v. vorige meting
            if let v = verschil {
                Label(
                    String(format: "%+.1f kg t.o.v. vorige meting", v),
                    systemImage: v >= 0 ? "arrow.up" : "arrow.down"
                )
                .font(.caption.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background((v >= 0 ? Color.orange : Color.mint).opacity(0.12))
                .foregroundStyle(v >= 0 ? .orange : .mint)
                .clipShape(Capsule())
            }

            // BMI balk
            BMIBalk(bmi: bmi)
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var outlierKaart: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Deze meting wijkt sterk af van de vorige trend. Controleer of dit een correcte meting is.")
                .font(.subheadline)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Lichaamssamenstelling kaart

    private var lichaamsKaart: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Lichaamssamenstelling")
                .font(.footnote.bold())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.3)

            // Ringen
            HStack(spacing: 0) {
                if let vet = meting.vetpercentage {
                    LichaamsRingView(waarde: vet, referentie: 40, eenheid: "%",
                                    label: "Vet", kleur: .vetKleur)
                }
                if let water = meting.waterpercentage {
                    LichaamsRingView(waarde: water, referentie: 70, eenheid: "%",
                                    label: "Water", kleur: .waterKleur)
                }
                if let spier = meting.spierpercentage {
                    LichaamsRingView(waarde: spier, referentie: 65, eenheid: "%",
                                    label: "Spier", kleur: .spierKleur)
                }
                if let bot = meting.botmassa {
                    LichaamsRingView(waarde: bot, referentie: 5, eenheid: "kg",
                                    label: "Bot", kleur: .botKleur)
                }
            }

            // Berekende waarden
            if let vet = meting.vetpercentage {
                Divider()
                VStack(spacing: 8) {
                    BerekendRij(
                        label: "Vetmassa",
                        waarde: String(format: "%.1f kg", meting.gewicht * vet / 100),
                        icoon: "drop.fill", kleur: .vetKleur
                    )
                    BerekendRij(
                        label: "Vetvrije massa",
                        waarde: String(format: "%.1f kg", meting.gewicht * (1 - vet / 100)),
                        icoon: "figure.strengthtraining.traditional", kleur: .spierKleur
                    )
                }
            }

            // Kcal
            if let kcal = meting.kcal {
                Divider()
                BerekendRij(
                    label: "Geschat basismetabolisme",
                    waarde: "\(kcal) kcal/dag",
                    icoon: "flame.fill", kleur: .orange
                )
            }
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Health sync knop

    private var healthKnop: some View {
        Button {
            syncNaarHealth()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: meting.gesynchroniseerdMetHealth ? "heart.fill" : "heart")
                    .foregroundStyle(.pink)
                Text(meting.gesynchroniseerdMetHealth
                     ? "Gesynchroniseerd met Apple Health"
                     : "Sync naar Apple Health")
                    .font(.subheadline.bold())
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .disabled(meting.gesynchroniseerdMetHealth)
    }

    private func syncNaarHealth() {
        if !healthKit.isGeautoriseerd {
            healthKit.vraagAutorisatie { success, bericht in
                if success {
                    syncNaarHealth()
                } else {
                    healthBericht = bericht ?? "Toegang tot Apple Health werd niet verleend."
                    healthAlert = true
                }
            }
            return
        }
        healthKit.synchroniseer(meting: meting, profiel: profiel) { success, error in
            if success {
                healthBericht = healthKit.status == .gedeeltelijk
                    ? "Meting gesynchroniseerd voor de geautoriseerde Apple Health-metrics."
                    : "Meting gesynchroniseerd."
            } else {
                healthBericht = error?.localizedDescription ?? "Synchronisatie mislukt."
            }
            healthAlert = true
        }
    }
}

// MARK: - Berekend rij

struct BerekendRij: View {
    let label: String
    let waarde: String
    let icoon: String
    let kleur: Color

    var body: some View {
        HStack {
            Image(systemName: icoon)
                .foregroundStyle(kleur)
                .frame(width: 20)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(waarde)
                .font(.subheadline.bold())
        }
    }
}

struct MetingBewerkenView: View {
    let meting: Meting
    let profiel: Profiel

    @Environment(\.dismiss) private var dismiss

    @State private var datum: Date
    @State private var gewicht: Double
    @State private var heeftSamenstelling: Bool
    @State private var vetpercentage: Double
    @State private var waterpercentage: Double
    @State private var spierpercentage: Double
    @State private var botmassa: Double
    @State private var kcal: Int
    @State private var toonGewichtSheet = false

    init(meting: Meting, profiel: Profiel) {
        self.meting = meting
        self.profiel = profiel

        _datum = State(initialValue: meting.datum)
        _gewicht = State(initialValue: meting.gewicht)
        _heeftSamenstelling = State(initialValue: meting.heeftLichaamssamenstelling)
        _vetpercentage = State(initialValue: meting.vetpercentage ?? 20)
        _waterpercentage = State(initialValue: meting.waterpercentage ?? 50)
        _spierpercentage = State(initialValue: meting.spierpercentage ?? 35)
        _botmassa = State(initialValue: meting.botmassa ?? 3)
        _kcal = State(initialValue: meting.kcal ?? 1800)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basis") {
                    DatePicker("Datum en tijd", selection: $datum)
                    HStack {
                        Text("Gewicht")
                        Spacer()
                        Button {
                            toonGewichtSheet = true
                        } label: {
                            HStack(spacing: 6) {
                                Text("\(gewicht.formatted(.number.precision(.fractionLength(1)))) kg")
                                    .monospacedDigit()
                                Image(systemName: "pencil")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Stepper(value: $gewicht, in: 20...300, step: 0.1) {
                        Text("Gewicht: \(gewicht.formatted(.number.precision(.fractionLength(1)))) kg")
                    }
                }

                Section("Lichaamssamenstelling") {
                    Toggle("Beschikbaar", isOn: $heeftSamenstelling)

                    if heeftSamenstelling {
                        Stepper(value: $vetpercentage, in: 1...70, step: 0.1) {
                            Text("Vet: \(vetpercentage.formatted(.number.precision(.fractionLength(1)))) %")
                        }
                        Stepper(value: $waterpercentage, in: 10...80, step: 0.1) {
                            Text("Water: \(waterpercentage.formatted(.number.precision(.fractionLength(1)))) %")
                        }
                        Stepper(value: $spierpercentage, in: 5...80, step: 0.1) {
                            Text("Spier: \(spierpercentage.formatted(.number.precision(.fractionLength(1)))) %")
                        }
                        Stepper(value: $botmassa, in: 0.5...8, step: 0.1) {
                            Text("Botmassa: \(botmassa.formatted(.number.precision(.fractionLength(1)))) kg")
                        }
                        Stepper(value: $kcal, in: 500...5000, step: 10) {
                            Text("Kcal: \(kcal)")
                        }
                    }
                }
            }
            .navigationTitle("Meting bewerken")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $toonGewichtSheet) {
                GewichtInvoerSheet(
                    titel: "Gewicht aanpassen",
                    bereik: 20...300,
                    initieleWaarde: gewicht
                ) { nieuweWaarde in
                    gewicht = nieuweWaarde
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuleer") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Opslaan") {
                        slaOp()
                        dismiss()
                    }
                }
            }
        }
    }

    private func slaOp() {
        let oudeSyncDatum = meting.healthSyncDatum ?? meting.datum
        let wasGesynchroniseerd = meting.gesynchroniseerdMetHealth || meting.healthSyncId != nil

        meting.datum = datum
        meting.gewicht = gewicht
        meting.bmi = profiel.berekenBMI(gewicht: gewicht)

        if heeftSamenstelling {
            meting.vetpercentage = vetpercentage
            meting.waterpercentage = waterpercentage
            meting.spierpercentage = spierpercentage
            meting.botmassa = botmassa
            meting.kcal = kcal
        } else {
            meting.vetpercentage = nil
            meting.waterpercentage = nil
            meting.spierpercentage = nil
            meting.botmassa = nil
            meting.kcal = nil
        }

        // Inhoud is aangepast; opnieuw synchroniseren met HealthKit kan nodig zijn.
        meting.gesynchroniseerdMetHealth = false
        if wasGesynchroniseerd {
            meting.healthSyncDatum = oudeSyncDatum
        }
    }
}
