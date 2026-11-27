// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:rosenweg_basis/rosenweg_basis.dart';

/// Antwortet wie die Haupt-API (Reklamationen, Melde-Orte, Technik,
/// Handwerker), mit erfundenen Daten – keine echten Personen, Firmen oder
/// Meldungen. Fuer Tests, Bildschirmfotos und Entwicklung ohne Server
/// (--dart-define=RW_ATTRAPPE=1).
///
/// Melde-QR-Code zum Ausprobieren (eintippen): `waschk9a`
/// (https://pwa.rosenweg4303.ch/reparatur/?ort=waschk9a).
class Attrappe implements Transport {
  Attrappe({
    this.gruppen = const ['r9-eigentuemer', 'stweg3-ausschuss'],
    this.recht = 'write',
    this.mitRechteEndpunkt = true,
  });

  /// Gruppen der angemeldeten Person.
  final List<String> gruppen;

  /// Seitenrecht `reklamationen`: 'write', 'read' oder null (keins).
  final String? recht;

  /// false = API ohne GET /api/reklamationen/rechte (vor dem Ausrollen).
  final bool mitRechteEndpunkt;

  /// Alle Anfragen in der Reihenfolge (fuer Tests).
  final anfragen = <({String methode, String pfad, Object? koerper})>[];

  /// Naechste Antwort fuer einen Pfad erzwingen (Tests).
  final erzwungen = <String, ApiAntwort>{};

  static const ich = 'erika.muster@example.org';

  late final _meldungen = <Map<String, dynamic>>[
    {
      'id': 41,
      'person_id': 7,
      'person_name': 'Erika Muster',
      'person_email': ich,
      'stweg': 3,
      'kategorie': 'licht',
      'beschreibung': 'Licht im Treppenhaus 2. OG brennt nicht mehr.',
      'standort': 'Haus 9, Treppenhaus 2. OG',
      'status': 'weitergeleitet',
      'bild_pfad': 'stweg3/reklamationen/rekl-1.jpg',
      'zugewiesen_an': 'Max Beispiel',
      'handwerker_id': null,
      'notiz': 'Leuchtmittel bestellt',
      'archiviert': false,
      'melder_archiviert': false,
      'created_at': '2026-11-24T08:15:00Z',
      'erledigt_am': null,
    },
    {
      'id': 38,
      'person_id': 12,
      'person_name': 'Lea Probe',
      'person_email': 'lea.probe@example.org',
      'stweg': 3,
      'kategorie': 'wasser',
      'beschreibung': 'Wasserhahn in der Waschküche tropft.',
      'standort': 'Waschküche Haus 9',
      'status': 'offen',
      'bild_pfad': null,
      'zugewiesen_an': null,
      'handwerker_id': null,
      'notiz': null,
      'archiviert': false,
      'melder_archiviert': false,
      'created_at': '2026-11-26T17:40:00Z',
      'erledigt_am': null,
    },
    {
      'id': 35,
      'person_id': 7,
      'person_name': 'Erika Muster',
      'person_email': ich,
      'stweg': 3,
      'kategorie': 'tuer',
      'beschreibung': 'Haustür schliesst nicht mehr von selbst.',
      'standort': 'Haus 9, Eingang',
      'status': 'erledigt',
      'bild_pfad': null,
      'zugewiesen_an': null,
      'handwerker_id': 3,
      'notiz': 'Türschliesser eingestellt',
      'archiviert': false,
      'melder_archiviert': false,
      'created_at': '2026-11-10T07:05:00Z',
      'erledigt_am': '2026-11-12T15:30:00Z',
    },
    {
      'id': 30,
      'person_id': null,
      'person_name': null,
      'person_email': null,
      'stweg': null,
      'kategorie': 'netzwerk',
      'beschreibung': 'WLAN im Velokeller sehr schwach.',
      'standort': 'Velokeller',
      'status': 'offen',
      'bild_pfad': null,
      'zugewiesen_an': null,
      'handwerker_id': null,
      'notiz': null,
      'archiviert': false,
      'melder_archiviert': false,
      'created_at': '2026-11-20T19:00:00Z',
      'erledigt_am': null,
    },
  ];

