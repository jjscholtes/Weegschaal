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

// MARK: - BluetoothManager

final class BluetoothManager: NSObject, ObservableObject {
    @Published var status: BluetoothStatus = .gereed
    @Published var nieuweMetingen: [MetingData] = []

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?

    private var weightChar: CBCharacteristic?
    private var bodyChar: CBCharacteristic?
    private var personChar: CBCharacteristic?
    private var cmdChar: CBCharacteristic?

    // Houd bij hoeveel subscriptions bevestigd zijn (we wachten op 3)
    private var aantalSubscriptions = 0

    // Tijdelijk opvangen van packets
    private var weightPackets: [BS444.WeightPacket] = []
    private var bodyPackets: [BS444.BodyPacket] = []

    // Timer om te detecteren dat de weegschaal klaar is met sturen
    private var afrondenTimer: Timer?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func startScan() {
        guard central.state == .poweredOn else {
            status = .uitgeschakeld
            return
        }
        reset()
        status = .scannen
        central.scanForPeripherals(withServices: [BS444.serviceUUID], options: nil)
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
        weightPackets = []
        bodyPackets = []
        aantalSubscriptions = 0
        weightChar = nil
        bodyChar = nil
        personChar = nil
        cmdChar = nil
        peripheral = nil
    }

    private func stuurTriggerCommand() {
        guard let p = peripheral, let cmd = cmdChar else { return }
        let data = BS444.triggerCommand()
        p.writeValue(data, for: cmd, type: .withResponse)
    }

    // Na ontvangst van alle data: koppel weight- en body-packets en maak MetingData objecten
    private func verwerkOntvangen() {
        afrondenTimer?.invalidate()

        var resultaten: [MetingData] = []
        for w in weightPackets {
            var meting = MetingData(datum: w.datum, gewicht: w.gewicht, persoonId: w.persoonId)
            if let body = bodyPackets.first(where: {
                $0.persoonId == w.persoonId && abs($0.datum.timeIntervalSince(w.datum)) < 3.0
            }) {
                meting.vetpercentage    = body.vet
                meting.waterpercentage  = body.water
                meting.spierpercentage  = body.spier
                meting.botmassa         = body.bot
                meting.kcal             = body.kcal
            }
            resultaten.append(meting)
        }

        // Sorteer van oud naar nieuw
        nieuweMetingen = resultaten.sorted { $0.datum < $1.datum }
        status = .gereed

        if let p = peripheral {
            central.cancelPeripheralConnection(p)
        }
    }

    // Reset timer elke keer als er een packet binnenkomt
    private func herzetAfrondenTimer() {
        afrondenTimer?.invalidate()
        afrondenTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
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
        central.stopScan()
        self.peripheral = peripheral
        status = .verbinden
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
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
        // Alleen fout tonen als we bezig waren (niet bij bewuste disconnect)
        if case .verbonden = status {
            verwerkOntvangen()
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

        for char in chars {
            switch char.uuid {
            case BS444.weightUUID:
                weightChar = char
                peripheral.setNotifyValue(true, for: char)
            case BS444.bodyUUID:
                bodyChar = char
                peripheral.setNotifyValue(true, for: char)
            case BS444.personUUID:
                personChar = char
                peripheral.setNotifyValue(true, for: char)
            case BS444.cmdUUID:
                cmdChar = char
            default:
                break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard characteristic.isNotifying else { return }
        aantalSubscriptions += 1
        // Stuur trigger zodra alle 3 characteristics gesubscribed zijn
        if aantalSubscriptions >= 3 {
            stuurTriggerCommand()
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
                weightPackets.append(packet)
                herzetAfrondenTimer()
            }
        case BS444.bodyUUID:
            if let packet = BS444.decodeBody(bytes) {
                bodyPackets.append(packet)
                herzetAfrondenTimer()
            }
        case BS444.personUUID:
            // Persoonsprofiel van de weegschaal — negeren, we gebruiken ons eigen profiel
            _ = BS444.decodePerson(bytes)
            herzetAfrondenTimer()
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
