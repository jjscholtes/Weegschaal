# Weegschaal App — Xcode Setup

## Vereisten
- Xcode 15 of nieuwer (gratis via App Store)
- iPhone met iOS 17+
- Apple ID (gratis, geen betaald Developer account nodig)

---

## Stap 1: Nieuw Xcode project aanmaken

1. Open Xcode
2. **File → New → Project**
3. Kies **iOS → App** → Next
4. Vul in:
   - **Product Name:** `Weegschaal`
   - **Team:** Selecteer je Apple ID (of "None" — je kunt dit later instellen)
   - **Organization Identifier:** `com.JOUWNAAMNAAM` (bijv. `com.jessescholtes`)
   - **Bundle Identifier:** wordt automatisch ingevuld
   - **Interface:** SwiftUI
   - **Storage:** SwiftData
   - **Language:** Swift
5. Klik **Next** en sla op in `/Users/jessescholtes/Development/Weegschaal/`
   - **Belangrijk:** sla op IN de `Weegschaal` map, niet erin (Xcode maakt zelf een submap)

---

## Stap 2: Bronbestanden toevoegen

De bronbestanden staan in `/Users/jessescholtes/Development/Weegschaal/Weegschaal/`.

1. In Xcode: klik rechts op de **Weegschaal** map in de linker bestandsstructuur
2. Kies **Add Files to "Weegschaal"**
3. Navigeer naar `/Users/jessescholtes/Development/Weegschaal/Weegschaal/`
4. Selecteer alle `.swift` bestanden:
   - `WeegschaalApp.swift`
   - `Models.swift`
   - `BluetoothManager.swift`
   - `HealthKitManager.swift`
   - `ContentView.swift`
   - `DashboardView.swift`
   - `GeschiedenisView.swift`
   - `InstellingenView.swift`
5. Vink **"Copy items if needed"** NIET aan (ze staan al op de juiste plek)
6. Klik **Add**

**Let op:** Verwijder de standaard `ContentView.swift` die Xcode zelf aanmaakt als die er al staat (rechts klik → Delete → Move to Trash).

---

## Stap 3: Capabilities toevoegen

### Bluetooth
1. Klik op het **Weegschaal** project (bovenaan de bestandslijst)
2. Selecteer het **Weegschaal** target
3. Ga naar het tabblad **Info**
4. Klik op het **+** icoon onder "Custom iOS Target Properties"
5. Voeg toe:
   - Key: `NSBluetoothAlwaysUsageDescription`
   - Value: `Weegschaal heeft Bluetooth nodig om verbinding te maken met je Medisana BS 444`

### HealthKit
1. Ga naar het tabblad **Signing & Capabilities**
2. Klik op **+ Capability**
3. Zoek en voeg toe: **HealthKit**
4. Vink aan: **Clinical Health Records** NIET, alleen de basis HealthKit

---

## Stap 4: Signing instellen (om op iPhone te installeren)

1. Ga naar **Signing & Capabilities**
2. Zorg dat **Automatically manage signing** aangevinkt is
3. Selecteer bij **Team** je Apple ID
4. Als je nog geen Apple ID toegevoegd hebt: **Xcode → Settings → Accounts → + → Apple ID**

**Let op met gratis account:** De app verloopt na **7 dagen**. Je hoeft dan alleen opnieuw op **Run** te klikken (met iPhone verbonden via USB).

---

## Stap 5: App op je iPhone zetten

1. Verbind je iPhone via USB
2. Vertrouw de computer op je iPhone als dat gevraagd wordt
3. Selecteer je iPhone in de toolbar (naast de Play knop)
4. Druk op **▶ Run** (Cmd+R)
5. Op je iPhone: **Instellingen → Algemeen → VPN en apparaatbeheer → [jouw Apple ID] → Vertrouwen**

---

## Gebruik van de app

1. **Stap op de weegschaal** — wacht tot hij een meting heeft gedaan
2. **Open de app** op je iPhone
3. Tik op **"Nieuwe meting ophalen"**
4. De app verbindt automatisch via Bluetooth
5. Alle opgeslagen metingen worden ingeladen (max 30 stuks)
6. Ga naar **Instellingen** en stel je **Persoon ID** in (standaard 1)

### Persoon ID
De BS 444 kan tot 8 gebruikersprofielen opslaan. Als je de enige gebruiker bent, is dit gewoon persoon 1. Als er meerdere mensen de weegschaal gebruiken, kies dan het juiste nummer.

---

## Bestandsoverzicht

| Bestand | Functie |
|---------|---------|
| `WeegschaalApp.swift` | App entry point, SwiftData container |
| `Models.swift` | Data modellen (Meting, Profiel) |
| `BluetoothManager.swift` | Bluetooth verbinding + BS 444 protocol |
| `HealthKitManager.swift` | Apple Health integratie |
| `ContentView.swift` | Tab navigatie |
| `DashboardView.swift` | Huidige meting + verbindknop |
| `GeschiedenisView.swift` | Historische metingen + grafiek |
| `InstellingenView.swift` | Profiel instellingen |
