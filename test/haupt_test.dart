// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';
import 'package:rosenweg_reparatur/app.dart';
import 'package:rosenweg_reparatur/attrappe.dart';
import 'package:rosenweg_reparatur/daten.dart';
import 'package:rosenweg_reparatur/reparatur_api.dart';
import 'package:rosenweg_reparatur/seiten/haupt.dart';
import 'package:rosenweg_reparatur/seiten/melden.dart';

Finder bereich(String titel) => find.widgetWithText(NavigationDestination, titel);

Future<void> sichtbar(WidgetTester t, Finder f) async {
  // Meldungen unten (Snackbar) koennen Knoepfe verdecken
  for (final m in t.stateList<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))) {
    m.removeCurrentSnackBar();
  }
  await t.pump();
  await t.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
  await t.pumpAndSettle();
}

/// Echte Zeit fuer das Foto (http-Attrappe, Bild dekodieren), dann ruhig.
Future<void> warten(WidgetTester t) async {
  await t.pump();
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  await t.pumpAndSettle();
}

void main() {
  setUpAll(() => Protokoll.nurKonsole = true);

  Future<Attrappe> zeigen(
    WidgetTester t, {
    Size groesse = const Size(412, 900),
    Attrappe? a,
    AppSpeicher? speicher,
  }) async {
    t.view.physicalSize = groesse;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final at = a ?? Attrappe();
    final s = attrappeSitzung(appAngaben, at);
    await s.starten();
    await t.pumpWidget(
      RosenwegRahmen(
        sitzung: s,
        inhalt: (_) => Haupt(sitzung: s, speicher: speicher ?? AppSpeicher.imSpeicher()),
      ),
    );
    await t.pumpAndSettle();
    return at;
  }

  testWidgets('Bereiche je nach Recht: Ausschuss sieht Bearbeiten und STWEG', (t) async {
    await zeigen(t);
    for (final b in ['Melden', 'Meine', 'STWEG', 'Bearbeiten']) {
      expect(bereich(b), findsOneWidget, reason: b);
    }
  });

  testWidgets('Bewohner ohne Seitenrecht: kein Bearbeiten', (t) async {
    await zeigen(t, a: Attrappe(gruppen: const ['r9-bewohner'], recht: null));
    expect(bereich('Bearbeiten'), findsNothing);
    expect(bereich('STWEG'), findsOneWidget);
  });

  testWidgets('Ohne STWEG-Gruppe und ohne Rechte-Endpunkt: kein STWEG-Bereich', (t) async {
    await zeigen(t, a: Attrappe(gruppen: const ['handwerker-extern'], recht: null, mitRechteEndpunkt: false));
    expect(bereich('STWEG'), findsNothing);
    expect(bereich('Meine'), findsOneWidget);
  });

  testWidgets('Melden: Pflichtfelder, dann senden mit Danke', (t) async {
    final a = await zeigen(t);
    await sichtbar(t, find.text('Meldung senden'));
    await t.tap(find.text('Meldung senden'));
    await t.pumpAndSettle();
    expect(find.text('Bitte eine Kategorie wählen.'), findsOneWidget);
    await sichtbar(t, find.text('Licht'));
    await t.tap(find.text('Licht'));
    await t.enterText(find.widgetWithText(TextFormField, 'Was ist kaputt? *'), 'Lampe im Keller defekt');
    await sichtbar(t, find.text('Meldung senden'));
    await t.tap(find.text('Meldung senden'));
    await t.pumpAndSettle();
    expect(find.textContaining('Danke! Deine Meldung #42 ist eingegangen.'), findsOneWidget);
    final post = a.anfragen.lastWhere((r) => r.methode == 'POST' && r.pfad == '/api/reklamationen');
    final k = post.koerper as Map;
    expect(k['kategorie'], 'licht');
    expect(k['stweg'], 3, reason: 'eigene STWEG vorgeschlagen');
    expect(k.containsKey('foto_base64'), isFalse);
    await t.tap(find.text('Weitere Meldung'));
    await t.pumpAndSettle();
    expect(find.text('Kategorie *'), findsOneWidget);
    expect(find.text('Lampe im Keller defekt'), findsNothing);
  });

  testWidgets('Melde-Ort per QR fuellt Ort, STWEG und Kategorie', (t) async {
    final a = Attrappe(gruppen: const ['stweg1-bewohner']);
    final s = attrappeSitzung(appAngaben, a);
    await s.starten();
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MeldenSeite(
            api: ReparaturApi(s),
            rechte: const ReparaturRechte(eigeneStwegs: [1]),
            scannen: (_) async => 'https://pwa.rosenweg4303.ch/reparatur/?ort=waschk9a',
          ),
        ),
      ),
    );
    await t.tap(find.text('QR-Code am Ort scannen'));
    await t.pumpAndSettle();
    expect(find.text('Waschküche Haus 9'), findsWidgets);
    await t.enterText(find.widgetWithText(TextFormField, 'Was ist kaputt? *'), 'Hahn tropft');
    await sichtbar(t, find.text('Meldung senden'));
    await t.tap(find.text('Meldung senden'));
    await t.pumpAndSettle();
    final k = a.anfragen.lastWhere((r) => r.methode == 'POST').koerper as Map;
    expect(k['stweg'], 3);
    expect(k['kategorie'], 'wasser');
    expect(k['standort'], 'Waschküche Haus 9');
  });

  test('Melde-Ort: Code aus Link oder allein', () {
    expect(MeldeOrt.codeAus('https://pwa.rosenweg4303.ch/reparatur/?ort=ab3dk9xz'), 'ab3dk9xz');
    expect(MeldeOrt.codeAus(' ab3dk9xz '), 'ab3dk9xz');
    expect(MeldeOrt.codeAus('https://example.org/'), isNull);
    expect(MeldeOrt.codeAus('<script>'), isNull);
  });

  testWidgets('Meine: Liste, Verlauf mit Arbeitsschritt, ausblenden', (t) async {
    final a = await zeigen(t);
    await t.tap(bereich('Meine'));
    await t.pumpAndSettle();
    expect(find.textContaining('Licht im Treppenhaus'), findsOneWidget);
    expect(find.textContaining('Wasserhahn'), findsNothing, reason: 'fremde Meldung');
    await t.tap(find.textContaining('Licht im Treppenhaus'));
    await warten(t);
    expect(find.text('🔧 Leuchtmittel bestellt, Einbau Freitag'), findsOneWidget);
    expect(find.textContaining('Auto-zugewiesen'), findsNothing, reason: 'interner Eintrag');
    await t.tap(find.byTooltip('Ausblenden'));
    await t.pumpAndSettle();
    await t.tap(find.text('Ausblenden'));
    await t.pumpAndSettle();
    expect(a.anfragen.any((r) => r.pfad == '/api/reklamationen/41/meine-archivieren'), isTrue);
    expect(find.textContaining('Ausgeblendete zeigen (1)'), findsOneWidget);
  });

  testWidgets('STWEG: ohne Namen, offen und abgeschlossen getrennt', (t) async {
    await zeigen(t);
    await t.tap(bereich('STWEG'));
    await t.pumpAndSettle();
    expect(find.text('In Arbeit (3)'), findsOneWidget);
    expect(find.text('Abgeschlossen (1)'), findsOneWidget);
    expect(find.textContaining('Erika Muster'), findsNothing);
  });

  testWidgets('Bearbeiten: Status und Zuweisung an Handwerker, Nachricht nur bei Statuswechsel', (t) async {
    final a = await zeigen(t);
    await t.tap(bereich('Bearbeiten'));
    await t.pumpAndSettle();
    // ohne STWEG: der Ausschuss sieht sie (lib/stweg-sicht.js ohneStweg)
    expect(find.textContaining('WLAN im Velokeller'), findsOneWidget);
    await t.tap(find.textContaining('Wasserhahn'));
    await t.pumpAndSettle();
    expect(find.textContaining('Nachricht an'), findsNothing);
    await t.tap(find.text('Offen').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Weitergeleitet').last);
    await t.pumpAndSettle();
    expect(find.textContaining('Nachricht an Lea Probe'), findsOneWidget);
    await t.enterText(
      find.widgetWithText(TextFormField, 'Nachricht an Lea Probe (freiwillig)'),
      'Handwerker kommt Montag',
    );
    await sichtbar(t, find.text('Zuständig'));
    await t.tap(find.text('Zuständig'), warnIfMissed: false);
    await t.pumpAndSettle();
    await t.tap(find.text('Muster Schlosserei AG'));
    await t.pumpAndSettle();
    await sichtbar(t, find.text('Speichern'));
    await t.tap(find.text('Speichern'));
    await t.pumpAndSettle();
    final put = a.anfragen.lastWhere((r) => r.methode == 'PUT');
    expect(put.pfad, '/api/reklamationen/38');
    final k = put.koerper as Map;
    expect(k['status'], 'weitergeleitet');
    expect(k['handwerker_id'], 3);
    expect(k['zugewiesen_an'], isNull);
    expect(k['melder_bemerkung'], 'Handwerker kommt Montag');
  });

  testWidgets('Bearbeiten nur lesen: kein Speichern, keine automatische Zuweisung', (t) async {
    await zeigen(
      t,
      a: Attrappe(gruppen: const ['r9-eigentuemer'], recht: 'read'),
    );
    await t.tap(bereich('Bearbeiten'));
    await t.pumpAndSettle();
    expect(find.text('Automatische Zuweisung'), findsNothing);
    await t.tap(find.textContaining('Licht im Treppenhaus'));
    await warten(t);
    expect(find.text('Speichern'), findsNothing);
    expect(find.text('Arbeitsschritt festhalten'), findsNothing);
  });

  testWidgets('Automatische Zuweisung: nur eigene STWEG, speichert alle Kategorien', (t) async {
    final a = await zeigen(t);
    await t.tap(bereich('Bearbeiten'));
    await t.pumpAndSettle();
    await t.tap(find.text('Automatische Zuweisung'));
    await t.pumpAndSettle();
    expect(find.text('Für STWEG 3'), findsOneWidget);
    expect(find.text('Muster Schlosserei AG (Handwerker)'), findsOneWidget);
    await sichtbar(t, find.text('Speichern'));
    await t.tap(find.text('Speichern'));
    await t.pumpAndSettle();
    final put = a.anfragen.lastWhere((r) => r.methode == 'PUT');
    final regeln = (put.koerper as Map)['rules'] as List;
    expect(regeln.length, Kategorie.alle.length);
    expect(regeln.every((r) => (r as Map)['stweg'] == 3), isTrue);
    expect(regeln.firstWhere((r) => (r as Map)['kategorie'] == 'tuer')['handwerker_id'], 3);
  });

  testWidgets('Abfrage beim Oeffnen: neuer Stand der eigenen Meldung', (t) async {
    final sp = AppSpeicher.imSpeicher();
    // Stand vom letzten Mal: #41 war noch offen
    await Neuigkeiten(sp, 'meine').vergleichen({'41': 'offen', '35': 'erledigt'});
    await Neuigkeiten(sp, 'bearbeiten').vergleichen({'41': 'da'});
    await zeigen(t, speicher: sp);
    expect(find.textContaining('Deine Meldung #41 ist jetzt „Weitergeleitet“.'), findsOneWidget);
    expect(find.textContaining('2 neue Meldungen zum Bearbeiten.'), findsOneWidget);
    await t.tap(bereich('Meine'));
    await t.pumpAndSettle();
    expect(find.text('Neu'), findsOneWidget);
  });

  test('Rechte aus den Gruppen (ohne neuen Endpunkt)', () {
    final b = ReparaturRechte.ausGruppen(['r9-bewohner']);
    expect(b.eigeneStwegs, [3]);
    expect(b.uebersichtStwegs, [3]);
    expect(b.autoStwegs, isEmpty);
    final v = ReparaturRechte.ausGruppen(['stweg5-verwaltung']);
    expect(v.eigeneStwegs, isEmpty);
    expect(v.uebersichtStwegs, [5]);
    expect(v.autoStwegs, [5]);
    final t = ReparaturRechte.ausGruppen(['technik']);
    expect(t.autoStwegs.first, 0);
    expect(t.uebersichtStwegs.length, 8);
  });

  test('Kennung, Ordner und Logo passen zusammen', () {
    expect(appAngaben.kennung, 'ch.rosenweg4303.reparatur');
    expect(appAngaben.gruppe, RosenwegGruppe.bewohner);
    expect(File('assets/logo/${appAngaben.ordner}-512.png').existsSync(), isTrue);
    expect(File('assets/logo/${appAngaben.ordner}-klein.png').existsSync(), isTrue);
  });
}
