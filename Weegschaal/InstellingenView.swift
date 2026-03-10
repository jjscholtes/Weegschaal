import SwiftUI
import UIKit

struct InstellingenView: View {
    @AppStorage(Profiel.storageKey) private var profielData: Data = (try? JSONEncoder().encode(Profiel())) ?? Data()
    @AppStorage("doelgewicht") private var doelgewicht: Double = 75
    @AppStorage("herinneringAan") private var herinneringAan = false
    @AppStorage("herinneringUur") private var herinneringUur = 8
    @AppStorage("herinneringMinuut") private var herinneringMinuut = 0

    @EnvironmentObject var healthKit: HealthKitManager
    @EnvironmentObject var reminders: ReminderManager
    @State private var profiel: Profiel = .laden()
    @State private var healthAlert = false
    @State private var healthBericht = ""
    @State private var toonDoelgewichtSheet = false

    private var herinneringsTijd: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(from: DateComponents(hour: herinneringUur, minute: herinneringMinuut)) ?? Date()
            },
            set: { nieuw in
                let comp = Calendar.current.dateComponents([.hour, .minute], from: nieuw)
                herinneringUur = comp.hour ?? 8
                herinneringMinuut = comp.minute ?? 0
            }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                Form {
                    Section {
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

                    Section("Doelgewicht") {
                        HStack {
                            Label("Doel", systemImage: "target")
                                .foregroundStyle(Color.appBlauw)
                            Spacer()
                            Button {
                                toonDoelgewichtSheet = true
                            } label: {
                                HStack(spacing: 6) {
                                    Text("\(doelgewicht.formatted(.number.precision(.fractionLength(1)))) kg")
                                        .monospacedDigit()
                                    Image(systemName: "pencil")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        Stepper(
                            value: $doelgewicht,
                            in: 30...250,
                            step: 0.1
                        ) {
                            Text("Pas doelgewicht aan")
                        }
                    }

                    Section("Meet herinneringen") {
                        HStack {
                            Label("Notificatiestatus", systemImage: "bell.badge.fill")
                                .foregroundStyle(Color.appBlauw)
                            Spacer()
                            Text(reminders.status.label)
                                .foregroundStyle(reminders.status == .geautoriseerd ? .green : .secondary)
                        }

                        Toggle("Dagelijkse herinnering", isOn: $herinneringAan)

                        if herinneringAan {
                            DatePicker(
                                "Tijd",
                                selection: herinneringsTijd,
                                displayedComponents: .hourAndMinute
                            )
                        }

                        if reminders.status == .geweigerd {
                            Button("Open iOS instellingen") {
                                openSysteemInstellingen()
                            }
                        }
                    }

                    Section("Apple Health") {
                        HStack {
                            Label("Synchronisatie", systemImage: "heart.fill")
                                .foregroundStyle(.pink)
                            Spacer()
                            Text(healthKit.status.label)
                                .foregroundStyle(healthKit.status == .geautoriseerd ? .green : .secondary)
                                .font(.subheadline)
                        }

                        Text(healthKit.status.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if healthKit.status != .geautoriseerd {
                            Button {
                                healthKit.vraagAutorisatie { success, bericht in
                                    if !success {
                                        healthBericht = bericht ?? "Toegang tot Apple Health werd niet verleend."
                                        healthAlert = true
                                    }
                                }
                            } label: {
                                Label("Toegang verlenen aan Apple Health", systemImage: "arrow.right.circle")
                                    .foregroundStyle(Color.appBlauw)
                            }
                        }

                        if healthKit.status == .geweigerd || healthKit.status == .gedeeltelijk {
                            Button("Open iOS instellingen") {
                                openSysteemInstellingen()
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
            .onAppear {
                healthKit.verversStatus()
                reminders.verversStatus()
            }
            .onChange(of: profiel.persoonId)  { _, _ in slaOp() }
            .onChange(of: profiel.geslacht)   { _, _ in slaOp() }
            .onChange(of: profiel.lengte)     { _, _ in slaOp() }
            .onChange(of: profiel.leeftijd)   { _, _ in slaOp() }
            .onChange(of: herinneringAan) { _, nieuw in
                configureReminder(isEnabled: nieuw)
            }
            .onChange(of: herinneringUur) { _, _ in
                if herinneringAan { planHerinnering() }
            }
            .onChange(of: herinneringMinuut) { _, _ in
                if herinneringAan { planHerinnering() }
            }
            .alert("Apple Health", isPresented: $healthAlert) {
                Button("OK") {}
            } message: {
                Text(healthBericht)
            }
            .sheet(isPresented: $toonDoelgewichtSheet) {
                GewichtInvoerSheet(
                    titel: "Doelgewicht",
                    bereik: 30...250,
                    initieleWaarde: doelgewicht
                ) { nieuweWaarde in
                    doelgewicht = nieuweWaarde
                }
            }
        }
    }

    private func slaOp() {
        profiel.opslaan()
        if let data = try? JSONEncoder().encode(profiel) {
            profielData = data
        }
    }

    private func configureReminder(isEnabled: Bool) {
        guard isEnabled else {
            reminders.verwijderHerinneringen()
            return
        }

        if reminders.status == .geautoriseerd || reminders.status == .voorlopig {
            planHerinnering()
            return
        }

        reminders.vraagToestemming { success, bericht in
            if success {
                planHerinnering()
            } else {
                herinneringAan = false
                healthBericht = bericht ?? "Notificatie-toegang werd niet verleend."
                healthAlert = true
            }
        }
    }

    private func planHerinnering() {
        reminders.planDagelijkseHerinnering(uur: herinneringUur, minuut: herinneringMinuut) { success, bericht in
            if !success {
                herinneringAan = false
                healthBericht = bericht ?? "Herinnering kon niet worden gepland."
                healthAlert = true
            }
        }
    }

    private func openSysteemInstellingen() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
