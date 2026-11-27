// SPDX-License-Identifier: GPL-3.0-or-later
/// Daten der Reparatur-Meldungen, wie sie die Haupt-API liefert
/// (api/server.js, Abschnitt "Reklamationen-API").
library;

import 'package:flutter/material.dart';

/// Kategorien wie die Reparatur-PWA und reklamationen.html (Wert → Text).
class Kategorie {
  const Kategorie(this.wert, this.text, this.symbol);
  final String wert;
  final String text;
  final IconData symbol;

  static const alle = [
    Kategorie('aufzug', 'Aufzug', Icons.elevator_outlined),
    Kategorie('heizung', 'Heizung', Icons.local_fire_department_outlined),
    Kategorie('wasser', 'Wasser', Icons.water_drop_outlined),
    Kategorie('tuer', 'Tür/Schloss', Icons.door_front_door_outlined),
    Kategorie('reinigung', 'Reinigung', Icons.cleaning_services_outlined),
    Kategorie('licht', 'Licht', Icons.lightbulb_outline),
    Kategorie('strom', 'Strom', Icons.bolt_outlined),
    Kategorie('netzwerk', 'Netzwerk', Icons.wifi),
    Kategorie('salz', 'Salz', Icons.grain),
    Kategorie('sonstige', 'Sonstiges', Icons.help_outline),
  ];

  static Kategorie von(String? wert) => alle.firstWhere(
    (k) => k.wert == wert,
    orElse: () => Kategorie(wert ?? 'sonstige', wert ?? 'Sonstiges', Icons.help_outline),
  );
}

/// Status einer Meldung.
enum Status {
  offen('offen', 'Offen'),
  weitergeleitet('weitergeleitet', 'Weitergeleitet'),
  erledigt('erledigt', 'Erledigt'),
  abgewiesen('abgewiesen', 'Abgewiesen');

  const Status(this.wert, this.text);
  final String wert;
  final String text;

  static Status von(Object? w) => values.firstWhere((s) => s.wert == w, orElse: () => offen);
  bool get abgeschlossen => this == erledigt || this == abgewiesen;

  Color farbe(ColorScheme f) => switch (this) {
    offen => const Color(0xFF92400E),
    weitergeleitet => const Color(0xFF1E40AF),
    erledigt => const Color(0xFF065F46),
    abgewiesen => const Color(0xFF991B1B),
  };
}

/// "STWEG 3", "MEG" (8) oder "Allgemein" (null).
String stwegText(int? n) => n == null ? 'Allgemein' : (n == 8 ? 'MEG' : 'STWEG $n');