  final _verlauf = <int, List<Map<String, dynamic>>>{
    41: [
      {
        'created_at': '2026-11-24T08:15:00Z',
        'who': ich,
        'event': 'Erstellt (Web-Formular) · 📍 Haus 9, Treppenhaus 2. OG',
        'an_melder': false,
      },
      {
        'created_at': '2026-11-24T08:15:02Z',
        'who': 'System',
        'event': 'Auto-zugewiesen an: Max Beispiel',
        'an_melder': false,
      },
      {
        'created_at': '2026-11-25T10:00:00Z',
        'who': 'Max Beispiel',
        'event': 'Status: offen → weitergeleitet',
        'an_melder': false,
      },
      {
        'created_at': '2026-11-25T10:01:00Z',
        'who': 'Max Beispiel',
        'event': '🔧 Leuchtmittel bestellt, Einbau Freitag',
        'an_melder': true,
      },
    ],
  };

  static const _handwerker = [
    {'id': 3, 'firma': 'Muster Schlosserei AG'},
    {'id': 5, 'firma': 'Beispiel Elektro GmbH'},
  ];

  final _regeln = <Map<String, dynamic>>[
    {'kategorie': 'licht', 'stweg': 0, 'zugewiesen_an': 'Max Beispiel', 'handwerker_id': null},
    {'kategorie': 'tuer', 'stweg': 3, 'zugewiesen_an': null, 'handwerker_id': 3},
  ];

  int _naechste = 42;

  Map<String, dynamic> get _ich => {
    'id': 7,
    'username': 'erika.muster',
    'name': 'Erika Muster',
    'email': ich,
    'groups': gruppen,
    'permissions': {'dashboard': 'read', 'reklamationen': ?recht},
  };

  bool get _alles => gruppen.any((g) => const ['technik', 'präsident', 'praesident'].contains(g.toLowerCase()));

  /// Sicht wie lib/stweg-sicht.js (vereinfacht fuer die Vorfuehrung).
  bool _sieht(Map<String, dynamic> m) {
    if (_alles) return true;
    final ausschuss = gruppen.contains('stweg3-ausschuss') || gruppen.contains('stweg3-verwaltung');
    if (ausschuss) return m['stweg'] == 3 || (m['stweg'] == null && gruppen.contains('stweg3-ausschuss'));
    return m['person_email'] == ich;
  }

  Map<String, dynamic> _melder(Map<String, dynamic> m) => {
    for (final k in [
      'id',
      'kategorie',
      'beschreibung',
      'status',
      'standort',
      'created_at',
      'erledigt_am',
      'melder_archiviert',
    ])
      k: m[k],
    'has_bild': m['bild_pfad'] != null,
  };

