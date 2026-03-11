import CoreBluetooth
import Combine
import Foundation

// MARK: - BS444 Protocol constanten

enum BS444 {
    static let serviceUUID  = CBUUID(string: "000078b2-0000-1000-8000-00805f9b34fb")
    static let weightUUID   = CBUUID(string: "00008a21-0000-1000-8000-00805f9b34fb")
    static let bodyUUID     = CBUUID(string: "00008a22-0000-1000-8000-00805f9b34fb")
    static let personUUID   = CBUUID(string: "00008a82-0000-1000-8000-00805f9b34fb")
    static let cmdUUID      = CBUUID(string: "00008a81-0000-1000-8000-00805f9b34fb")

    // BS444 slaat tijden op vanaf 2010-01-01 i.p.v. 1970-01-01
    static let tijdOffset: UInt32 = 1_262_304_000

    static func triggerCommand() -> Data {
        let adjusted = UInt32(Date().timeIntervalSince1970) - tijdOffset
        return Data([
            0x02,
            UInt8(adjusted & 0xFF),
            UInt8((adjusted >> 8) & 0xFF),
            UInt8((adjusted >> 16) & 0xFF),
            UInt8((adjusted >> 24) & 0xFF)
        ])
    }

    // MARK: Packet parsing

    struct WeightPacket {
        let datum: Date
        let gewicht: Double
        let persoonId: Int
    }

    struct BodyPacket {
        let datum: Date
        let persoonId: Int
        let kcal: Int
        let vet: Double
        let water: Double
        let spier: Double
        let bot: Double
    }

    struct PersonPacket {
        let persoonId: Int
        let geslacht: Int
        let leeftijd: Int
        let lengte: Int
    }

    static func decodeWeight(_ bytes: [UInt8]) -> WeightPacket? {
        guard bytes.count >= 14, bytes[0] == 0x1D else { return nil }
        let rawWeight = UInt16(bytes[1]) | (UInt16(bytes[2]) << 8)
        let gewicht = Double(rawWeight) / 100.0
        let rawTs = UInt32(bytes[5]) | (UInt32(bytes[6]) << 8)
                  | (UInt32(bytes[7]) << 16) | (UInt32(bytes[8]) << 24)
        let datum = Date(timeIntervalSince1970: TimeInterval(rawTs + tijdOffset))
        let persoonId = Int(bytes[13])
        return WeightPacket(datum: datum, gewicht: gewicht, persoonId: persoonId)
    }

    static func decodeBody(_ bytes: [UInt8]) -> BodyPacket? {
        guard bytes.count >= 16, bytes[0] == 0x6F else { return nil }
        let rawTs = UInt32(bytes[1]) | (UInt32(bytes[2]) << 8)
                  | (UInt32(bytes[3]) << 16) | (UInt32(bytes[4]) << 24)
        let datum = Date(timeIntervalSince1970: TimeInterval(rawTs + tijdOffset))
        let persoonId = Int(bytes[5])
        let kcal = Int(UInt16(bytes[6]) | (UInt16(bytes[7]) << 8))
        let rawVet   = (UInt16(bytes[8])  | (UInt16(bytes[9])  << 8)) & 0x0FFF
        let rawWater = (UInt16(bytes[10]) | (UInt16(bytes[11]) << 8)) & 0x0FFF
        let rawSpier = (UInt16(bytes[12]) | (UInt16(bytes[13]) << 8)) & 0x0FFF
        let rawBot   = (UInt16(bytes[14]) | (UInt16(bytes[15]) << 8)) & 0x0FFF
        return BodyPacket(
            datum: datum, persoonId: persoonId, kcal: kcal,
            vet: Double(rawVet) / 10.0,
            water: Double(rawWater) / 10.0,
            spier: Double(rawSpier) / 10.0,
            bot: Double(rawBot) / 10.0
        )
    }

    static func decodePerson(_ bytes: [UInt8]) -> PersonPacket? {
        guard bytes.count >= 9, bytes[0] == 0x84 else { return nil }
        return PersonPacket(
            persoonId: Int(bytes[2]),
            geslacht: Int(bytes[4]),
            leeftijd: Int(bytes[5]),
            lengte: Int(bytes[6])
        )
    }
}

// MARK: - Bluetooth status

enum BluetoothStatus: Equatable {
    case uitgeschakeld
    case gereed
    case scannen
    case verbinden
    case verbonden
    case fout(String)

