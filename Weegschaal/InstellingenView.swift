import SwiftUI

struct InstellingenView: View {
    @AppStorage("profielData") private var profielData: Data = (try? JSONEncoder().encode(Profiel())) ?? Data()
    @EnvironmentObject var healthKit: HealthKitManager
    @State private var profiel: Profiel = .laden()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                Form {
                    Section {
                        // Profiel slot
                        HStack {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Mijn profiel op de weegschaal")
                                    Text("De BS 444 kan 8 personen opslaan")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "person.fill")
                                    .foregroundStyle(Color.appBlauw)
                            }
                            Spacer()
                            Picker("", selection: $profiel.persoonId) {
                                ForEach(1...8, id: \.self) { id in
                                    Text("\(id)").tag(id)
                                }
                            }
                            .labelsHidden()
                        }

                        // Geslacht
                        HStack {
                            Label {
                                Text("Geslacht")
                            } icon: {
                                Image(systemName: "figure.stand")
                                    .foregroundStyle(Color.appBlauw)
                            }
                            Spacer()
                            Picker("", selection: $profiel.geslacht) {
                                ForEach(Profiel.Geslacht.allCases) { g in
                                    Text(g.naam).tag(g)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 130)
                        }

                        // Lengte
                        HStack {
                            Label {
                                Text("Lengte")
                            } icon: {
                                Image(systemName: "ruler")
                                    .foregroundStyle(Color.appBlauw)
                            }
                            Spacer()
                            Stepper("\(profiel.lengte) cm", value: $profiel.lengte, in: 100...250)
                                .fixedSize()
                        }

                        // Leeftijd
                        HStack {
                            Label {
                                Text("Leeftijd")
                            } icon: {
                                Image(systemName: "calendar")
                                    .foregroundStyle(Color.appBlauw)
                            }
                            Spacer()
                            Stepper("\(profiel.leeftijd) jaar", value: $profiel.leeftijd, in: 10...120)
                                .fixedSize()
                        }

                    } header: {
                        Text("Mijn gegevens")
                    } footer: {
                        Text("Je lengte en leeftijd worden gebruikt om je BMI te berekenen.")
                    }

                    Section("Apple Health") {
                        HStack {
                            Label {
                                Text("Synchronisatie")
                            } icon: {
                                Image(systemName: "heart.fill")
                                    .foregroundStyle(.pink)
                            }
                            Spacer()
                            Text(healthKit.isGeautoriseerd ? "Actief" : "Niet actief")
                                .foregroundStyle(healthKit.isGeautoriseerd ? .green : .secondary)
                                .font(.subheadline)
                        }

                        if !healthKit.isGeautoriseerd {
                            Button {
                                healthKit.vraagAutorisatie { _ in }
                            } label: {
                                Label("Toegang verlenen aan Apple Health", systemImage: "arrow.right.circle")
                                    .foregroundStyle(Color.appBlauw)
                            }
                        }
                    }

                    Section("Over") {
                        LabeledContent("Weegschaal", value: "Medisana BS 444")
                        LabeledContent("Verbinding", value: "Bluetooth LE")
                        LabeledContent("Vereist", value: "iOS 17+")
                    }
                }
            }
            .navigationTitle("Instellingen")
            .onChange(of: profiel.persoonId)  { _, _ in slaOp() }
            .onChange(of: profiel.geslacht)   { _, _ in slaOp() }
            .onChange(of: profiel.lengte)     { _, _ in slaOp() }
            .onChange(of: profiel.leeftijd)   { _, _ in slaOp() }
        }
    }

    private func slaOp() {
        profiel.opslaan()
        if let data = try? JSONEncoder().encode(profiel) {
            profielData = data
        }
    }
}