  @override
  Future<ApiAntwort> senden(String methode, String pfad, {Object? koerper}) async {
    anfragen.add((methode: methode, pfad: pfad, koerper: koerper));
    final z = erzwungen.remove('$methode $pfad');
    if (z != null) return z;
    final uri = Uri.parse(pfad);
    final weg = uri.path;
    final k = koerper is Map ? koerper.cast<String, Object?>() : const <String, Object?>{};
    final teile = weg.split('/');
    final id = teile.length > 3 ? int.tryParse(teile[3]) : null;
    Map<String, dynamic>? finde() => id == null ? null : _meldungen.where((m) => m['id'] == id).firstOrNull;
    bool darf(String zugriff) => _alles || recht == 'write' || (zugriff == 'read' && recht == 'read');

    switch ('$methode $weg') {
      case 'GET /api/auth/me':
        return (status: 200, json: {'user': _ich});
      case 'GET /api/reklamationen/rechte':
        if (!mitRechteEndpunkt) return (status: 404, json: {'error': 'Nicht gefunden'});
        return (
          status: 200,
          json: {
            'eigene_stwegs': [3],
            'uebersicht_stwegs': _alles ? [1, 2, 3, 4, 5, 6, 7, 8] : [3],
            'auto_assign_stwegs': _alles
                ? [0, 1, 2, 3, 4, 5, 6, 7, 8]
                : (gruppen.contains('stweg3-ausschuss') ? [3] : <int>[]),
          },
        );
      case 'GET /api/reklamationen/meine':
        return (
          status: 200,
          json: {
            'reklamationen': [
              for (final m in _meldungen)
                if (m['person_email'] == ich) _melder(m),
            ],
          },
        );
      case 'GET /api/reklamationen/uebersicht':
        final s = int.tryParse(uri.queryParameters['stweg'] ?? '') ?? 3;
        return (
          status: 200,
          json: {
            'reklamationen': [
              for (final m in _meldungen)
                if (m['stweg'] == s || m['stweg'] == null)
                  {
                    for (final f in ['id', 'kategorie', 'beschreibung', 'status', 'stweg', 'created_at', 'erledigt_am'])
                      f: m[f],
                    'in_bearbeitung': m['zugewiesen_an'] != null || m['handwerker_id'] != null,
                  },
            ],
            'stwegs': [s],
          },
        );
      case 'POST /api/reklamationen':
        final b = '${k['beschreibung'] ?? ''}'.trim();
        if (b.isEmpty) return (status: 400, json: {'error': 'Beschreibung erforderlich'});
        final n = _naechste++;
        _meldungen.insert(0, {
          'id': n,
          'person_id': 7,
          'person_name': 'Erika Muster',
          'person_email': ich,
          'stweg': k['stweg'],
          'kategorie': k['kategorie'] ?? 'sonstige',
          'beschreibung': b,
          'standort': k['standort'],
          'status': 'offen',
          'bild_pfad': k['foto_base64'] == null ? null : 'x.jpg',
          'zugewiesen_an': null,
          'handwerker_id': null,
          'notiz': null,
          'archiviert': false,
          'melder_archiviert': false,
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'erledigt_am': null,
        });
        return (
          status: 200,
          json: {
            'ok': true,
            'reklamation': {'id': n, 'status': 'offen'},
          },
        );
      case 'GET /api/reklamationen':
        if (!darf('read')) return (status: 403, json: {'error': 'Keine Berechtigung'});
        final st = (uri.queryParameters['status'] ?? '').split(',').where((x) => x.isNotEmpty).toSet();
        final arch = uri.queryParameters['archiviert'] == '1';
        return (
          status: 200,
          json: {
            'reklamationen': [
              for (final m in _meldungen)
                if (_sieht(m) && (st.isEmpty || st.contains(m['status'])) && m['archiviert'] == arch)
                  {
                    ...m,
                    'handwerker_firma': _handwerker.where((h) => h['id'] == m['handwerker_id']).firstOrNull?['firma'],
                  },
            ],
          },
        );
      case 'GET /api/technik/mitglieder':
        return (
          status: 200,
          json: {
            'mitglieder': [
              {'name': 'Max Beispiel', 'email': 'max.beispiel@example.org'},
              {'name': 'Nora Technik', 'email': 'nora.technik@example.org'},
            ],
          },
        );
      case 'GET /api/handwerker':
        return (status: 200, json: {'handwerker': _handwerker});
      case 'GET /api/reklamationen/auto-assign':
        return (status: 200, json: {'rules': _regeln});
      case 'PUT /api/reklamationen/auto-assign':
        for (final r in (k['rules'] as List? ?? const [])) {
          final m = (r as Map).cast<String, Object?>();
          _regeln.removeWhere((x) => x['kategorie'] == m['kategorie'] && x['stweg'] == m['stweg']);
          if (m['zugewiesen_an'] != null || m['handwerker_id'] != null) _regeln.add(m);
        }
        return (status: 200, json: {'ok': true});
      case 'GET /api/melde-ort/waschk9a':
        return (
          status: 200,
          json: {
            'ort': {'name': 'Waschküche Haus 9', 'stweg': 3, 'kategorie': 'wasser'},
          },
        );
    }
    if (methode == 'GET' && weg.startsWith('/api/melde-ort/')) {
      return (status: 404, json: {'error': 'Ort nicht gefunden'});
    }

    if (methode == 'GET' && teile.length > 4 && teile[3] == 'meine') {
      final mm = _meldungen.where((x) => x['id'] == int.tryParse(teile[4])).firstOrNull;
      if (mm != null && teile.length > 5 && teile[5] == 'verlauf') {
        final v = _verlauf[mm['id']] ?? const [];
        return (
          status: 200,
          json: {
            'events': [
              for (final e in v)
                if (e['an_melder'] == true ||
                    '${e['event']}'.startsWith('Erstellt') ||
                    '${e['event']}'.startsWith('Status: '))
                  e,
            ],
          },
        );
      }
    }
    // /api/reklamationen/:id/…
    final m = finde();
    if (m == null) return (status: 404, json: {'error': 'Nicht gefunden: $methode $pfad'});
    final rest = teile.length > 4 ? teile.sublist(4).join('/') : '';
    switch ('$methode $rest') {
      case 'PUT ':
        if (!darf('write') || !_sieht(m)) return (status: 404, json: {'error': 'Nicht gefunden'});
        final alt = m['status'];
        for (final f in ['status', 'kategorie', 'notiz', 'zugewiesen_an', 'handwerker_id', 'archiviert']) {
          if (k.containsKey(f)) m[f] = k[f];
        }
        if (k['status'] != null && k['status'] != alt) {
          (_verlauf[m['id'] as int] ??= []).add({
            'created_at': DateTime.now().toUtc().toIso8601String(),
            'who': 'Erika Muster',
            'event': 'Status: $alt → ${k['status']}',
            'an_melder': false,
          });
        }
        return (status: 200, json: m);
      case 'GET history':
        return (status: 200, json: {'events': _verlauf[m['id']] ?? const []});
      case 'POST history':
        final e = {
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'who': 'Erika Muster',
          'event': '🔧 ${k['text']}',
          'an_melder': true,
        };
        (_verlauf[m['id'] as int] ??= []).add(e);
        return (status: 200, json: {'ok': true, 'events': _verlauf[m['id']]});
      case 'POST meine-archivieren':
        m['melder_archiviert'] = k['archiviert'] == true;
        return (status: 200, json: {'ok': true});
    }
    return (status: 404, json: {'error': 'Nicht gefunden: $methode $pfad'});
  }
}

