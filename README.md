<p align="center"><img src="assets/logo/rosenweg-reparatur-512.png" width="96" alt="Logo"></p>
<h1 align="center">Rosenweg Reparatur</h1>
<p align="center">Schäden melden mit Foto, eigene Meldungen verfolgen, Meldungen der STWEG ansehen und bearbeiten.</p>
<p align="center"><a href="docs/anleitung.md">Anleitung</a> · <a href="https://www.rosenweg4303.ch/apps">Herunterladen</a></p>

Angelegt mit `werkzeug/neue-app.sh` aus der App-Vorlage von
[rosenweg-basis](https://github.com/Rosenweg/rosenweg-basis). Anmeldung, API,
Gerüst, Updater und Logo kommen aus der Basis; hier steht nur, was diese App
eigen macht.

## Läuft auf

| Plattform | Datei | Grenzen |
|---|---|---|
| Linux (Debian 13, Stationen und eigene Rechner) | `rosenweg-reparatur_<version>_amd64.deb` | Stationen bekommen das Paket vom PXE-Server (os-stationen), dort ist der Updater aus |
| Android 8 und neuer | `rosenweg-reparatur-<version>.apk` (Rosenweg-Schlüssel) | auf geteilten Telefonen meldet Rosenweg Gerät an und ab |
| Windows 10/11 | `Rosenweg-Reparatur-<version>-Setup.exe` | unsigniert, solange kein Code-Signing-Zertifikat da ist (SmartScreen fragt einmal) |
| macOS 11 und neuer | `Rosenweg-Reparatur-<version>.dmg` | ohne Apple Developer ID ad hoc signiert (Gatekeeper fragt beim ersten Start) |
| iOS/iPadOS | – | baut in CI ohne Signatur, verteilt wird erst mit dem Apple Developer Program |

Herunterladen: [www.rosenweg4303.ch/apps](https://www.rosenweg4303.ch/apps).

## Bedienung

Siehe [docs/anleitung.md](docs/anleitung.md).

## Was die App macht

Ein Vorgang von der Meldung bis zur Erledigung – ersetzt in der App
`pwa/reparatur/` (angemeldet), `reklamationen.html` und die STWEG-Seiten
`stwegN/pages/reklamationen.html`. Die Web-Seiten bleiben, auch der öffentliche
Teil (Melde-Ort-QR ohne Konto).

| Bereich | Wer | API |
|---|---|---|
| Melden | alle | `POST /api/reklamationen` (Foto als Data-URL, vorher verkleinert), `GET /api/melde-ort/:code` |
| Meine | alle | `/api/reklamationen/meine`, `…/meine/:id/verlauf`, `…/meine/:id/foto`, `…/:id/meine-archivieren` |
| STWEG | Bewohner/Eigentümer/Ausschuss/Verwaltung der STWEG | `/api/reklamationen/uebersicht?stweg=N` |
| Bearbeiten | Seitenrecht `reklamationen` (ändern: `write`) | `/api/reklamationen`, `PUT …/:id`, `…/:id/history`, `…/:id/foto`, `/api/technik/mitglieder`, `/api/handwerker`, `…/auto-assign` |

Welche STWEG jemand sieht und ändern darf, liefert `GET /api/reklamationen/rechte`
(fehlt der Endpunkt, leitet die App es aus den Gruppen ab); die API prüft
jede Anfrage selbst. Push: keiner (kein ntfy) – Abfrage beim Öffnen,
bei Rückkehr und alle 5 Minuten (`BeimOeffnen`, `Neuigkeiten` aus der Basis).

## Entwickeln

```sh
# rosenweg-basis daneben auschecken, dann lokal gegen sie bauen:
printf 'dependency_overrides:\n  rosenweg_basis:\n    path: ../rosenweg-basis\n' > pubspec_overrides.yaml
flutter pub get
flutter run -d macos                       # oder linux, windows, ein Handy
flutter run -d macos --dart-define=RW_ATTRAPPE=1   # ohne Server, mit Vorführdaten (lib/attrappe.dart)
flutter analyze && flutter test
RW_FOTO=$HOME/Downloads flutter test test/bildschirmfoto_test.dart   # Bildschirmfotos
```

Vor dem Commit `pubspec_overrides.yaml` entfernen und `flutter pub get` laufen lassen –
`pubspec.lock` darf nicht auf `../rosenweg-basis` zeigen (die CI bricht sonst ab).

| Ordner | Inhalt |
|---|---|
| `lib/app.dart` | `RosenwegApp`: Kennung `ch.rosenweg4303.reparatur`, Name, Logo |
| `lib/seiten/` | die Seiten der App (`RosenwegGeruest`: Handy unten, Desktop links) |
| `lib/attrappe.dart` | Vorführdaten statt der API (Tests, Bildschirmfotos) |
| `assets/logo/` | Logo aus dem Baukasten der Basis: `sh assets/logo/erzeugen.sh ../rosenweg-basis` |
| `linux/paket/` | Debian-Paket (`bauen.sh`, im Bau-Container `im-container.sh`), `paket.conf` = Vorlage für os-stationen |
| `macos/installer/` | DMG (`bauen.sh`) |
| `windows/installer/` | Inno-Setup-Installer |
| `.github/workflows/` | `app.yml` (Bau, Release) und `apps.yml` (an /apps) – die Arbeit macht rosenweg-basis |

## Veröffentlichen

1. Version in `pubspec.yaml` erhöhen (`version: x.y.z+n`, Baunummer immer mit).
2. Pull Request, CI grün (Linux und Android), Merge auf main.
3. Die CI baut alle fünf Plattformen, legt das Release `vx.y.z` an und schickt
   APK, `.deb`, DMG und Installer an `/apps`. Ohne neue Version passiert nach dem
   Merge nur die CI.
4. Stationen: `linux/paket/paket.conf` in os-stationen (`pakete/rosenweg-reparatur/`)
   mit Version und Prüfsumme nachführen.

## Lizenz

GPL-3.0-or-later, siehe [LICENSE](LICENSE). Logo-Zeichen: siehe rosenweg-basis
`werkzeug/logo/zeichen/LIZENZEN.md`.
