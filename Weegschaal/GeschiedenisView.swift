import SwiftUI
import SwiftData
import Charts

struct GeschiedenisView: View {
    @EnvironmentObject var healthKit: HealthKitManager
    @Environment(\.modelContext) var context
    @Query(sort: \Meting.datum, order: .reverse) var alleMetingen: [Meting]

    @AppStorage(Profiel.storageKey) private var profielData: Data = (try? JSONEncoder().encode(Profiel())) ?? Data()
    @AppStorage("doelgewicht") private var doelgewicht: Double = 75
    @State private var grafiekMetriek: GrafiekMetriek = .gewicht
    @State private var geselecteerdePeriode: Periode = .jaar
    @State private var geselecteerdeMeting: Meting?
    @State private var teVerwijderen: Meting?
    @State private var verwijderAlert = false
    @State private var verwijderBezig = false
    @State private var syncBezig = false
    @State private var syncAlert = false
    @State private var syncBericht = ""
    @State private var geselecteerdGrafiekPuntId: Date?

    private var profiel: Profiel {
        (try? JSONDecoder().decode(Profiel.self, from: profielData)) ?? Profiel()
    }

    private var metingen: [Meting] {
        alleMetingen.filter { $0.persoonId == profiel.persoonId }
    }

    private var gesorteerdeMetingen: [Meting] {
        metingen.sorted { $0.datum < $1.datum }
    }

    private var grafiekMetingen: [Meting] {
        guard let vanaf = geselecteerdePeriode.datumVanaf else { return gesorteerdeMetingen }
        return gesorteerdeMetingen.filter { $0.datum >= vanaf }
    }

    private var outlierIds: Set<UUID> {
        MetingAnalyse.outlierIds(metingen: gesorteerdeMetingen)
    }

    // MARK: - Periode

    enum Periode: String, CaseIterable {
        case dag         = "D"
        case week        = "W"
        case maand       = "M"
        case halfJaar    = "6M"
        case jaar        = "J"

        var datumVanaf: Date? {
            let cal = Calendar.current
            switch self {
            case .dag:        return cal.date(byAdding: .day, value: -1,  to: Date())
            case .week:       return cal.date(byAdding: .day, value: -7,  to: Date())
            case .maand:      return cal.date(byAdding: .month, value: -1,  to: Date())
            case .halfJaar:   return cal.date(byAdding: .month, value: -6,  to: Date())
            case .jaar:       return cal.date(byAdding: .year,  value: -1,  to: Date())
            }
        }

        var omschrijving: String {
            switch self {
            case .dag: return "Afgelopen 24 uur"
            case .week: return "Afgelopen week"
            case .maand: return "Afgelopen maand"
            case .halfJaar: return "Afgelopen 6 maanden"
            case .jaar: return "Afgelopen jaar"
            }
        }
    }

    // MARK: - Grafiek metriek

    enum GrafiekMetriek: String, CaseIterable {
        case gewicht       = "Gewicht"
        case bmi           = "BMI"
        case vetpercentage = "Vet%"
        case water         = "Water%"
        case spier         = "Spier%"

        func waarde(meting: Meting) -> Double? {
            switch self {
            case .gewicht:       return meting.gewicht
            case .bmi:           return meting.bmi
            case .vetpercentage: return meting.vetpercentage
            case .water:         return meting.waterpercentage
            case .spier:         return meting.spierpercentage
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
            case .gewicht:       return .appBlauw
            case .bmi:           return .purple
            case .vetpercentage: return .vetKleur
            case .water:         return .waterKleur
            case .spier:         return .spierKleur
            }
        }

        var icoon: String {
            switch self {
            case .gewicht: return "scalemass.fill"
            case .bmi: return "figure.walk"
            case .vetpercentage: return "drop.fill"
            case .water: return "humidity.fill"
            case .spier: return "figure.strengthtraining.traditional"
            }
        }

