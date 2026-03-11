import SwiftUI

struct GewichtInvoerSheet: View {
    let titel: String
    let bereik: ClosedRange<Double>
    let stap: Double
    let initieleWaarde: Double
    let onOpslaan: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var invoerGefocust: Bool
    @State private var invoer: String

    init(
        titel: String,
        bereik: ClosedRange<Double>,
        stap: Double = 0.1,
        initieleWaarde: Double,
        onOpslaan: @escaping (Double) -> Void
    ) {
        self.titel = titel
        self.bereik = bereik
        self.stap = stap
        self.initieleWaarde = initieleWaarde
        self.onOpslaan = onOpslaan
        _invoer = State(initialValue: Self.formatteer(initieleWaarde: initieleWaarde))
    }

    private var parsedWaarde: Double? {
        let tekst = invoer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tekst.isEmpty else { return nil }

        if let nummer = Self.formatter.number(from: tekst) {
            return nummer.doubleValue
        }

        let genormaliseerd = tekst.replacingOccurrences(of: ",", with: ".")
        return Double(genormaliseerd)
    }

    private var gevalideerdeWaarde: Double? {
        guard let parsedWaarde else { return nil }
        let afgerond = (parsedWaarde / stap).rounded() * stap
        let begrensd = min(max(afgerond, bereik.lowerBound), bereik.upperBound)
        return Double(round(begrensd * 10) / 10)
    }

    private var foutmelding: String? {
        guard let parsedWaarde else { return "Voer een geldig gewicht in." }
        guard bereik.contains(parsedWaarde) else {
            return "Gebruik een waarde tussen \(bereik.lowerBound.formatted(.number.precision(.fractionLength(1)))) en \(bereik.upperBound.formatted(.number.precision(.fractionLength(1)))) kg."
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Gewicht", text: $invoer)
                        .keyboardType(.decimalPad)
                        .focused($invoerGefocust)

                    Text("Je kunt een punt of komma gebruiken.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let foutmelding {
                        Text(foutmelding)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Gewicht invoeren")
                }
            }
            .navigationTitle(titel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuleer") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Opslaan") {
                        guard let gevalideerdeWaarde else { return }
                        onOpslaan(gevalideerdeWaarde)
                        dismiss()
                    }
                    .disabled(gevalideerdeWaarde == nil)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Gereed") { invoerGefocust = false }
                }
            }
            .onAppear {
                DispatchQueue.main.async {
                    invoerGefocust = true
                }
            }
        }
        .presentationDetents([.fraction(0.28)])
    }

    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    private static func formatteer(initieleWaarde: Double) -> String {
        formatter.string(from: NSNumber(value: initieleWaarde))
            ?? initieleWaarde.formatted(.number.precision(.fractionLength(1)))
    }
}