DateTime? _zeit(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
int? _zahl(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}'));
String? _text(Object? v) => v == null || '$v'.trim().isEmpty ? null : '$v';

/// Eine Meldung. Je nach Endpunkt sind nur Teile gefuellt:
///  * `/meine`: eigene, mit Foto-Merker und "fuer mich archiviert"
///  * `/uebersicht`: STWEG-Brett ohne Namen der meldenden Person
///  * `/api/reklamationen`: Bearbeiten, mit Zuweisung, Notiz, Person
class Meldung {
  const Meldung({
    required this.id,
    required this.kategorie,
    required this.beschreibung,
    required this.status,
    this.stweg,
    this.standort,
    this.erstellt,
    this.erledigtAm,
    this.hatFoto = false,
    this.melderArchiviert = false,
    this.archiviert = false,
    this.inBearbeitung = false,
    this.personId,
    this.personName,
    this.zugewiesenAn,
    this.handwerkerId,
    this.handwerkerFirma,
    this.notiz,
    this.mitNotiz = false,
  });

  factory Meldung.aus(Map<String, dynamic> j) => Meldung(
    id: _zahl(j['id']) ?? 0,
    kategorie: '${j['kategorie'] ?? 'sonstige'}',
    beschreibung: '${j['beschreibung'] ?? ''}',
    status: Status.von(j['status']),
    stweg: _zahl(j['stweg']),
    standort: _text(j['standort']),
    erstellt: _zeit(j['created_at']),
    erledigtAm: _zeit(j['erledigt_am']),
    hatFoto: j['has_bild'] == true || _text(j['bild_pfad']) != null,
    melderArchiviert: j['melder_archiviert'] == true,
    archiviert: j['archiviert'] == true,
    inBearbeitung: j['in_bearbeitung'] == true,
    personId: _zahl(j['person_id']),
    personName: _text(j['person_name']),
    zugewiesenAn: _text(j['zugewiesen_an']),
    handwerkerId: _zahl(j['handwerker_id']),
    handwerkerFirma: _text(j['handwerker_firma']),
    notiz: _text(j['notiz']),
    // Die API schickt die Notiz nur an Bearbeitende (nie an die meldende Person)
    mitNotiz: j.containsKey('notiz'),
  );

  final int id;
  final String kategorie;
  final String beschreibung;
  final Status status;
  final int? stweg;
  final String? standort;
  final DateTime? erstellt;
  final DateTime? erledigtAm;
  final bool hatFoto;
  final bool melderArchiviert;
  final bool archiviert;
  final bool inBearbeitung;
  final int? personId;
  final String? personName;
  final String? zugewiesenAn;
  final int? handwerkerId;
  final String? handwerkerFirma;
  final String? notiz;

  /// Antwort enthielt das Feld `notiz` (Sicht der Bearbeitenden).
  final bool mitNotiz;

  Kategorie get kat => Kategorie.von(kategorie);

  /// Zuweisung als Text ("—" = niemand).
  String get zuweisungText =>
      handwerkerFirma ?? (handwerkerId != null ? 'Handwerker #$handwerkerId' : (zugewiesenAn ?? '—'));

  Zustaendig? get zustaendig => handwerkerId != null
      ? Zustaendig.handwerker(handwerkerId!, handwerkerFirma ?? '#$handwerkerId')
      : (zugewiesenAn != null ? Zustaendig.technik(zugewiesenAn!) : null);
}

/// Eintrag im Verlauf einer Meldung.
class VerlaufEintrag {
  const VerlaufEintrag({required this.zeit, required this.wer, required this.text});
  factory VerlaufEintrag.aus(Map<String, dynamic> j) =>
      VerlaufEintrag(zeit: _zeit(j['created_at']), wer: _text(j['who']), text: '${j['event'] ?? ''}');
  final DateTime? zeit;
  final String? wer;
  final String text;
}

/// Ort eines Melde-QR-Codes (`GET /api/melde-ort/:code`).
class MeldeOrt {
  const MeldeOrt({required this.code, required this.name, this.stweg, this.kategorie});
  factory MeldeOrt.aus(String code, Map<String, dynamic> j) =>
      MeldeOrt(code: code, name: '${j['name'] ?? ''}', stweg: _zahl(j['stweg']), kategorie: _text(j['kategorie']));
  final String code;
  final String name;
  final int? stweg;
  final String? kategorie;

  /// Code aus dem Inhalt eines QR-Codes: Link mit `?ort=<code>`
  /// (https://pwa.rosenweg4303.ch/reparatur/?ort=abcd2345) oder der Code
  /// allein. null = passt nicht.
  static String? codeAus(String inhalt) {
    final t = inhalt.trim();
    final uri = Uri.tryParse(t);
    final q = uri?.queryParameters['ort'];
    if (q != null && RegExp(r'^[A-Za-z0-9_-]{4,40}$').hasMatch(q)) return q;
    if (RegExp(r'^[A-Za-z0-9_-]{4,40}$').hasMatch(t)) return t;
    return null;
  }
}

/// Wer kuemmert sich: ein Technik-Mitglied (Name) oder ein Handwerker (Id).
class Zustaendig {
  const Zustaendig.technik(this.name) : handwerkerId = null, istHandwerker = false;
  const Zustaendig.handwerker(int id, this.name) : handwerkerId = id, istHandwerker = true;
  final String name;
  final int? handwerkerId;
  final bool istHandwerker;

  String get art => istHandwerker ? 'Handwerker' : 'Technik';

  @override
  bool operator ==(Object other) =>
      other is Zustaendig &&
      other.istHandwerker == istHandwerker &&
      (istHandwerker ? other.handwerkerId == handwerkerId : other.name == name);

  @override
  int get hashCode => Object.hash(istHandwerker, istHandwerker ? handwerkerId : name);
}

/// Regel der automatischen Zuweisung (je Kategorie und STWEG; 0 = alle).
class AutoRegel {
  const AutoRegel({required this.kategorie, required this.stweg, this.zustaendig});
  final String kategorie;
  final int stweg;
  final Zustaendig? zustaendig;

  Map<String, Object?> get json => {
    'kategorie': kategorie,
    'stweg': stweg,
    'zugewiesen_an': zustaendig != null && !zustaendig!.istHandwerker ? zustaendig!.name : null,
    'handwerker_id': zustaendig?.handwerkerId,
  };
}

/// Was die angemeldete Person in der Reparatur darf (GET
/// /api/reklamationen/rechte; die API prueft trotzdem jede Anfrage selbst).
class ReparaturRechte {
  const ReparaturRechte({this.eigeneStwegs = const [], this.uebersichtStwegs = const [], this.autoStwegs = const []});

  /// STWEG(s) der Person (Vorschlag beim Melden).
  final List<int> eigeneStwegs;

  /// STWEGs fuer "Meine STWEG" (Bewohner, Eigentuemer, Ausschuss,
  /// Verwaltung der STWEG; Technik/Praesident alle).
  final List<int> uebersichtStwegs;

  /// STWEGs, deren automatische Zuweisung die Person aendern darf
  /// (0 = "alle STWEG", nur Technik/Praesident).
  final List<int> autoStwegs;

  factory ReparaturRechte.aus(Map<String, dynamic> j) {
    List<int> l(Object? v) => [for (final x in v is List ? v : const []) ?_zahl(x)];
    return ReparaturRechte(
      eigeneStwegs: l(j['eigene_stwegs']),
      uebersichtStwegs: l(j['uebersicht_stwegs']),
      autoStwegs: l(j['auto_assign_stwegs']),
    );
  }

  /// Ersatz, solange die API den Endpunkt noch nicht hat: dieselben Regeln
  /// aus den Gruppen (api/lib/groups.js, lib/stweg-sicht.js).
  factory ReparaturRechte.ausGruppen(List<String> gruppen) {
    final g = {for (final x in gruppen) x.toLowerCase()};
    final alles = g.contains('technik') || g.contains('präsident') || g.contains('praesident');
    final eigene = <int>{};
    final ausschuss = <int>{};
    final verwaltung = <int>{};
    for (final e in _stwegGruppen.entries) {
      if (e.value.any(g.contains)) eigene.add(e.key);
      if (g.contains(e.value.last)) ausschuss.add(e.key);
      if (g.contains(e.key == 8 ? 'meg-verwaltung' : 'stweg${e.key}-verwaltung')) verwaltung.add(e.key);
    }
    // Uebergang: alte globale Gruppe "verwaltung" = alle STWEGs
    if (g.contains('verwaltung')) verwaltung.addAll(_stwegGruppen.keys);
    final alle = [for (var i = 1; i <= 8; i++) i];
    return ReparaturRechte(
      eigeneStwegs: eigene.toList()..sort(),
      uebersichtStwegs: alles ? alle : ({...eigene, ...verwaltung}.toList()..sort()),
      autoStwegs: alles ? [0, ...alle] : ({...ausschuss, ...verwaltung}.toList()..sort()),
    );
  }

  // bewohner, eigentuemer, ausschuss (api/lib/groups.js STWEG_GROUPS)
  static const _stwegGruppen = {
    1: ['stweg1-bewohner', 'stweg1-eigentuemer', 'stweg1-ausschuss'],
    2: ['stweg2-bewohner', 'stweg2-eigentuemer', 'stweg2-ausschuss'],
    3: ['r9-bewohner', 'r9-eigentuemer', 'stweg3-ausschuss'],
    4: ['stweg4-bewohner', 'stweg4-eigentuemer', 'stweg4-ausschuss'],
    5: ['stweg5-bewohner', 'stweg5-eigentuemer', 'stweg5-ausschuss'],
    6: ['r1-bewohner', 'r1-eigentuemer', 'stweg6-ausschuss'],
    7: ['stweg7-bewohner', 'stweg7-eigentuemer', 'stweg7-ausschuss'],
    8: ['meg-bewohner', 'meg-eigentuemer', 'meg-ausschuss'],
  };
}

/// "27.11.2026, 14:05".
String wannText(DateTime? z) {
  if (z == null) return '';
  String zz(int n) => n.toString().padLeft(2, '0');
  return '${zz(z.day)}.${zz(z.month)}.${z.year}, ${zz(z.hour)}:${zz(z.minute)}';
}

/// "27.11.2026".
String tagText(DateTime? z) => z == null ? '' : wannText(z).split(',').first;