        func formatteer(_ waarde: Double) -> String {
            switch self {
            case .gewicht:
                return "\(waarde.formatted(.number.precision(.fractionLength(1)))) kg"
            case .bmi:
                return waarde.formatted(.number.precision(.fractionLength(1)))
            default:
                return "\(waarde.formatted(.number.precision(.fractionLength(1)))) %"
            }
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                List {
                    if gesorteerdeMetingen.count >= 2 {
                        grafiekKaart
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }

                    metingenLijst
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Geschiedenis")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    let ongesync = metingen.filter { !$0.gesynchroniseerdMetHealth }
                    if !ongesync.isEmpty {
                        Button {
                            syncAlle()
                        } label: {
                            if syncBezig {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Text("Sync alle")
                            }
                        }
                        .disabled(syncBezig)
                    }
                }
            }
            .sheet(item: $geselecteerdeMeting) { meting in
                let index = metingen.firstIndex(where: { $0.id == meting.id }) ?? 0
                MetingDetailView(
                    meting: meting,
                    profiel: profiel,
                    vorigeGewicht: metingen.dropFirst(index + 1).first?.gewicht,
                    isOutlier: outlierIds.contains(meting.id)
                )
            }
            .alert("Meting verwijderen?", isPresented: $verwijderAlert, presenting: teVerwijderen) { meting in
                Button("Verwijder", role: .destructive) { verwijderMeting(meting) }
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
        let punten = grafiekPunten()
        let geselecteerdPunt = geselecteerdGrafiekPunt(in: punten)
        let actiefPunt = geselecteerdPunt ?? punten.last
        let delta = periodeDelta(voor: punten)

        return VStack(alignment: .leading, spacing: 16) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(GrafiekMetriek.allCases, id: \.self) { metriek in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                grafiekMetriek = metriek
                                geselecteerdGrafiekPuntId = nil
                            }
                        } label: {
                            GrafiekMetriekKnop(
                                titel: metriek.rawValue,
                                icoon: metriek.icoon,
                                kleur: metriek.kleur,
                                geselecteerd: grafiekMetriek == metriek
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }

            HStack(spacing: 4) {
                ForEach(Periode.allCases, id: \.self) { periode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            geselecteerdePeriode = periode
                            geselecteerdGrafiekPuntId = nil
                        }
                    } label: {
                        Text(periode.rawValue)
                            .font(.caption2.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(geselecteerdePeriode == periode
                                          ? grafiekMetriek.kleur.opacity(0.14)
                                          : Color.clear)
                            )
                            .foregroundStyle(geselecteerdePeriode == periode ? grafiekMetriek.kleur : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            if punten.count >= 2, let actiefPunt {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(geselecteerdPunt != nil ? periodeLabel(voor: actiefPunt) : geselecteerdePeriode.omschrijving)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Text(grafiekMetriek.formatteer(actiefPunt.waarde))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()

                        VStack(alignment: .leading, spacing: 4) {
                            Text(contextRegel(voor: actiefPunt, isSelectieActief: geselecteerdPunt != nil))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let delta, geselecteerdPunt == nil {
                                Text(trendTekst(voor: delta))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(trendKleur(voor: delta))
                            }
                        }
                    }

                    if grafiekMetriek == .gewicht {
                        HStack(spacing: 8) {
                            Capsule()
                                .fill(Color.appBlauw.opacity(0.55))
                                .frame(width: 18, height: 2)
                            Text("Doel \(grafiekMetriek.formatteer(doelgewicht))")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.appBlauw)
                        }
                    }

                    Chart {
                        if grafiekMetriek == .gewicht {
                            RuleMark(y: .value("Doelgewicht", doelgewicht))
                                .lineStyle(StrokeStyle(lineWidth: 1.25, dash: [4, 4]))
                                .foregroundStyle(Color.appBlauw.opacity(0.45))
                        }

                        ForEach(punten) { punt in
                            LineMark(
                                x: .value("Datum", punt.datum),
                                y: .value(grafiekMetriek.rawValue, punt.waarde)
                            )
                            .interpolationMethod(.linear)
                            .foregroundStyle(grafiekMetriek.kleur)
                            .lineStyle(StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                        }

                        if let geselecteerdPunt {
                            RuleMark(x: .value("Selectie", geselecteerdPunt.datum))
                                .foregroundStyle(Color.secondary.opacity(0.18))
                                .lineStyle(StrokeStyle(lineWidth: 1))
                        }

                        if let markerPunt = geselecteerdPunt ?? punten.last {
                            PointMark(
                                x: .value("Datum", markerPunt.datum),
                                y: .value(grafiekMetriek.rawValue, markerPunt.waarde)
                            )
                            .foregroundStyle(.white)
                            .symbolSize(geselecteerdPunt == nil ? 90 : 110)

                            PointMark(
                                x: .value("Datum", markerPunt.datum),
                                y: .value(grafiekMetriek.rawValue, markerPunt.waarde)
                            )
                            .foregroundStyle(grafiekMetriek.kleur)
                            .symbolSize(geselecteerdPunt == nil ? 34 : 44)
                        }
                    }
                    .frame(height: 238)
                    .chartXScale(range: .plotDimension(startPadding: 10, endPadding: 12))
                    .chartYScale(domain: yDomein(voor: punten))
                    .chartLegend(.hidden)
                    .chartXAxis {
                        AxisMarks(values: xAsWaarden(voor: punten)) { value in
                            AxisGridLine()
                                .foregroundStyle(Color.secondary.opacity(0.06))
                            AxisValueLabel {
                                if let datum = value.as(Date.self) {
                                    Text(xAsLabel(voor: datum))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine()
                                .foregroundStyle(Color.secondary.opacity(0.06))
                            AxisValueLabel {
                                if let nummer = value.as(Double.self) {
                                    Text(yAsLabel(voor: nummer))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .chartPlotStyle { plotArea in
                        plotArea
                            .background(Color.clear)
                    }
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            if let plotFrame = proxy.plotFrame {
                                let plotRect = geometry[plotFrame]

                                Rectangle()
                                    .fill(.clear)
                                    .contentShape(Rectangle())
                                    .gesture(
                                        DragGesture(minimumDistance: 0)
                                            .onChanged { value in
                                                guard plotRect.contains(value.location) else { return }

                                                let locatieX = value.location.x - plotRect.origin.x
                                                guard let datum: Date = proxy.value(atX: locatieX) else { return }

                                                geselecteerdGrafiekPuntId = dichtstbijzijndePunt(aan: datum, in: punten)?.id
                                            }
                                    )
                            }
                        }
                    }
                    .animation(.easeInOut(duration: 0.25), value: grafiekMetriek)
                    .animation(.easeInOut(duration: 0.25), value: geselecteerdePeriode)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Te weinig data voor deze periode")
                        .font(.subheadline.weight(.semibold))
                    Text("Voeg nog een paar metingen toe om de trend van \(grafiekMetriek.rawValue.lowercased()) zichtbaar te maken.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var grafiekGroepering: GrafiekGroepering {
        switch geselecteerdePeriode {
        case .dag:
            return .meting
        case .week, .maand:
            return .dag
        case .halfJaar:
            return .week
        case .jaar:
            return .maand
        }
    }

    private func grafiekPunten() -> [GrafiekPunt] {
        let kalender = Calendar.current
        let groepering = grafiekGroepering

        if groepering == .meting {
            return grafiekMetingen.compactMap { meting in
                guard let waarde = grafiekMetriek.waarde(meting: meting) else { return nil }
                return GrafiekPunt(
                    datum: meting.datum,
                    bucketStart: meting.datum,
                    bucketEinde: meting.datum,
                    waarde: waarde,
                    aantalBronnen: 1
                )
            }
        }

        let gegroepeerdeWaarden = Dictionary(grouping: grafiekMetingen.compactMap { meting -> (Date, Double)? in
            guard let waarde = grafiekMetriek.waarde(meting: meting) else { return nil }
            let bucketStart = bucketStart(voor: meting.datum, groepering: groepering, kalender: kalender)
            return (bucketStart, waarde)
        }, by: \.0)

        return gegroepeerdeWaarden.keys.sorted().compactMap { start in
            let waarden = gegroepeerdeWaarden[start]?.map(\.1) ?? []
            guard !waarden.isEmpty else { return nil }

            let einde = bucketEinde(vanaf: start, groepering: groepering, kalender: kalender)
            let gemiddelde = waarden.reduce(0, +) / Double(waarden.count)

            return GrafiekPunt(
                datum: plotDatum(vanaf: start, tot: einde, groepering: groepering),
                bucketStart: start,
                bucketEinde: einde,
                waarde: gemiddelde,
                aantalBronnen: waarden.count
            )
        }
    }

    private func bucketStart(voor datum: Date, groepering: GrafiekGroepering, kalender: Calendar) -> Date {
        switch groepering {
        case .meting:
            return datum
        case .dag:
            return kalender.startOfDay(for: datum)
        case .week:
            return kalender.dateInterval(of: .weekOfYear, for: datum)?.start ?? kalender.startOfDay(for: datum)
        case .maand:
            return kalender.dateInterval(of: .month, for: datum)?.start ?? kalender.startOfDay(for: datum)
        }
    }

    private func bucketEinde(vanaf start: Date, groepering: GrafiekGroepering, kalender: Calendar) -> Date {
        let volgendeStart: Date?

        switch groepering {
        case .meting:
            volgendeStart = nil
        case .dag:
            volgendeStart = kalender.date(byAdding: .day, value: 1, to: start)
        case .week:
            volgendeStart = kalender.date(byAdding: .weekOfYear, value: 1, to: start)
        case .maand:
            volgendeStart = kalender.date(byAdding: .month, value: 1, to: start)
        }

        guard let volgendeStart else { return start }
        return kalender.date(byAdding: .second, value: -1, to: volgendeStart) ?? start
    }

    private func plotDatum(vanaf start: Date, tot einde: Date, groepering: GrafiekGroepering) -> Date {
        switch groepering {
        case .meting:
            return start
        case .dag:
            return start
        case .week, .maand:
            return start.addingTimeInterval(einde.timeIntervalSince(start) / 2)
        }
    }

    private func geselecteerdGrafiekPunt(in punten: [GrafiekPunt]) -> GrafiekPunt? {
        guard let geselecteerdGrafiekPuntId else { return nil }
        return punten.first { $0.id == geselecteerdGrafiekPuntId }
    }

    private func dichtstbijzijndePunt(aan datum: Date, in punten: [GrafiekPunt]) -> GrafiekPunt? {
        punten.min { abs($0.datum.timeIntervalSince(datum)) < abs($1.datum.timeIntervalSince(datum)) }
    }

    private func periodeDelta(voor punten: [GrafiekPunt]) -> Double? {
        guard let eerste = punten.first, let laatste = punten.last, punten.count >= 2 else { return nil }
        return laatste.waarde - eerste.waarde
    }

    private func trendTekst(voor delta: Double) -> String {
        let richting = delta > 0 ? "↗" : (delta < 0 ? "↘" : "→")
        return "\(richting) \(grafiekMetriek.formatteer(abs(delta))) in deze periode"
    }

    private func trendKleur(voor delta: Double) -> Color {
        if delta > 0 { return .orange }
        if delta < 0 { return .mint }
        return .secondary
    }

    private func yDomein(voor punten: [GrafiekPunt]) -> ClosedRange<Double> {
        var waarden = punten.map(\.waarde)
        if grafiekMetriek == .gewicht {
            waarden.append(doelgewicht)
        }

        guard let minimum = waarden.min(), let maximum = waarden.max() else {
            return 0...1
        }

        let span = max(maximum - minimum, grafiekMetriek == .gewicht ? 1.2 : 0.8)
        let padding = span * 0.18
        let ondergrens = max(0, minimum - padding)
        return ondergrens...(maximum + padding)
    }

    private func xAsWaarden(voor punten: [GrafiekPunt]) -> [Date] {
        guard let eerste = punten.first?.bucketStart, let laatste = punten.last?.bucketStart else { return [] }
        let kalender = Calendar.current

        switch geselecteerdePeriode {
        case .dag:
            return strideDatums(
                vanaf: eerste,
                totEnMet: laatste,
                component: .hour,
                stap: 6,
                kalender: kalender
            )
        case .week:
            return strideDatums(
                vanaf: kalender.startOfDay(for: eerste),
                totEnMet: laatste,
                component: .day,
                stap: 1,
                kalender: kalender
            )
        case .maand:
            return strideDatums(
                vanaf: kalender.startOfDay(for: eerste),
                totEnMet: laatste,
                component: .day,
                stap: 7,
                kalender: kalender
            )
        case .halfJaar:
            return strideDatums(
                vanaf: kalender.dateInterval(of: .month, for: eerste)?.start ?? eerste,
                totEnMet: laatste,
                component: .month,
                stap: 2,
                kalender: kalender
            )
        case .jaar:
            return strideDatums(
                vanaf: kalender.dateInterval(of: .month, for: eerste)?.start ?? eerste,
                totEnMet: laatste,
                component: .month,
                stap: 3,
                kalender: kalender
            )
        }
    }

    private func strideDatums(
        vanaf start: Date,
        totEnMet einde: Date,
        component: Calendar.Component,
        stap: Int,
        kalender: Calendar
    ) -> [Date] {
        guard start <= einde else { return [start] }

        var datums: [Date] = []
        var cursor = start

        while cursor <= einde {
            datums.append(cursor)
            guard let volgende = kalender.date(byAdding: component, value: stap, to: cursor) else { break }
            cursor = volgende
        }

        if datums.last != einde {
            datums.append(einde)
        }

        return datums
    }

    private func xAsLabel(voor datum: Date) -> String {
        switch geselecteerdePeriode {
        case .dag:
            return datum.formatted(.dateTime.hour())
        case .week:
            return datum.formatted(.dateTime.weekday(.abbreviated))
        case .maand:
            return datum.formatted(.dateTime.day())
        case .halfJaar, .jaar:
            return datum.formatted(.dateTime.month(.abbreviated))
        }
    }

    private func periodeLabel(voor punt: GrafiekPunt) -> String {
        switch grafiekGroepering {
        case .meting:
            return punt.bucketStart.formatted(.dateTime.day().month(.wide).year().hour().minute())
        case .dag:
            return punt.bucketStart.formatted(.dateTime.day().month(.wide).year())
        case .week:
            let zelfdeMaand = Calendar.current.isDate(punt.bucketStart, equalTo: punt.bucketEinde, toGranularity: .month)
            if zelfdeMaand {
                return "\(punt.bucketStart.formatted(.dateTime.day()))–\(punt.bucketEinde.formatted(.dateTime.day().month(.abbreviated).year()))"
            }
            return "\(punt.bucketStart.formatted(.dateTime.day().month(.abbreviated)))–\(punt.bucketEinde.formatted(.dateTime.day().month(.abbreviated).year()))"
        case .maand:
            return punt.bucketStart.formatted(.dateTime.month(.wide).year())
        }
    }

    private func contextRegel(voor punt: GrafiekPunt, isSelectieActief: Bool) -> String {
        let label: String

        switch grafiekGroepering {
        case .meting:
            label = isSelectieActief ? "Meting" : "Laatste meting"
        case .dag:
            if punt.aantalBronnen > 1 {
                label = isSelectieActief ? "Daggemiddelde" : "Laatste daggemiddelde"
            } else {
                label = isSelectieActief ? "Meting" : "Laatste meting"
            }
        case .week:
            label = isSelectieActief ? "Weekgemiddelde" : "Laatste weekgemiddelde"
        case .maand:
            label = isSelectieActief ? "Maandgemiddelde" : "Laatste maandgemiddelde"
        }

        let bronTekst = punt.aantalBronnen > 1 ? " · \(punt.aantalBronnen) metingen" : ""
        return "\(label)\(bronTekst)"
    }

    private func yAsLabel(voor waarde: Double) -> String {
        switch grafiekMetriek {
        case .gewicht:
            return waarde.formatted(.number.precision(.fractionLength(1)))
        case .bmi:
            return waarde.formatted(.number.precision(.fractionLength(1)))
        default:
            return waarde.formatted(.number.precision(.fractionLength(0)))
        }
    }

    // MARK: - Metingen lijst

    private var metingenLijst: some View {
        Section {
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
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(Array(metingen.enumerated()), id: \.element.id) { index, meting in
                    let isOutlier = outlierIds.contains(meting.id)
                    MetingRij(
                        meting: meting,
                        profiel: profiel,
                        vorigeGewicht: metingen.dropFirst(index + 1).first?.gewicht,
                        isOutlier: isOutlier
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        geselecteerdeMeting = meting
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            teVerwijderen = meting
                            verwijderAlert = true
                        } label: {
                            Label("Verwijder", systemImage: "trash")
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(isOutlier ? Color.orange.opacity(0.10) : Color(.secondarySystemGroupedBackground))
                    .listRowSeparator(index < metingen.count - 1 ? .visible : .hidden)
                }
            }
        } header: {
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
            .textCase(nil)
        }
    }

    // MARK: - Sync alle (sequentieel, SwiftData-safe)

    private func syncAlle() {
        guard !syncBezig else { return }
        if !healthKit.isGeautoriseerd {
            healthKit.vraagAutorisatie { success, bericht in
                if success {
                    syncAlle()
                } else {
                    syncBericht = bericht ?? "Toegang tot Apple Health werd niet verleend."
                    syncAlert = true
                }
            }
            return
        }
        syncBezig = true
        healthKit.synchroniseerAlle(
            metingen: Array(metingen),
            profiel: profiel,
            onEen: { meting, success in
                if success { meting.gesynchroniseerdMetHealth = true }
            },
            completion: { aantal, totaal in
                syncBezig = false
                let doel = healthKit.status == .gedeeltelijk
                    ? "de geautoriseerde Apple Health-metrics"
                    : "Apple Health"
                if totaal == 0 {
                    syncBericht = "Alle metingen waren al gesynchroniseerd."
                } else if aantal == totaal {
                    syncBericht = "\(aantal) meting\(aantal == 1 ? "" : "en") gesynchroniseerd met \(doel)."
                } else {
                    let mislukt = totaal - aantal
                    syncBericht = "\(aantal) van \(totaal) metingen gesynchroniseerd (\(mislukt) mislukt)."
                }
                syncAlert = true
            }
        )
    }

    private func verwijderMeting(_ meting: Meting) {
        guard !verwijderBezig else { return }

        let heeftHealthData = meting.gesynchroniseerdMetHealth
            || meting.healthSyncId != nil
            || meting.healthSyncDatum != nil

        guard heeftHealthData else {
            markeerWeegschaalMetingAlsVerwijderd(meting)
            context.delete(meting)
            return
        }

        if !healthKit.isGeautoriseerd {
            healthKit.vraagAutorisatie { success, bericht in
                if success {
                    verwijderMeting(meting)
                } else {
                    syncBericht = bericht ?? "Toegang tot Apple Health werd niet verleend."
                    syncAlert = true
                }
            }
            return
        }

        verwijderBezig = true
        healthKit.verwijderGesynchroniseerdeData(voor: meting) { success, error in
            verwijderBezig = false
            if success {
                markeerWeegschaalMetingAlsVerwijderd(meting)
                context.delete(meting)
            } else {
                syncBericht = error?.localizedDescription ?? "Apple Health-data kon niet worden bijgewerkt."
                syncAlert = true
            }
        }
    }

    private func markeerWeegschaalMetingAlsVerwijderd(_ meting: Meting) {
        VerwijderdeWeegschaalMetingen.voegToe(meting.fallbackWeegschaalBronId)
    }
}

// MARK: - Meting rij

struct MetingRij: View {
    let meting: Meting
    let profiel: Profiel
    let vorigeGewicht: Double?
    let isOutlier: Bool

    private var verschil: Double? { vorigeGewicht.map { meting.gewicht - $0 } }
    private var bmi: Double { meting.bmi ?? profiel.berekenBMI(gewicht: meting.gewicht) }

    var body: some View {
        HStack(spacing: 12) {
            // Datum
            VStack(alignment: .leading, spacing: 3) {
                Text(meting.datum.formatted(.dateTime.day().month(.wide)))
                    .font(.subheadline.bold())
                Text(meting.datum.formatted(.dateTime.year().weekday(.wide)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Body comp dots
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

            // Chevron + health
            HStack(spacing: 4) {
                if isOutlier {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                if meting.gesynchroniseerdMetHealth {
                    Image(systemName: "heart.fill")
                        .font(.caption2)
                        .foregroundStyle(.pink)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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
            Circle().fill(kleur).frame(width: 6, height: 6)
            Text(waardeTekst)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

private struct GrafiekPunt: Identifiable {
    let datum: Date
    let bucketStart: Date
    let bucketEinde: Date
    let waarde: Double
    let aantalBronnen: Int

    var id: Date { bucketStart }
}

private enum GrafiekGroepering {
    case meting
    case dag
    case week
    case maand
}

private struct GrafiekMetriekKnop: View {
    let titel: String
    let icoon: String
    let kleur: Color
    let geselecteerd: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icoon)
                .font(.caption.weight(.semibold))
            Text(titel)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(geselecteerd ? kleur : .secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(geselecteerd ? kleur.opacity(0.12) : Color(.tertiarySystemGroupedBackground))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(geselecteerd ? kleur.opacity(0.18) : Color.clear, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
