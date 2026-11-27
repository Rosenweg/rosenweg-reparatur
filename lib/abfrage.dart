// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:rosenweg_basis/rosenweg_basis.dart';

import 'daten.dart';
import 'reparatur_api.dart';

/// Abfrage fuer Benachrichtigungen (ohne Push, ohne ntfy): Android etwa alle
/// 15 Minuten im Hintergrund, iOS wann iOS will, am Computer alle 5 Minuten,
/// solange die App laeuft.
///
///  * Statuswechsel bei den eigenen Meldungen → "Deine Meldung #41 ist
///    jetzt erledigt" (antippen = Bereich "Meine")
///  * Wer bearbeiten darf: Meldungen, die neu **dir** zugewiesen sind
///    (wie die WhatsApp-Nachricht der API an zugewiesene Technik-Mitglieder)
///    → antippen = Bereich "Bearbeiten"
///
/// Beim allerersten Lauf merkt sie sich nur den Stand (sonst kaeme fuer
/// jede alte Meldung eine Benachrichtigung).
Future<void> reparaturAbfrage(HintergrundKontext k) async {
  final api = ReparaturApi(k.sitzung);
  final meine = await api.meine();
  // vorher gemerkter Stand: eine eben selbst gemeldete (neu und offen) ist keine Neuigkeit
  final vorher = await k.speicher.lesen('neuigkeiten:meine');
  final bekannt = vorher is Map ? vorher.keys.map((x) => '$x').toSet() : const <String>{};
  final geaendert = await Neuigkeiten(
    k.speicher,
    'meine',
  ).vergleichen({for (final m in meine) '${m.id}': m.status.wert});
  for (final m in meine) {
    if (!geaendert.contains('${m.id}')) continue;
    if (!bekannt.contains('${m.id}') && m.status == Status.offen) continue;
    await Benachrichtigung.zeigen(
      id: Benachrichtigung.idFuer('meldung-${m.id}'),
      titel: 'Meldung #${m.id}: ${m.status.text}',
      text: m.beschreibung.length > 120 ? '${m.beschreibung.substring(0, 117)}…' : m.beschreibung,
      ziel: 'meine/${m.id}',
    );
  }

  final r = await k.sitzung.rechte.laden();
  final ich = r.name;
  if (!r.darf('reklamationen') || ich == null || ich.isEmpty) return;
  final aktiv = await api.bearbeiten('aktiv');
  // Stand je Meldung: wem sie zugewiesen ist; neu = jetzt mir, vorher nicht
  final zuMir = await Neuigkeiten(k.speicher, 'zugewiesen').vergleichen({
    for (final m in aktiv)
      if (m.zugewiesenAn == ich) '${m.id}': 'ich',
  });
  for (final m in aktiv) {
    if (!zuMir.contains('${m.id}')) continue;
    await Benachrichtigung.zeigen(
      id: Benachrichtigung.idFuer('zugewiesen-${m.id}'),
      titel: 'Dir zugewiesen: Meldung #${m.id}',
      text: '${m.kat.text}${m.stweg != null ? ' · ${stwegText(m.stweg)}' : ''}: ${m.beschreibung}',
      ziel: 'bearbeiten/${m.id}',
    );
  }
}
