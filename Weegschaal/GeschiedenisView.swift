import SwiftUI
import SwiftData
import Charts

struct GeschiedenisView: View {
    @EnvironmentObject var healthKit: HealthKitManager
    @Environment(\.modelContext) var context
    @Query(sort: \Meting.datum, order: .reverse) var alleMetingen: [Meting]

    @AppStorage("profielData") private var profielData: Data = (try? JSONEncoder().encode(Profiel())) ?? Data()
    @State private var grafiekMetriek: GrafiekMetriek = .gewicht
    @State private var teVerwijderen: Meting?
    @State private var verwijderAlert = false
    @State private var syncAlert = false
    @State private var syncBericht = ""

    private var profiel: Profiel {
        (try? JSONDecoder().decode(Profiel.self, from: profielData)) ?? Profiel()
    }

    private var metingen: [Meting] {
        alleMetingen.filter { $0.persoonId == profiel.persoonId }
    }

    private var gesorteerdeMetingen: [Meting] {
        metingen.sorted { $0.datum < $1.datum }
    }

    enum GrafiekMetriek: String, CaseIterable {
        case gewicht      = "Gewicht"
        case bmi          = "BMI"
        case vetpercentage  = "Vet%"
        case waterpercentage = "Water%"
        case spierpercentage = "Spier%"

        func waarde(meting: Meting) -> Double? {
            switch self {
            case .gewicht:         return meting.gewicht
            case .bmi:             return meting.bmi
            case .vetpercentage:   return meting.vetpercentage
            case .waterpercentage: return meting.waterpercentage
            case .spierpercentage: return meting.spierpercentage
            }
        }

        var eenheid: String {
            switch self {
            case .gewicht: return "kg"
            case .bmi:     return ""
            default:       return "%"
            }
        }

        var kleur: Color {
            switch self {
            case .gewicht:         return .appBlauw
            case .bmi:             return .purple
            case .vetpercentage:   return .vetKleur
            case .waterpercentage: return .waterKleur
            case .spierpercentage: return .spierKleur
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        if gesorteerdeMetingen.count >= 2 {
                            grafiekKaart
                        }
                        metingenLijst
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Geschiedenis")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    let ongesync = metingen.filter { !$0.gesynchroniseerdMetHealth }
                    if !ongesync.isEmpty {
                        Button("Sync alle") { syncAlle() }
                            .font(.subheadline)
                    }
                }
            }
            .alert("Meting verwijderen?", isPresented: $verwijderAlert, presenting: teVerwijderen) { meting in
                Button("Verwijder", role: .destructive) { context.delete(meting) }
                Button("Annuleer", role: .cancel) {}
            } message: { meting in
                Text("De meting van \(meting.datum.formatted(date: .abbreviated, time: .omitted)) wordt permanent verwijderd.")
            }
            .alert("Apple Health", isPresented: $syncAlert) {
                Button("OK") {}
            } message: {
                Text(syncBericht)
            }
        }
    }

    // MARK: - Grafiek kaart

    private var grafiekKaart: some View {
        let punten = gesorteerdeMetingen.compactMap { m -> (Date, Double)? in
            guard let v = grafiekMetriek.waarde(meting: m) else { return nil }
            return (m.datum, v)
        }

        return VStack(alignment: .leading, spacing: 14) {
            // Pill-selector (scrollbaar horizontaal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(GrafiekMetriek.allCases, id: \.self) { m in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                grafiekMetriek = m
                            }
                        } label: {
                            Text(m.rawValue)
                                .font(.caption.bold())
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(grafiekMetriek == m ? m.kleur : Color.secondary.opacity(0.1))
                                .foregroundStyle(grafiekMetriek == m ? .white : .primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }

            // Grafiek
            if punten.count >= 2 {
                Chart {
                    ForEach(punten, id: \.0) { datum, waarde in
                        AreaMark(
                            x: .value("Datum", datum),
                            y: .value(grafiekMetriek.rawValue, waarde)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [grafiekMetriek.kleur.opacity(0.25), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("Datum", datum),
                            y: .value(grafiekMetriek.rawValue, waarde)
                        )
                        .foregroundStyle(grafiekMetriek.kleur)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Datum", datum),
                            y: .value(grafiekMetriek.rawValue, waarde)
                        )
                        .foregroundStyle(grafiekMetriek.kleur)
                        .symbolSize(25)
                    }
                }
                .frame(height: 160)
                .chartYAxisLabel(grafiekMetriek.eenheid, position: .trailing)
                .chartXAxis {
                    AxisMarks(preset: .aligned) { _ in
                        AxisGridLine()
                            .foregroundStyle(Color.secondary.opacity(0.1))
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                            .foregroundStyle(Color.secondary)
                            .font(.caption2)
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine()
                            .foregroundStyle(Color.secondary.opacity(0.1))
                        AxisValueLabel()
                            .foregroundStyle(Color.secondary)
                            .font(.caption2)
                    }
                }
                .animation(.easeInOut, value: grafiekMetriek)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Metingen lijst

    private var metingenLijst: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Alle metingen")
                    .font(.footnote.bold())
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.3)
                Spacer()
                Text("\(metingen.count)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)

            if metingen.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 36, weight: .ultraLight))
                        .foregroundStyle(.secondary)
                    Text("Nog geen metingen")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(metingen.enumerated()), id: \.element.id) { index, meting in
                        MetingRij(
                            meting: meting,
                            profiel: profiel,
                            vorigeGewicht: metingen.dropFirst(index + 1).first?.gewicht
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                teVerwijderen = meting
                                verwijderAlert = true
                            } label: {
                                Label("Verwijder", systemImage: "trash")
                            }
                        }

                        if index < metingen.count - 1 {
                            Divider()
                                .padding(.leading, 16)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    // MARK: - Acties

    private func syncAlle() {
        if !healthKit.isGeautoriseerd {
            healthKit.vraagAutorisatie { success in
                if success { syncAlle() }
            }
            return
        }
        healthKit.synchroniseerAlle(metingen: Array(metingen), profiel: profiel) { aantal in
            syncBericht = "\(aantal) meting\(aantal == 1 ? "" : "en") gesynchroniseerd met Apple Health."
            syncAlert = true
        }
    }
}

