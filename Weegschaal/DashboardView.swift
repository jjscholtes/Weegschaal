import SwiftUI
import SwiftData

struct DashboardView: View {
    @EnvironmentObject var bluetooth: BluetoothManager
    @EnvironmentObject var healthKit: HealthKitManager
    @Environment(\.modelContext) var context
    @Query(sort: \Meting.datum, order: .reverse) var metingen: [Meting]

    @AppStorage(Profiel.storageKey) private var profielData: Data = (try? JSONEncoder().encode(Profiel())) ?? Data()
    @AppStorage("doelgewicht") private var doelgewicht: Double = 75
    @State private var toonVerbindSheet = false
    @State private var healthAlert = false
    @State private var healthBericht = ""

    private var profiel: Profiel {
        (try? JSONDecoder().decode(Profiel.self, from: profielData)) ?? Profiel()
    }

    private var profielMetingen: [Meting] {
        MetingAnalyse.metingenVoorProfiel(metingen, persoonId: profiel.persoonId)
    }

    private var meestRecent: Meting? {
        profielMetingen.last
    }

    private var vorigeMeting: Meting? {
        profielMetingen.dropLast().last
    }

    private var outlierIds: Set<UUID> {
        MetingAnalyse.outlierIds(metingen: profielMetingen)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                if let meting = meestRecent {
                    GeometryReader { geo in
                        let compact = geo.size.height < 800
                        let tussenruimte: CGFloat = compact ? 6 : 10

                        VStack(spacing: 0) {
                            heroSectie(meting: meting, compact: compact)

                            Spacer(minLength: tussenruimte)
                            doelKaart(meting: meting, compact: compact)

                            Spacer(minLength: tussenruimte)
                            trendAnalyseKaart(compact: compact)

                            if meting.heeftLichaamssamenstelling {
                                Spacer(minLength: tussenruimte)
                                lichaamsKaart(meting: meting, compact: compact)
                            }
                            if outlierIds.contains(meting.id) {
                                Spacer(minLength: tussenruimte)
                                outlierWaarschuwing(meting: meting, compact: compact)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, compact ? 2 : 8)
                        .padding(.bottom, compact ? 96 : 100)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                } else {
                    legeStatus
                }
            }
            .navigationTitle("Wegen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if let meting = meestRecent {
                        Button {
                            syncNaarHealth(meting: meting)
                        } label: {
                            Image(systemName: meting.gesynchroniseerdMetHealth ? "heart.fill" : "heart")
                                .foregroundStyle(.pink)
                        }
                    }

                    Menu {
                        Button {
                            startNieuweMeting()
                        } label: {
                            Label("Nieuwe meting", systemImage: "scalemass.fill")
                        }

                        Button {
                            startNieuweMeting(forceFullImport: true)
                        } label: {
                            Label("Importeer volledige historie", systemImage: "arrow.down.doc.fill")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .disabled(bluetooth.status.isBusy)
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

    private func heroSectie(meting: Meting, compact: Bool) -> some View {
        let bmi = meting.bmi ?? profiel.berekenBMI(gewicht: meting.gewicht)
        let verschil = vorigeMeting.map { meting.gewicht - $0.gewicht }

        return VStack(spacing: compact ? 8 : 16) {
            // Datum + trend
            HStack(spacing: 8) {
                Text(meting.datum.formatted(.dateTime.weekday(.wide).day().month()))
                    .font(compact ? .caption2 : .subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                if let v = verschil {
                    Label(
                        String(format: "%+.1f kg", v),
                        systemImage: v >= 0 ? "arrow.up" : "arrow.down"
                    )
                    .font(compact ? .caption2.bold() : .caption.bold())
                    .padding(.horizontal, compact ? 8 : 10)
                    .padding(.vertical, compact ? 3 : 4)
                    .background((v >= 0 ? Color.orange : Color.mint).opacity(0.12))
                    .foregroundStyle(v >= 0 ? .orange : .mint)
                    .clipShape(Capsule())
                }
            }

            // Groot gewichtsgetal
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(String(format: "%.1f", meting.gewicht))
                    .font(.system(size: compact ? 58 : 76, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("kg")
                    .font(compact ? .title3 : .title2)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, compact ? 6 : 8)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            // BMI balk
            BMIBalk(bmi: bmi)
        }
        .padding(compact ? 12 : 18)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Lichaamssamenstelling kaart

    private func lichaamsKaart(meting: Meting, compact: Bool) -> some View {
        return VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            Text("Lichaamssamenstelling")
                .font(compact ? .caption.bold() : .footnote.bold())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.3)

            HStack(spacing: compact ? 0 : 2) {
                if let vet = meting.vetpercentage {
                    LichaamsRingView(waarde: vet, referentie: 40, eenheid: "%", label: "Vet", kleur: .vetKleur)
                        .scaleEffect(compact ? 0.86 : 1)
                }
                if let water = meting.waterpercentage {
                    LichaamsRingView(waarde: water, referentie: 70, eenheid: "%", label: "Water", kleur: .waterKleur)
                        .scaleEffect(compact ? 0.86 : 1)
                }
                if let spier = meting.spierpercentage {
                    LichaamsRingView(waarde: spier, referentie: 65, eenheid: "%", label: "Spier", kleur: .spierKleur)
                        .scaleEffect(compact ? 0.86 : 1)
                }
                if let bot = meting.botmassa {
                    LichaamsRingView(waarde: bot, referentie: 5, eenheid: "kg", label: "Bot", kleur: .botKleur)
                        .scaleEffect(compact ? 0.86 : 1)
                }
            }

            if let kcal = meting.kcal {
                Divider()
                HStack {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                    Text("\(kcal.formatted(.number.grouping(.automatic))) kcal")
                        .font(compact ? .caption2.bold() : .caption.bold())
                    Text(compact ? "rustverbruik" : "geschatte energieverbruik")
                        .font(compact ? .caption2 : .caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let vet = meting.vetpercentage {
                let vetmassa = meting.gewicht * vet / 100
                let vetvrijeMassa = meting.gewicht - vetmassa

                Divider()
                VStack(spacing: compact ? 6 : 8) {
                    overzichtBerekendRij(
                        label: "Vetmassa",
                        waarde: "\(vetmassa.formatted(.number.precision(.fractionLength(1)))) kg",
                        icoon: "drop.fill",
                        kleur: .vetKleur,
                        compact: compact
                    )
                    overzichtBerekendRij(
                        label: "Vetvrije massa",
                        waarde: "\(vetvrijeMassa.formatted(.number.precision(.fractionLength(1)))) kg",
                        icoon: "figure.strengthtraining.traditional",
                        kleur: .spierKleur,
                        compact: compact
                    )
                }
            }
        }
        .padding(compact ? 12 : 14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func overzichtBerekendRij(
        label: String,
        waarde: String,
        icoon: String,
        kleur: Color,
        compact: Bool
    ) -> some View {
        HStack {
            Image(systemName: icoon)
                .font(compact ? .caption : .subheadline)
                .foregroundStyle(kleur)
                .frame(width: compact ? 16 : 20)
            Text(label)
                .font(compact ? .caption : .subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(waarde)
                .font((compact ? Font.caption : Font.subheadline).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    // MARK: - Doelgewicht + trend

    private func doelKaart(meting: Meting, compact: Bool) -> some View {
        let start = profielMetingen.first?.gewicht ?? meting.gewicht
        let resterend = meting.gewicht - doelgewicht
        let totaalPad = abs(start - doelgewicht)
        let afgelegd = abs(start - meting.gewicht)
        let progress = totaalPad > 0 ? min(max(afgelegd / totaalPad, 0), 1) : (abs(resterend) < 0.1 ? 1 : 0)

        return VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            HStack {
                Label("Doelgewicht", systemImage: "target")
                    .font(compact ? .callout.bold() : .subheadline.bold())
                Spacer()
                Text("\(doelgewicht.formatted(.number.precision(.fractionLength(1)))) kg")
                    .font(compact ? .callout : .subheadline)
                    .foregroundStyle(.secondary)
            }

            if abs(resterend) < 0.1 {
                Text("Doel bereikt")
                    .font(compact ? .callout.bold() : .subheadline.bold())
                    .foregroundStyle(.green)
            } else if resterend > 0 {
                Text("Nog \(resterend.formatted(.number.precision(.fractionLength(1)))) kg te gaan")
                    .font(compact ? .callout : .subheadline)
            } else {
                Text("Je zit \(abs(resterend).formatted(.number.precision(.fractionLength(1)))) kg onder je doel")
                    .font(compact ? .callout : .subheadline)
            }

            ProgressView(value: progress)
                .tint(.appBlauw)
        }
        .padding(compact ? 12 : 14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func trendAnalyseKaart(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            Text("Trendanalyse")
                .font(compact ? .caption.bold() : .footnote.bold())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.3)

            HStack(spacing: compact ? 6 : 10) {
                trendVakje(dagen: 7, titel: "7 dagen", compact: compact)
                trendVakje(dagen: 30, titel: "30 dagen", compact: compact)
                trendVakje(dagen: 90, titel: "90 dagen", compact: compact)
            }
        }
        .padding(compact ? 12 : 14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func trendVakje(dagen: Int, titel: String, compact: Bool) -> some View {
        let delta = MetingAnalyse.trendDelta(metingen: profielMetingen, dagen: dagen)

        return VStack(alignment: .leading, spacing: 4) {
            Text(titel)
                .font(compact ? .caption2 : .caption)
                .foregroundStyle(.secondary)
            if let delta {
                Text(String(format: "%+.1f kg", delta))
                    .font((compact ? Font.callout.bold() : Font.headline).monospacedDigit())
                    .foregroundStyle(delta > 0 ? .orange : (delta < 0 ? .mint : .primary))
            } else {
                Text("—")
                    .font(compact ? .callout : .headline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compact ? 8 : 10)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func outlierWaarschuwing(meting: Meting, compact: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Meting op \(meting.datum.formatted(date: .abbreviated, time: .omitted)) wijkt sterk af. Controleer of dit een correcte meting is.")
                .font(compact ? .caption : .subheadline)
        }
        .padding(compact ? 10 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
                startNieuweMeting()
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

    private func startNieuweMeting(forceFullImport: Bool = false) {
        toonVerbindSheet = true
        bluetooth.startScan(voor: profiel.persoonId, forceFullImport: forceFullImport)
    }

    private func slaMetingenOp(_ metingData: [MetingData]) {
        guard !metingData.isEmpty else { return }
        let verwijderdeBronIds = VerwijderdeWeegschaalMetingen.laad()
        let bevatProfielMetingen = metingData.contains { $0.persoonId == profiel.persoonId }
        var bestaandeDatums = Set(
            metingen
                .filter { $0.persoonId == profiel.persoonId }
                .map { $0.datum.timeIntervalSince1970 }
        )
        var heeftNieuweInserts = false

        for data in metingData where data.persoonId == profiel.persoonId {
            let bronId = data.weegschaalBronId
            guard !verwijderdeBronIds.contains(bronId) else { continue }

            let timestamp = data.datum.timeIntervalSince1970
            guard !bestaandeDatums.contains(timestamp) else { continue }

            let meting = Meting(datum: data.datum, gewicht: data.gewicht, persoonId: data.persoonId)
            meting.weegschaalBronId = bronId
            meting.vetpercentage   = data.vetpercentage
            meting.waterpercentage = data.waterpercentage
            meting.spierpercentage = data.spierpercentage
            meting.botmassa        = data.botmassa
            meting.kcal            = data.kcal
            meting.bmi             = profiel.berekenBMI(gewicht: data.gewicht)
            context.insert(meting)
            bestaandeDatums.insert(timestamp)
            heeftNieuweInserts = true
        }

        if heeftNieuweInserts {
            try? context.save()
        }

        if bluetooth.importModus == .volledigeHistorie, bevatProfielMetingen {
            bluetooth.markeerVolledigeImportVoltooid(voor: profiel.persoonId)
        }

        bluetooth.markeerNieuweMetingenVerwerkt()
    }

    private func syncNaarHealth(meting: Meting) {
        if !healthKit.isGeautoriseerd {
            healthKit.vraagAutorisatie { success, bericht in
                if success {
                    syncNaarHealth(meting: meting)
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
                    : "Meting gesynchroniseerd met Apple Health."
            } else {
                healthBericht = error?.localizedDescription ?? "Synchronisatie mislukt."
            }
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

                    Text(bluetooth.importModus.omschrijving)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    VStack(spacing: 4) {
                        StapRij(nummer: 1, tekst: "Stap op de weegschaal", actief: stap == 1, klaar: stap > 1)
                        StapRij(nummer: 2, tekst: "Verbinding maken",      actief: stap == 2, klaar: stap > 2)
                        StapRij(nummer: 3, tekst: bluetooth.importModus.stapTekst, actief: stap == 3, klaar: stap > 3)
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