    var omschrijving: String {
        switch self {
        case .uitgeschakeld: return "Bluetooth is uitgeschakeld"
        case .gereed:        return "Klaar om te verbinden"
        case .scannen:       return "Zoeken naar weegschaal..."
        case .verbinden:     return "Verbinden..."
        case .verbonden:     return "Metingen ophalen..."
        case .fout(let m):   return "Fout: \(m)"
        }
    }

    var isBusy: Bool {
        switch self {
        case .scannen, .verbinden, .verbonden: return true
        default: return false
        }
    }
}

enum WeegschaalImportModus: Equatable {
    case volledigeHistorie
    case laatsteMeting

    var omschrijving: String {
        switch self {
        case .volledigeHistorie:
            return "Volledige historie wordt opgehaald"
        case .laatsteMeting:
            return "Alleen de nieuwste meting wordt opgehaald"
        }
    }

    var stapTekst: String {
        switch self {
        case .volledigeHistorie:
            return "Historie importeren"
        case .laatsteMeting:
            return "Laatste meting ophalen"
        }
    }
}

enum WeegschaalImportHistorie {
    private static let storageKey = "volledigeWeegschaalImportProfielen"

    static func heeftVolledigeImportGedaan(persoonId: Int) -> Bool {
        laad().contains(persoonId)
    }

    static func markeerVolledigeImport(persoonId: Int) {
        var ids = laad()
        ids.insert(persoonId)
        slaOp(ids)
    }

    private static func laad() -> Set<Int> {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let ids = try? JSONDecoder().decode(Set<Int>.self, from: data)
        else {
            return []
        }
        return ids
    }

