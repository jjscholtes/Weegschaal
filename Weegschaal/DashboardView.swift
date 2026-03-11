import SwiftUI
import SwiftData

struct DashboardView: View {
    @EnvironmentObject var bluetooth: BluetoothManager
    @EnvironmentObject var healthKit: HealthKitManager
    @Environment(\.modelContext) var context
    @Query(sort: \Meting.datum, order: .reverse) var metingen: [Meting]

    @AppStorage("profielData") private var profielData: Data = (try? JSONEncoder().encode(Profiel())) ?? Data()
    @State private var toonVerbindSheet = false
    @State private var healthAlert = false
    @State private var healthBericht = ""

    private var profiel: Profiel {
        (try? JSONDecoder().decode(Profiel.self, from: profielData)) ?? Profiel()
    }

    private var meestRecent: Meting? {
        metingen.first(where: { $0.persoonId == profiel.persoonId })
    }

    private var vorigeMeting: Meting? {
        metingen.filter { $0.persoonId == profiel.persoonId }.dropFirst().first
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                if let meting = meestRecent {
                    ScrollView {
                        VStack(spacing: 16) {
                            heroSectie(meting: meting)
                            if meting.heeftLichaamssamenstelling {
                                lichaamsKaart(meting: meting)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 100)
                    }
                } else {
                    legeStatus
                }
            }
            .navigationTitle("Weegschaal")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if let meting = meestRecent {
                        Button {
                            syncNaarHealth(meting: meting)
                        } label: {
                            Image(systemName: meting.gesynchroniseerdMetHealth ? "heart.fill" : "heart")
                                .foregroundStyle(.pink)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                metenKnop
            }
            .sheet(isPresented: $toonVerbindSheet) {
                VerbindSheet()
            }
            .alert("Apple Health", isPresented: $healthAlert) {
                Button("OK") {}
            } message: {
                Text(healthBericht)
            }
            .onChange(of: bluetooth.nieuweMetingen) { _, nieuw in
                slaMetingenOp(nieuw)
            }
        }
    }

    // MARK: - Hero sectie

