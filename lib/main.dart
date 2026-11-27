// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:rosenweg_basis/rosenweg_basis.dart';

import 'abfrage.dart';
import 'app.dart';
import 'attrappe.dart';
import 'seiten/haupt.dart';

/// Abfrage im Hintergrund (Android WorkManager, iOS BGAppRefreshTask): eigener
/// Isolate, meldet still mit der bestehenden Anmeldung an, nie auf geteilten
/// Telefonen.
@pragma('vm:entry-point')
void hintergrund() => HintergrundAbfrage.ausfuehren(appAngaben, reparaturAbfrage);

/// rosenwegStarten (rosenweg_basis): Logdatei, Fehlerfang, Anmeldung
/// (Anmeldeschirm mit Karte, QR, Konto; an Stationen still per Kerberos;
/// auf geteilten Telefonen ueber Rosenweg Geraet) und der Updater
/// (aus auf Rosenweg-Stationen und mit Rosenweg Geraet). Erst danach kommt
/// [Haupt].
///
/// Die Abfrage im Hintergrund meldet erst [Haupt] beim System an, also nach
/// der Anmeldung; "Abmelden" meldet sie wieder ab.
void main() => rosenwegStarten(
  appAngaben,
  (sitzung) => Haupt(
    sitzung: sitzung,
    hintergrund: attrappe ? null : () => HintergrundAbfrage.anmelden(appAngaben, hintergrund),
  ),
  sitzung: attrappe ? attrappeSitzung(appAngaben) : null,
);