class _Fest implements Zugangsquelle {
  @override
  Future<String?> zugangsToken() async => 'vorfuehrung';
  @override
  void zugangUngueltig() {}
}

/// Fotos der Vorfuehrung: ein erfundenes Bild (kein echtes Foto).
RosenwegDateien attrappeDateien() => RosenwegDateien(
  basis: 'https://beispiel.invalid',
  zugang: _Fest(),
  client: MockClient((r) async {
    if (r.url.path.endsWith('/foto')) {
      return http.Response.bytes(_bild(), 200, headers: {'content-type': 'image/png'});
    }
    return http.Response(jsonEncode({'error': 'Nicht gefunden.'}), 404);
  }),
);

/// Sitzung mit Vorfuehrdaten (main.dart, Tests, Bildschirmfotos).
RosenwegSitzung attrappeSitzung(RosenwegApp app, [Attrappe? a]) =>
    RosenwegSitzung(app, transport: a ?? Attrappe())..dateien = attrappeDateien();

Uint8List _bild() {
  final b = img.Image(width: 320, height: 200);
  img.fill(b, color: img.ColorRgb8(226, 232, 240));
  img.fillRect(b, x1: 130, y1: 20, x2: 190, y2: 60, color: img.ColorRgb8(120, 120, 120));
  img.fillCircle(b, x: 160, y: 95, radius: 34, color: img.ColorRgb8(250, 204, 21));
  return Uint8List.fromList(img.encodePng(b));
}