    private func heroSectie(meting: Meting) -> some View {
        let bmi = meting.bmi ?? profiel.berekenBMI(gewicht: meting.gewicht)
        let verschil = vorigeMeting.map { meting.gewicht - $0.gewicht }

        return VStack(spacing: 20) {
            // Datum + trend
            HStack(spacing: 8) {
                Text(meting.datum.formatted(.dateTime.weekday(.wide).day().month()))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                if let v = verschil {
                    Label(
                        String(format: "%+.1f kg", v),
                        systemImage: v >= 0 ? "arrow.up" : "arrow.down"
                    )
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background((v >= 0 ? Color.orange : Color.mint).opacity(0.12))
                    .foregroundStyle(v >= 0 ? .orange : .mint)
                    .clipShape(Capsule())
                }
            }

            // Groot gewichtsgetal
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(String(format: "%.1f", meting.gewicht))
                    .font(.system(size: 84, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("kg")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            // BMI balk
            BMIBalk(bmi: bmi)
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Lichaamsamenstelling kaart

    private func lichaamsKaart(meting: Meting) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Lichaamssamenstelling")
                .font(.footnote.bold())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.3)

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

            if let kcal = meting.kcal {
                Divider()
                HStack {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                    Text("\(kcal) kcal")
                        .font(.subheadline.bold())
                    Text("geschatte energieverbruik")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Lege status

    private var legeStatus: some View {
        VStack(spacing: 16) {
            Image(systemName: "scalemass")
                .font(.system(size: 56, weight: .ultraLight))
                .foregroundStyle(.secondary)
            Text("Nog geen metingen")
                .font(.title3.bold())
            Text("Stap op de weegschaal\nen tik op Nieuwe meting")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Meten knop (fixed onderaan)

    private var metenKnop: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                toonVerbindSheet = true
                bluetooth.startScan()
            } label: {
                HStack(spacing: 8) {
                    if bluetooth.status.isBusy {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.9)
                    } else {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    Text(bluetooth.status.isBusy ? bluetooth.status.omschrijving : "Nieuwe meting")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .foregroundStyle(.white)
                .background(bluetooth.status.isBusy ? Color.secondary : Color.appBlauw)
                .clipShape(RoundedRectangle(cornerRadius: 13))
            }
            .disabled(bluetooth.status.isBusy)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(.bar)
    }

    // MARK: - Acties

    private func slaMetingenOp(_ metingData: [MetingData]) {
        guard !metingData.isEmpty else { return }
        let bestaandeDatums = Set(metingen.map { $0.datum.timeIntervalSince1970 })
        for data in metingData where data.persoonId == profiel.persoonId {
            guard !bestaandeDatums.contains(data.datum.timeIntervalSince1970) else { continue }
            let meting = Meting(datum: data.datum, gewicht: data.gewicht, persoonId: data.persoonId)
            meting.vetpercentage   = data.vetpercentage
            meting.waterpercentage = data.waterpercentage
            meting.spierpercentage = data.spierpercentage
            meting.botmassa        = data.botmassa
            meting.kcal            = data.kcal
            meting.bmi             = profiel.berekenBMI(gewicht: data.gewicht)
            context.insert(meting)
        }
    }

    private func syncNaarHealth(meting: Meting) {
        if !healthKit.isGeautoriseerd {
            healthKit.vraagAutorisatie { success in
                if success { syncNaarHealth(meting: meting) }
            }
            return
        }
        healthKit.synchroniseer(meting: meting, profiel: profiel) { success, _ in
            healthBericht = success ? "Meting gesynchroniseerd met Apple Health." : "Synchronisatie mislukt."
            healthAlert = true
        }
    }
}

// MARK: - BMI balk (zone indicator)

struct BMIBalk: View {
    let bmi: Double

    private let minBMI: Double = 15
    private let maxBMI: Double = 35

    private var progress: Double {
        min(max((bmi - minBMI) / (maxBMI - minBMI), 0), 1)
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(String(format: "BMI %.1f", bmi))
                    .font(.subheadline.bold())
                Spacer()
                Text(bmi.bmiCategorie)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Gekleurde zone-balk
                    LinearGradient(stops: [
                        .init(color: .blue,   location: 0),
                        .init(color: .blue,   location: (18.5 - minBMI) / (maxBMI - minBMI)),
                        .init(color: .green,  location: (18.5 - minBMI) / (maxBMI - minBMI)),
                        .init(color: .green,  location: (25   - minBMI) / (maxBMI - minBMI)),
                        .init(color: .orange, location: (25   - minBMI) / (maxBMI - minBMI)),
                        .init(color: .orange, location: (30   - minBMI) / (maxBMI - minBMI)),
                        .init(color: .red,    location: (30   - minBMI) / (maxBMI - minBMI)),
                        .init(color: .red,    location: 1)
                    ], startPoint: .leading, endPoint: .trailing)
                    .frame(height: 5)
                    .clipShape(Capsule())
                    .opacity(0.3)

                    // Positie-indicator
                    Circle()
                        .fill(bmi.bmiKleur)
                        .frame(width: 13, height: 13)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .offset(x: geo.size.width * progress - 6.5)
                        .animation(.spring(duration: 0.6), value: bmi)
                }
            }
            .frame(height: 13)
        }
    }
}

// MARK: - Circulaire ring per metriek

struct LichaamsRingView: View {
    let waarde: Double
    let referentie: Double   // Referentiewaarde voor de ring (= volle ring)
    let eenheid: String
    let label: String
    let kleur: Color

    private var progress: Double { min(waarde / referentie, 1.0) }

    private var weergaveWaarde: String {
        waarde < 10 ? String(format: "%.1f", waarde) : String(format: "%.0f", waarde)
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Achtergrond ring
                Circle()
                    .stroke(kleur.opacity(0.12), lineWidth: 8)

                // Voortgangs ring
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(kleur, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 1.0), value: progress)

                // Waarde in het midden
                VStack(spacing: 0) {
                    Text(weergaveWaarde)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Text(eenheid)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 64, height: 64)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Verbind sheet (met werkende animatie)

struct VerbindSheet: View {
    @EnvironmentObject var bluetooth: BluetoothManager
    @Environment(\.dismiss) var dismiss
    @State private var rotatie: Double = 0

    private var stap: Int {
        switch bluetooth.status {
        case .scannen:   return 1
        case .verbinden: return 2
        case .verbonden: return 3
        default:         return 0
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 40) {
                Spacer()

                // Animatie-ring
                ZStack {
                    Circle()
                        .stroke(Color.appBlauw.opacity(0.1), lineWidth: 10)
                        .frame(width: 110, height: 110)

                    if bluetooth.status.isBusy {
                        Circle()
                            .trim(from: 0, to: 0.72)
                            .stroke(Color.appBlauw,
                                    style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .frame(width: 110, height: 110)
                            .rotationEffect(.degrees(rotatie - 90))
                            .onAppear {
                                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                                    rotatie = 360
                                }
                            }
                    }

                    Image(systemName: "scalemass.fill")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(Color.appBlauw)
                }

                // Stap-indicator
                VStack(spacing: 6) {
                    Text(bluetooth.status.omschrijving)
                        .font(.headline)
                        .multilineTextAlignment(.center)

                    VStack(spacing: 4) {
                        StapRij(nummer: 1, tekst: "Stap op de weegschaal", actief: stap == 1, klaar: stap > 1)
                        StapRij(nummer: 2, tekst: "Verbinding maken",      actief: stap == 2, klaar: stap > 2)
                        StapRij(nummer: 3, tekst: "Metingen ophalen",      actief: stap == 3, klaar: stap > 3)
                    }
                    .padding(.top, 8)
                }

                Spacer()
            }
            .padding(24)
            .navigationTitle("Verbinden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Annuleer") {
                        bluetooth.annuleer()
                        dismiss()
                    }
                }
            }
            .onChange(of: bluetooth.status) { _, status in
                if case .gereed = status, !bluetooth.nieuweMetingen.isEmpty {
                    dismiss()
                }
            }
        }
    }
}

struct StapRij: View {
    let nummer: Int
    let tekst: String
    let actief: Bool
    let klaar: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(klaar ? Color.appBlauw : (actief ? Color.appBlauw.opacity(0.15) : Color.secondary.opacity(0.1)))
                    .frame(width: 24, height: 24)
                if klaar {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(nummer)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(actief ? Color.appBlauw : .secondary)
                }
            }

            Text(tekst)
                .font(.subheadline)
                .foregroundStyle(actief ? .primary : .secondary)

            Spacer()
        }
    }
}