    private static func slaOp(_ ids: Set<Int>) {
        guard let data = try? JSONEncoder().encode(ids) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

// MARK: - BluetoothManager

final class BluetoothManager: NSObject, ObservableObject {
    @Published var status: BluetoothStatus = .gereed
    @Published var nieuweMetingen: [MetingData] = []
    @Published private(set) var importModus: WeegschaalImportModus = .laatsteMeting
    @Published private(set) var importVoortgang: Double = 0
    @Published private(set) var ontvangenMetingAantal: Int = 0
    @Published private(set) var voltooideImporten: Int = 0

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var actiefPersoonId: Int?

    private var weightChar: CBCharacteristic?
    private var bodyChar: CBCharacteristic?
    private var personChar: CBCharacteristic?
    private var cmdChar: CBCharacteristic?

    // Houd bij hoeveel vereiste subscriptions actief zijn voordat het trigger-commando mag worden gestuurd.
    private var aantalSubscriptions = 0
    private var vereisteSubscriptions = 0
    private var heeftTriggerVerzonden = false

    // Tijdelijk opvangen van packets
    private var weightPackets: [BS444.WeightPacket] = []
    private var bodyPackets: [BS444.BodyPacket] = []

    // Timer om te detecteren dat de weegschaal klaar is met sturen
    private var afrondenTimer: Timer?
    private var scanTimeoutTimer: Timer?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func startScan(voor persoonId: Int, forceFullImport: Bool = false) {
        guard central.state == .poweredOn else {
            status = .uitgeschakeld
            return
        }
        actiefPersoonId = persoonId
        importModus = forceFullImport || !WeegschaalImportHistorie.heeftVolledigeImportGedaan(persoonId: persoonId)
            ? .volledigeHistorie
            : .laatsteMeting
        reset()
        importVoortgang = 0.08
        ontvangenMetingAantal = 0
        status = .scannen
        central.scanForPeripherals(
            withServices: [BS444.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        startScanTimeout()
    }

    func annuleer() {
        afrondenTimer?.invalidate()
        central.stopScan()
        if let p = peripheral {
            central.cancelPeripheralConnection(p)
        }
        reset()
        status = .gereed
    }

    private func reset() {
        afrondenTimer?.invalidate()
        afrondenTimer = nil
        scanTimeoutTimer?.invalidate()
        scanTimeoutTimer = nil
        nieuweMetingen = []
        importVoortgang = 0
        ontvangenMetingAantal = 0
        weightPackets.removeAll(keepingCapacity: false)
        bodyPackets.removeAll(keepingCapacity: false)
        aantalSubscriptions = 0
        vereisteSubscriptions = 0
        heeftTriggerVerzonden = false
        peripheral?.delegate = nil
        weightChar = nil
        bodyChar = nil
        personChar = nil
        cmdChar = nil
        peripheral = nil
    }

    func markeerNieuweMetingenVerwerkt() {
        guard !nieuweMetingen.isEmpty else { return }
        nieuweMetingen.removeAll(keepingCapacity: false)
    }

    func markeerVolledigeImportVoltooid(voor persoonId: Int) {
        WeegschaalImportHistorie.markeerVolledigeImport(persoonId: persoonId)
    }

    private func startScanTimeout() {
        scanTimeoutTimer?.invalidate()
        scanTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
            guard let self else { return }
            guard case .scannen = self.status else { return }

            self.central.stopScan()
            self.reset()
            self.status = .fout("Geen weegschaal gevonden")
        }
    }

    private func stuurTriggerCommand() {
        guard let p = peripheral, let cmd = cmdChar else { return }
        let data = BS444.triggerCommand()
        p.writeValue(data, for: cmd, type: .withResponse)
    }

    // Na ontvangst van alle data: koppel weight- en body-packets en maak MetingData objecten
    private func verwerkOntvangen() {
        afrondenTimer?.invalidate()
        afrondenTimer = nil

        let gekoppeldeMetingen = maakMetingenUitOntvangenPackets()

        switch importModus {
        case .volledigeHistorie:
            nieuweMetingen = gekoppeldeMetingen
        case .laatsteMeting:
            if let actiefPersoonId,
               let laatsteMeting = gekoppeldeMetingen.last(where: { $0.persoonId == actiefPersoonId }) {
                nieuweMetingen = [laatsteMeting]
            } else if let laatsteMeting = gekoppeldeMetingen.last {
                nieuweMetingen = [laatsteMeting]
            } else {
                nieuweMetingen = []
            }
        }

        ontvangenMetingAantal = max(ontvangenMetingAantal, gekoppeldeMetingen.count)
        importVoortgang = gekoppeldeMetingen.isEmpty ? max(importVoortgang, 0.92) : 1.0
        voltooideImporten += 1

        let huidigePeripheral = peripheral
        ruimActieveImportCacheOp()
        status = .gereed

        if let huidigePeripheral {
            central.cancelPeripheralConnection(huidigePeripheral)
        }
    }

    private func maakMetingenUitOntvangenPackets() -> [MetingData] {
        let gesorteerdeGewichten = weightPackets.sorted { $0.datum < $1.datum }
        let bodyPacketsPerPersoon = Dictionary(grouping: bodyPackets, by: \.persoonId)
            .mapValues { $0.sorted { $0.datum < $1.datum } }

        var bodyIndicesPerPersoon: [Int: Int] = [:]
        var resultaten: [MetingData] = []
        resultaten.reserveCapacity(gesorteerdeGewichten.count)

        for weightPacket in gesorteerdeGewichten {
            var meting = MetingData(
                datum: weightPacket.datum,
                gewicht: weightPacket.gewicht,
                persoonId: weightPacket.persoonId
            )

            if let bodyPackets = bodyPacketsPerPersoon[weightPacket.persoonId] {
                var bodyIndex = bodyIndicesPerPersoon[weightPacket.persoonId, default: 0]
                if let bodyPacket = dichtstbijzijndeBodyPacket(
                    voor: weightPacket,
                    in: bodyPackets,
                    startIndex: &bodyIndex
                ) {
                    meting.vetpercentage = bodyPacket.vet
                    meting.waterpercentage = bodyPacket.water
                    meting.spierpercentage = bodyPacket.spier
                    meting.botmassa = bodyPacket.bot
                    meting.kcal = bodyPacket.kcal
                }
                bodyIndicesPerPersoon[weightPacket.persoonId] = bodyIndex
            }

            resultaten.append(meting)
        }

        return resultaten
    }

    private func dichtstbijzijndeBodyPacket(
        voor weightPacket: BS444.WeightPacket,
        in bodyPackets: [BS444.BodyPacket],
        startIndex: inout Int
    ) -> BS444.BodyPacket? {
        guard !bodyPackets.isEmpty else { return nil }

        let vroegsteDatum = weightPacket.datum.addingTimeInterval(-3)
        while startIndex < bodyPackets.count && bodyPackets[startIndex].datum < vroegsteDatum {
            startIndex += 1
        }

        let geldigeKandidaten = [
            startIndex > 0 ? bodyPackets[startIndex - 1] : nil,
            startIndex < bodyPackets.count ? bodyPackets[startIndex] : nil,
            startIndex + 1 < bodyPackets.count ? bodyPackets[startIndex + 1] : nil
        ]
            .compactMap { $0 }
            .filter { abs($0.datum.timeIntervalSince(weightPacket.datum)) < 3.0 }

        return geldigeKandidaten.min {
            abs($0.datum.timeIntervalSince(weightPacket.datum))
                < abs($1.datum.timeIntervalSince(weightPacket.datum))
        }
    }

    private func ruimActieveImportCacheOp() {
        afrondenTimer?.invalidate()
        afrondenTimer = nil
        scanTimeoutTimer?.invalidate()
        scanTimeoutTimer = nil
        weightPackets.removeAll(keepingCapacity: false)
        bodyPackets.removeAll(keepingCapacity: false)
        aantalSubscriptions = 0
        vereisteSubscriptions = 0
        heeftTriggerVerzonden = false
        peripheral?.delegate = nil
        weightChar = nil
        bodyChar = nil
        personChar = nil
        cmdChar = nil
        peripheral = nil
    }

    private var heeftOntvangenMeetdata: Bool {
        !weightPackets.isEmpty || !bodyPackets.isEmpty
    }

    // Reset timer elke keer als er een packet binnenkomt
    private func herzetAfrondenTimer() {
        afrondenTimer?.invalidate()
        let timeout: TimeInterval = importModus == .laatsteMeting ? 1.25 : 2.5
        afrondenTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            self?.verwerkOntvangen()
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            status = .gereed
        case .poweredOff:
            status = .uitgeschakeld
        default:
            status = .uitgeschakeld
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        scanTimeoutTimer?.invalidate()
        scanTimeoutTimer = nil
        importVoortgang = max(importVoortgang, 0.22)
        central.stopScan()
        self.peripheral = peripheral
        status = .verbinden
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        scanTimeoutTimer?.invalidate()
        scanTimeoutTimer = nil
        importVoortgang = max(importVoortgang, 0.38)
        peripheral.delegate = self
        peripheral.discoverServices([BS444.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        status = .fout(error?.localizedDescription ?? "Verbinding mislukt")
        reset()
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        if case .verbonden = status {
            afrondenTimer?.invalidate()

            // De BS444 verbreekt de BLE-verbinding vaak zelf nadat alle metingen zijn verstuurd.
            // Als er al packets zijn ontvangen, behandelen we dit daarom als een normale afronding.
            if heeftOntvangenMeetdata {
                verwerkOntvangen()
            } else if let error {
                status = .fout("Verbinding verbroken: \(error.localizedDescription)")
                reset()
            } else {
                verwerkOntvangen()
            }
        } else if case .verbinden = status, let error {
            status = .fout("Verbinding verbroken: \(error.localizedDescription)")
            reset()
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == BS444.serviceUUID }) else {
            status = .fout("Service niet gevonden")
            return
        }
        peripheral.discoverCharacteristics(
            [BS444.weightUUID, BS444.bodyUUID, BS444.personUUID, BS444.cmdUUID],
            for: service
        )
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard let chars = service.characteristics else { return }
        status = .verbonden
        aantalSubscriptions = 0
        vereisteSubscriptions = 0

        for char in chars {
            switch char.uuid {
            case BS444.weightUUID:
                weightChar = char
                guard char.properties.contains(.notify) || char.properties.contains(.indicate) else {
                    status = .fout("Gewichtskarakteristiek ondersteunt geen notificaties")
                    central.cancelPeripheralConnection(peripheral)
                    return
                }
                vereisteSubscriptions += 1
                peripheral.setNotifyValue(true, for: char)
            case BS444.bodyUUID:
                bodyChar = char
                guard char.properties.contains(.notify) || char.properties.contains(.indicate) else {
                    status = .fout("Lichaamssamenstelling ondersteunt geen notificaties")
                    central.cancelPeripheralConnection(peripheral)
                    return
                }
                vereisteSubscriptions += 1
                peripheral.setNotifyValue(true, for: char)
            case BS444.personUUID:
                personChar = char
                if char.properties.contains(.notify) || char.properties.contains(.indicate) {
                    peripheral.setNotifyValue(true, for: char)
                }
            case BS444.cmdUUID:
                cmdChar = char
            default:
                break
            }
        }

        guard weightChar != nil, bodyChar != nil, cmdChar != nil else {
            status = .fout("Weegschaalprotocol onvolledig")
            central.cancelPeripheralConnection(peripheral)
            return
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error {
            if characteristic.uuid == BS444.personUUID {
                return
            }
            status = .fout("Notificatie mislukt: \(error.localizedDescription)")
            central.cancelPeripheralConnection(peripheral)
            return
        }

        guard characteristic.isNotifying else {
            if characteristic.uuid == BS444.personUUID {
                return
            }
            status = .fout("Notificaties niet actief voor metingen")
            central.cancelPeripheralConnection(peripheral)
            return
        }

        guard characteristic.uuid != BS444.personUUID else { return }
        aantalSubscriptions += 1
        let subscriptionVoortgang = 0.38 + (Double(aantalSubscriptions) / Double(max(vereisteSubscriptions, 1))) * 0.20
        importVoortgang = max(importVoortgang, subscriptionVoortgang)

        if aantalSubscriptions == vereisteSubscriptions, !heeftTriggerVerzonden {
            heeftTriggerVerzonden = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self else { return }
                guard self.status == .verbonden else { return }
                self.importVoortgang = max(self.importVoortgang, 0.62)
                self.stuurTriggerCommand()
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard let data = characteristic.value else { return }
        let bytes = [UInt8](data)

        switch characteristic.uuid {
        case BS444.weightUUID:
            if let packet = BS444.decodeWeight(bytes) {
                bewaarWeightPacket(packet)
                herzetAfrondenTimer()
            }
        case BS444.bodyUUID:
            if let packet = BS444.decodeBody(bytes) {
                bewaarBodyPacket(packet)
                herzetAfrondenTimer()
            }
        case BS444.personUUID:
            _ = BS444.decodePerson(bytes)
        default:
            break
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error = error {
            status = .fout("Commando mislukt: \(error.localizedDescription)")
        }
        // Nu wachten op de indications die de weegschaal stuurt
    }
}

private extension BluetoothManager {
    func bewaarWeightPacket(_ packet: BS444.WeightPacket) {
        guard importModus == .laatsteMeting else {
            weightPackets.append(packet)
            ontvangenMetingAantal = max(ontvangenMetingAantal, weightPackets.count)
            importVoortgang = max(importVoortgang, min(0.62 + Double(weightPackets.count) * 0.035, 0.9))
            return
        }

        guard let actiefPersoonId else {
            weightPackets = [meestRecenteWeightPacket(tussen: weightPackets.first, en: packet)]
            ontvangenMetingAantal = max(ontvangenMetingAantal, weightPackets.count)
            importVoortgang = max(importVoortgang, 0.84)
            return
        }

        guard packet.persoonId == actiefPersoonId else { return }

        if let index = weightPackets.firstIndex(where: { $0.persoonId == packet.persoonId }) {
            weightPackets[index] = meestRecenteWeightPacket(tussen: weightPackets[index], en: packet)
        } else {
            weightPackets = [packet]
        }
        ontvangenMetingAantal = max(ontvangenMetingAantal, weightPackets.count)
        importVoortgang = max(importVoortgang, 0.84)
    }

    func bewaarBodyPacket(_ packet: BS444.BodyPacket) {
        guard importModus == .laatsteMeting else {
            bodyPackets.append(packet)
            importVoortgang = max(importVoortgang, min(0.68 + Double(bodyPackets.count) * 0.02, 0.94))
            return
        }

        guard let actiefPersoonId else {
            bodyPackets = [meestRecenteBodyPacket(tussen: bodyPackets.first, en: packet)]
            importVoortgang = max(importVoortgang, 0.94)
            return
        }

        guard packet.persoonId == actiefPersoonId else { return }

        if let index = bodyPackets.firstIndex(where: { $0.persoonId == packet.persoonId }) {
            bodyPackets[index] = meestRecenteBodyPacket(tussen: bodyPackets[index], en: packet)
        } else {
            bodyPackets = [packet]
        }
        importVoortgang = max(importVoortgang, 0.94)
    }

    func meestRecenteWeightPacket(
        tussen bestaand: BS444.WeightPacket?,
        en nieuw: BS444.WeightPacket
    ) -> BS444.WeightPacket {
        guard let bestaand else { return nieuw }
        return nieuw.datum >= bestaand.datum ? nieuw : bestaand
    }

    func meestRecenteBodyPacket(
        tussen bestaand: BS444.BodyPacket?,
        en nieuw: BS444.BodyPacket
    ) -> BS444.BodyPacket {
        guard let bestaand else { return nieuw }
        return nieuw.datum >= bestaand.datum ? nieuw : bestaand
    }
}
