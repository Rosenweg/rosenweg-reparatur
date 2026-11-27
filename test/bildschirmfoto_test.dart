// SPDX-License-Identifier: GPL-3.0-or-later
//
// Bildschirmfotos mit den Vorfuehrdaten (Attrappe), nur auf Wunsch:
//   RW_FOTO=$HOME/Downloads flutter test test/bildschirmfoto_test.dart
// Laedt Roboto und die Material-Symbole aus dem Flutter-SDK, sonst zeigen
// Widget-Tests nur Kaesten. Muster: rosenweg-profil.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';
import 'package:rosenweg_reparatur/app.dart';
import 'package:rosenweg_reparatur/attrappe.dart';
import 'package:rosenweg_reparatur/seiten/haupt.dart';

final ziel = Platform.environment['RW_FOTO'];

Future<void> schriften() async {
  final sdk = File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.parent.path;
  final ordner =
      ['$sdk/artifacts/material_fonts', '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts']
          .map(Directory.new)
          .firstWhere(
            (d) => d.existsSync(),
            orElse: () => Directory('/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts'),
          );
  Future<void> laden(String familie, List<String> dateien) async {
    final l = FontLoader(familie);
    for (final d in dateien) {
      l.addFont(Future.value(ByteData.sublistView(File('${ordner.path}/$d').readAsBytesSync())));
    }
    await l.load();
  }

  await laden('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
  await laden('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

Future<void> foto(WidgetTester t, String datei) async {
  final rb = t.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
  final bild = await t.runAsync(() => rb.toImage(pixelRatio: 2));
  final png = await t.runAsync(() => bild!.toByteData(format: ui.ImageByteFormat.png));
  File('$ziel/$datei').writeAsBytesSync(png!.buffer.asUint8List());
}

void main() {
  setUpAll(() async {
    Protokoll.nurKonsole = true;
    if (ziel != null) await schriften();
  });

  Future<void> zeigen(WidgetTester t, Size groesse, {Phase? phase, String? bereich}) async {
    t.view.physicalSize = groesse * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(const SizedBox()); // alten Baum (auch offene Seiten) verwerfen
    final s = attrappeSitzung(appAngaben);
    await s.starten();
    if (phase != null) s.phase = phase;
    await t.pumpWidget(
      RepaintBoundary(
        child: RosenwegRahmen(
          sitzung: s,
          inhalt: (_) => Haupt(sitzung: s, speicher: AppSpeicher.imSpeicher()),
        ),
      ),
    );
    await t.runAsync(() => precacheImage(appAngaben.logo!, t.element(find.byType(MaterialApp))));
    await t.runAsync(
      () => precacheImage(
        const AssetImage('assets/logo/rosenweg-reparatur-klein.png'),
        t.element(find.byType(MaterialApp)),
      ),
    );
    await t.pumpAndSettle();
    if (bereich != null) {
      await t.pump(const Duration(milliseconds: 100));
      await t.pumpAndSettle();
      await t.tap(
        find.widgetWithText(NavigationDestination, bereich).evaluate().isNotEmpty
            ? find.widgetWithText(NavigationDestination, bereich)
            : find.descendant(of: find.byType(NavigationRail), matching: find.text(bereich)),
      );
      await t.pumpAndSettle();
    }
  }

  Future<void> warten(WidgetTester t) async {
    await t.pump();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pumpAndSettle();
  }

  testWidgets('Fotos', (t) async {
    await zeigen(t, const Size(412, 860));
    await foto(t, 'rosenweg-reparatur-melden.png');
    await zeigen(t, const Size(412, 860), bereich: 'Meine');
    await foto(t, 'rosenweg-reparatur-meine.png');
    await t.tap(find.textContaining('Licht im Treppenhaus'));
    await warten(t);
    await foto(t, 'rosenweg-reparatur-meine-detail.png');
    await zeigen(t, const Size(412, 860), bereich: 'STWEG');
    await foto(t, 'rosenweg-reparatur-stweg.png');
    await zeigen(t, const Size(1200, 800), bereich: 'Bearbeiten');
    await foto(t, 'rosenweg-reparatur-station.png');
    await t.tap(find.textContaining('Wasserhahn'));
    await warten(t);
    await foto(t, 'rosenweg-reparatur-bearbeiten.png');
    await zeigen(t, const Size(412, 860), phase: Phase.abgemeldet);
    await foto(t, 'rosenweg-reparatur-anmelden.png');
  }, skip: ziel == null);
}