// MARK: - Meting rij

struct MetingRij: View {
    let meting: Meting
    let profiel: Profiel
    let vorigeGewicht: Double?

    private var verschil: Double? {
        vorigeGewicht.map { meting.gewicht - $0 }
    }

    private var bmi: Double {
        meting.bmi ?? profiel.berekenBMI(gewicht: meting.gewicht)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Datum kolom
            VStack(alignment: .leading, spacing: 3) {
                Text(meting.datum.formatted(.dateTime.day().month(.wide)))
                    .font(.subheadline.bold())
                Text(meting.datum.formatted(.dateTime.year().weekday(.wide)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Body comp samenvatting (kleine dots)
            if meting.heeftLichaamssamenstelling {
                HStack(spacing: 4) {
                    if let vet = meting.vetpercentage {
                        MetriekDot(waarde: vet, eenheid: "%", kleur: .vetKleur)
                    }
                    if let water = meting.waterpercentage {
                        MetriekDot(waarde: water, eenheid: "%", kleur: .waterKleur)
                    }
                }
            }

            // Gewicht + trend
            VStack(alignment: .trailing, spacing: 3) {
                Text(String(format: "%.1f kg", meting.gewicht))
                    .font(.headline.monospacedDigit())

                HStack(spacing: 3) {
                    Text(String(format: "BMI %.1f", bmi))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let v = verschil {
                        Image(systemName: v >= 0 ? "arrow.up" : "arrow.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(v >= 0 ? .orange : .mint)
                    }
                }
            }

            // Health sync icoon
            if meting.gesynchroniseerdMetHealth {
                Image(systemName: "heart.fill")
                    .font(.caption2)
                    .foregroundStyle(.pink)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct MetriekDot: View {
    let waarde: Double
    let eenheid: String
    let kleur: Color

    private var waardeTekst: String {
        waarde.formatted(.number.precision(.fractionLength(0))) + eenheid
    }

    var body: some View {
        HStack(spacing: 2) {
            Circle()
                .fill(kleur)
                .frame(width: 6, height: 6)
            Text(waardeTekst)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}
