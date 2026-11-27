// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:convert';

import 'package:rosenweg_basis/rosenweg_basis.dart';

import 'daten.dart';

/// Alle Aufrufe der App gegen die Haupt-API (www.rosenweg4303.ch), dieselben
/// Endpunkte wie die Reparatur-PWA und reklamationen.html. Die Rechte prueft
/// die API selbst (requirePermission('reklamationen'), STWEG-Sicht in
/// api/lib/stweg-sicht.js); die App blendet nur aus, was ohnehin abgelehnt
/// wuerde.
class ReparaturApi {
  ReparaturApi(this.sitzung);
  final RosenwegSitzung sitzung;
  RosenwegApi get api => sitzung.api;

  static List<Map<String, dynamic>> _liste(Object? l) => [
    for (final e in l is List ? l : const [])
      if (e is Map<String, dynamic>) e,
  ];

  // ── Melden ──

  /// Ort eines Melde-QR-Codes; null = unbekannt oder abgeschaltet.
  Future<MeldeOrt?> meldeOrt(String code) async {
    try {
      final j = await api.objekt('/api/melde-ort/${Uri.encodeComponent(code)}');
      final o = j['ort'];
      return o is Map<String, dynamic> ? MeldeOrt.aus(code, o) : null;
    } on ApiFehler catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  /// Neue Meldung; liefert die Nummer. Das Foto ist schon verkleinert
  /// (FotoFeld) und geht wie bei der PWA als Data-URL im JSON mit.
  Future<int> melden({
    required String kategorie,
    required String beschreibung,
    int? stweg,
    String? standort,
    DateiDaten? foto,
  }) async {
    final j = await api.post('/api/reklamationen', {
      'kategorie': kategorie,
      'beschreibung': beschreibung,
      'stweg': stweg,
      if (standort != null && standort.trim().isNotEmpty) 'standort': standort.trim(),
      if (foto != null) 'foto_base64': 'data:${foto.typ};base64,${base64Encode(foto.bytes)}',
    });
    final r = j is Map ? j['reklamation'] : null;
    return r is Map && r['id'] is num ? (r['id'] as num).toInt() : 0;
  }

  // ── Meine Meldungen ──

  Future<List<Meldung>> meine() async {
    final j = await api.objekt('/api/reklamationen/meine');
    return [for (final r in _liste(j['reklamationen'])) Meldung.aus(r)];
  }

  Future<List<VerlaufEintrag>> meinVerlauf(int id) async {
    final j = await api.objekt('/api/reklamationen/meine/$id/verlauf');
    return [for (final e in _liste(j['events'])) VerlaufEintrag.aus(e)];
  }

  Future<DateiDaten> meinFoto(int id) =>
      sitzung.dateien.herunterladen('/api/reklamationen/meine/$id/foto', name: 'meldung-$id.jpg');

  /// Nur in der eigenen Liste ausblenden (Technik sieht sie weiter).
  Future<void> meineArchivieren(int id, bool archiviert) =>
      api.post('/api/reklamationen/$id/meine-archivieren', {'archiviert': archiviert});

  // ── Meine STWEG ──

  /// Meldungen einer STWEG (ohne Namen); [stweg] null = alle eigenen.
  Future<List<Meldung>> uebersicht({int? stweg}) async {
    final j = await api.objekt('/api/reklamationen/uebersicht${stweg == null ? '' : '?stweg=$stweg'}');
    return [for (final r in _liste(j['reklamationen'])) Meldung.aus(r)];
  }

  /// Was die Person darf; ohne den neuen Endpunkt aus den Gruppen.
  Future<ReparaturRechte> rechte() async {
    try {
      return ReparaturRechte.aus(await api.objekt('/api/reklamationen/rechte'));
    } on ApiFehler catch (e) {
      if (e.status != 404) rethrow;
      final r = await sitzung.rechte.laden();
      return ReparaturRechte.ausGruppen(r.gruppen);
    }
  }

  // ── Bearbeiten (Seitenrecht reklamationen) ──

  /// [ansicht]: `aktiv`, `abgeschlossen`, `archiviert`, `alle`.
  Future<List<Meldung>> bearbeiten(String ansicht) async {
    final q = switch (ansicht) {
      'aktiv' => '?status=offen,weitergeleitet',
      'abgeschlossen' => '?status=erledigt,abgewiesen',
      'archiviert' => '?archiviert=1',
      _ => '',
    };
    final j = await api.objekt('/api/reklamationen$q');
    return [for (final r in _liste(j['reklamationen'])) Meldung.aus(r)];
  }

  Future<Meldung> aendern(int id, Map<String, Object?> felder) async {
    final j = await api.put('/api/reklamationen/$id', felder);
    return Meldung.aus(j is Map<String, dynamic> ? j : const {});
  }

  Future<List<VerlaufEintrag>> verlauf(int id) async {
    final j = await api.objekt('/api/reklamationen/$id/history');
    return [for (final e in _liste(j['events'])) VerlaufEintrag.aus(e)];
  }

  /// Arbeitsschritt festhalten; geht an die meldende Person (WhatsApp/Push).
  Future<List<VerlaufEintrag>> schritt(int id, String text) async {
    final j = await api.post('/api/reklamationen/$id/history', {'text': text});
    return [for (final e in _liste(j is Map ? j['events'] : null)) VerlaufEintrag.aus(e)];
  }

  Future<DateiDaten> foto(int id) =>
      sitzung.dateien.herunterladen('/api/reklamationen/$id/foto', name: 'meldung-$id.jpg');

  /// Technik-Team und Handwerker fuer die Zuweisung. Handwerker braucht das
  /// Seitenrecht `handwerker`; fehlt es, bleibt nur die Technik (wie im Web).
  Future<List<Zustaendig>> zustaendige() async {
    final t = await api.objekt('/api/technik/mitglieder');
    final technik = [
      for (final m in _liste(t['mitglieder']))
        if ('${m['name'] ?? m['email'] ?? ''}'.isNotEmpty) Zustaendig.technik('${m['name'] ?? m['email']}'),
    ];
    var handwerker = <Zustaendig>[];
    try {
      final h = await api.get('/api/handwerker');
      final l = h is Map ? h['handwerker'] : h;
      handwerker = [
        for (final x in _liste(l))
          if (x['id'] is num)
            Zustaendig.handwerker((x['id'] as num).toInt(), '${x['firma'] ?? x['name'] ?? '#${x['id']}'}'),
      ];
    } on ApiFehler catch (e) {
      // 403 ohne Seitenrecht handwerker: nur die Technik zur Auswahl
      Protokoll.schreiben('Handwerker nicht geladen (${e.status})');
    }
    handwerker.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return [...technik, ...handwerker];
  }

  Future<List<AutoRegel>> autoRegeln(List<Zustaendig> zustaendige) async {
    final j = await api.objekt('/api/reklamationen/auto-assign');
    Zustaendig? finden(Map<String, dynamic> r) {
      final hw = r['handwerker_id'];
      if (hw is num) {
        return zustaendige.firstWhere(
          (z) => z.handwerkerId == hw.toInt(),
          orElse: () => Zustaendig.handwerker(hw.toInt(), 'Handwerker #$hw'),
        );
      }
      final n = r['zugewiesen_an'];
      return n is String && n.isNotEmpty ? Zustaendig.technik(n) : null;
    }

    return [
      for (final r in _liste(j['rules']))
        AutoRegel(kategorie: '${r['kategorie']}', stweg: (r['stweg'] as num?)?.toInt() ?? 0, zustaendig: finden(r)),
    ];
  }

  /// Regeln speichern (leere Zuweisung = Regel weg). Die API ueberspringt
  /// STWEGs, die die Person nicht aendern darf.
  Future<void> autoRegelnSpeichern(List<AutoRegel> regeln) => api.put('/api/reklamationen/auto-assign', {
    'rules': [for (final r in regeln) r.json],
  });
}
