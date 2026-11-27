// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

import '../daten.dart';
import '../reparatur_api.dart';
import 'haupt.dart';

/// Bearbeiten (ersetzt reklamationen.html): Meldungen sichten, Status,
/// Kategorie, Zuweisung an Technik oder Handwerker, interne Notiz,
/// Nachricht an die meldende Person, Arbeitsschritte, archivieren; dazu die
/// automatische Zuweisung je Kategorie und STWEG.
///
/// Sichtbar mit dem Seitenrecht `reklamationen` (lesen); aendern mit
/// `schreiben` (Technik/Praesident immer). Welche Meldungen jemand sieht,
/// entscheidet die API: Technik/Praesident alle, Ausschuss und Verwaltung die
/// ihrer STWEG(s), sonst nur die eigenen.
class BearbeitenSeite extends StatefulWidget {
  const BearbeitenSeite({
    super.key,
    required this.api,
    required this.schreiben,
    required this.rechte,
    required this.neu,
  });
  final ReparaturApi api;
  final bool schreiben;
  final ReparaturRechte? rechte;
  final ValueNotifier<Set<int>> neu;

  @override
  State<BearbeitenSeite> createState() => _BearbeitenSeiteState();
}

class _BearbeitenSeiteState extends State<BearbeitenSeite> {
  String _ansicht = 'aktiv';
  List<Zustaendig>? _zustaendige;

  late final _liste = ListenSteuerung<Meldung>.lokal(
    alle: () => widget.api.bearbeiten(_ansicht),
    suchText: (m) => [
      '#${m.id}',
      m.beschreibung,
      m.kat.text,
      stwegText(m.stweg),
      m.standort ?? '',
      m.personName ?? '',
      m.zuweisungText,
    ].join(' '),
    schluessel: (m) => m.id,
    filter: [
      ListenFilter(id: 'offen', titel: 'Offen', passt: (m) => m.status == Status.offen),
      ListenFilter(id: 'ohne', titel: 'Niemand zugewiesen', passt: (m) => m.zustaendig == null),
    ],
    sortierer: {
      'nr': (a, b) => a.id.compareTo(b.id),
      'stweg': (a, b) => (a.stweg ?? 0).compareTo(b.stweg ?? 0),
      'status': (a, b) => a.status.index.compareTo(b.status.index),
    },
  );

  @override
  void dispose() {
    _liste.dispose();
    super.dispose();
  }

  Future<List<Zustaendig>> _zustaendigeLaden() async => _zustaendige ??= await widget.api.zustaendige();

  Future<void> _oeffnen(Meldung m) async {
    widget.neu.value = {...widget.neu.value}..remove(m.id);
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            MeldungBearbeiten(api: widget.api, m: m, schreiben: widget.schreiben, zustaendige: _zustaendigeLaden),
      ),
    );
    // auch ohne Speichern: ein Arbeitsschritt kann den Stand geaendert haben
    await _liste.neuLaden();
  }

  void _ansichtWechseln(String a) {
    setState(() => _ansicht = a);
    _liste.neuLaden();
  }

  @override
  Widget build(BuildContext context) {
    final auto = widget.schreiben && (widget.rechte?.autoStwegs.isNotEmpty ?? false);
    return ValueListenableBuilder<Set<int>>(
      valueListenable: widget.neu,
      builder: (context, neuNr, _) => RosenwegListe<Meldung>(
        steuerung: _liste,
        suchHinweis: 'Nummer, Text, Person, Ort suchen',
        leerText: switch (_ansicht) {
          'aktiv' => 'Keine offenen Meldungen.',
          'abgeschlossen' => 'Keine abgeschlossenen Meldungen.',
          _ => 'Nichts archiviert.',
        },
        kopf: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'aktiv', label: Text('In Arbeit')),
                ButtonSegment(value: 'abgeschlossen', label: Text('Abgeschlossen')),
                ButtonSegment(value: 'archiviert', label: Text('Archiv')),
              ],
              selected: {_ansicht},
              showSelectedIcon: false,
              onSelectionChanged: (s) => _ansichtWechseln(s.first),
            ),
            if (auto)
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AutoZuweisung(
                      api: widget.api,
                      stwegs: widget.rechte!.autoStwegs,
                      zustaendige: _zustaendigeLaden,
                    ),
                  ),
                ),
                icon: const Icon(Icons.rule),
                label: const Text('Automatische Zuweisung'),
              ),
          ],
        ),
        antippen: _oeffnen,
        spalten: [
          ListenSpalte(id: 'nr', titel: 'Nr.', text: (m) => '#${m.id}', breite: 70, sortierbar: true),
          ListenSpalte(id: 'datum', titel: 'Gemeldet', text: (m) => tagText(m.erstellt), breite: 100),
          ListenSpalte(id: 'stweg', titel: 'STWEG', text: (m) => stwegText(m.stweg), breite: 90, sortierbar: true),
          ListenSpalte(
            id: 'was',
            titel: 'Meldung',
            flex: 4,
            zelle: (context, m) => Row(
              children: [
                if (neuNr.contains(m.id)) const Padding(padding: EdgeInsets.only(right: 6), child: NeuSchild()),
                Expanded(
                  child: Text(
                    '${m.kat.text}: ${m.standort != null ? '${m.standort} · ' : ''}${m.beschreibung}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          ListenSpalte(id: 'wer', titel: 'Zuständig', text: (m) => m.zuweisungText, flex: 2),
          ListenSpalte(
            id: 'status',
            titel: 'Status',
            zelle: (_, m) => Align(alignment: Alignment.centerLeft, child: StatusSchild(m.status)),
            breite: 130,
            sortierbar: true,
          ),
        ],
        kachel: (context, m) => MeldungKachel(
          m: m,
          neu: neuNr.contains(m.id),
          zeigeStweg: true,
          antippen: () => _oeffnen(m),
          unten: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              [if (m.personName != null) 'von ${m.personName}', 'zuständig: ${m.zuweisungText}'].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ),
    );
  }
}

/// Eine Meldung bearbeiten. Ohne Schreibrecht nur ansehen.
class MeldungBearbeiten extends StatefulWidget {
  const MeldungBearbeiten({
    super.key,
    required this.api,
    required this.m,
    required this.schreiben,
    required this.zustaendige,
  });
  final ReparaturApi api;
  final Meldung m;
  final bool schreiben;
  final Future<List<Zustaendig>> Function() zustaendige;

  @override
  State<MeldungBearbeiten> createState() => _MeldungBearbeitenState();
}

class _MeldungBearbeitenState extends State<MeldungBearbeiten> {
  late final Meldung _m = widget.m;
  late Status _status = _m.status;
  late String _kategorie = _m.kategorie;
  late Zustaendig? _wer = _m.zustaendig;
  late final _notiz = TextEditingController(text: _m.notiz ?? '');
  final _nachricht = TextEditingController();
  final _schritt = TextEditingController();
  List<VerlaufEintrag>? _verlauf;
  Object? _verlaufFehler;
  bool _schrittLaeuft = false;

  @override
  void initState() {
    super.initState();
    _verlaufLaden();
  }

  @override
  void dispose() {
    _notiz.dispose();
    _nachricht.dispose();
    _schritt.dispose();
    super.dispose();
  }

  Future<void> _verlaufLaden() async {
    try {
      final v = await widget.api.verlauf(_m.id);
      if (mounted) setState(() => _verlauf = v);
    } catch (e) {
      if (mounted) setState(() => _verlaufFehler = e);
    }
  }

  /// Die Nachricht an die meldende Person geht nur mit einem Statuswechsel
  /// (wie reklamationen.html) und nur, wenn es eine meldende Person gibt.
  bool get _nachrichtMoeglich => _m.personId != null && _m.mitNotiz && _status != _m.status;

  Future<void> _speichern() async {
    final w = _wer;
    final felder = <String, Object?>{
      'status': _status.wert,
      'kategorie': _kategorie,
      'notiz': _notiz.text,
      'zugewiesen_an': w == null || w.istHandwerker ? null : w.name,
      'handwerker_id': w?.handwerkerId,
      if (_nachrichtMoeglich && _nachricht.text.trim().isNotEmpty) 'melder_bemerkung': _nachricht.text.trim(),
    };
    await widget.api.aendern(_m.id, felder);
  }

  Future<void> _archivieren() async {
    final weg = !_m.archiviert;
    if (weg &&
        !await frage(
          context,
          'Meldung archivieren?',
          'Sie verschwindet aus „In Arbeit“ und „Abgeschlossen“. Die meldende Person wird nicht benachrichtigt. Im „Archiv“ holst du sie zurück.',
          ja: 'Archivieren',
        )) {
      return;
    }
    try {
      await widget.api.aendern(_m.id, {'archiviert': weg});
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) zeigeMeldung(context, fehlerText(e), fehler: true);
    }
  }

  Future<void> _schrittSpeichern() async {
    final text = _schritt.text.trim();
    if (text.isEmpty) return;
    setState(() => _schrittLaeuft = true);
    try {
      final v = await widget.api.schritt(_m.id, text);
      _schritt.clear();
      if (mounted) setState(() => _verlauf = v);
    } catch (e) {
      if (mounted) zeigeMeldung(context, fehlerText(e), fehler: true);
    } finally {
      if (mounted) setState(() => _schrittLaeuft = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final m = _m;
    final kopf = [
      MeldungKachel(
        m: m,
        zeigeStweg: true,
        unten: m.personName == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('von ${m.personName}', style: t.bodySmall),
              ),
      ),
      if (m.hatFoto)
        Abschnitt(
          titel: 'Foto',
          symbol: Icons.photo_outlined,
          kind: GeladenesBild(laden: () => widget.api.foto(m.id), titel: 'Foto zu #${m.id}'),
        ),
    ];
    final verlauf = Abschnitt(
      titel: 'Verlauf',
      symbol: Icons.history,
      kind: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_verlaufFehler != null)
            Text(fehlerText(_verlaufFehler!))
          else if (_verlauf == null)
            const LinearProgressIndicator()
          else
            VerlaufListe(eintraege: _verlauf!),
          if (widget.schreiben) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _schritt,
              maxLength: 480,
              enabled: !_schrittLaeuft,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _schrittSpeichern(),
              decoration: InputDecoration(
                labelText: 'Arbeitsschritt festhalten',
                hintText: 'z. B. „Handwerker angerufen, Termin Di 14 Uhr“',
                helperText: m.personId != null
                    ? 'Steht sofort im Verlauf und geht per WhatsApp/Push an die meldende Person.'
                    : 'Steht sofort im Verlauf.',
                helperMaxLines: 2,
                suffixIcon: IconButton(
                  tooltip: 'Schritt speichern',
                  icon: _schrittLaeuft
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send),
                  onPressed: _schrittLaeuft ? null : _schrittSpeichern,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    final Widget inhalt;
    if (!widget.schreiben) {
      inhalt = ListView(
        padding: const EdgeInsets.all(12),
        children: [
          ...kopf,
          Abschnitt(
            titel: 'Stand',
            symbol: Icons.info_outline,
            kind: Text(
              'Status: ${m.status.text}\nZuständig: ${m.zuweisungText}${m.notiz != null ? '\nNotiz: ${m.notiz}' : ''}',
            ),
          ),
          verlauf,
        ],
      );
    } else {
      inhalt = RosenwegFormular(
        speichern: _speichern,
        gespeichert: () => Navigator.of(context).pop(true),
        weitereKnoepfe: [
          OutlinedButton.icon(
            onPressed: _archivieren,
            icon: Icon(m.archiviert ? Icons.unarchive_outlined : Icons.inventory_2_outlined),
            label: Text(m.archiviert ? 'Aus dem Archiv holen' : 'Archivieren'),
          ),
        ],
        felder: [
          ...kopf,
          AuswahlFeld<Status>(
            name: 'status',
            titel: 'Status',
            optionen: {for (final s in Status.values) s: s.text},
            wert: _status,
            geaendert: (v) => setState(() => _status = v ?? _status),
          ),
          if (_nachrichtMoeglich)
            TextFeld(
              name: 'melder_bemerkung',
              titel: 'Nachricht an ${m.personName ?? 'die meldende Person'} (freiwillig)',
              controller: _nachricht,
              zeilen: 2,
              hinweis: 'Geht mit der Statusmeldung per WhatsApp, bei „Erledigt“ und „Abgewiesen“ auch per E-Mail, und steht in ihrem Verlauf.',
              pruefen: (v) => (v ?? '').length > 500 ? 'Höchstens 500 Zeichen.' : null,
            ),
          AuswahlFeld<String>(
            name: 'kategorie',
            titel: 'Kategorie',
            optionen: {
              if (!Kategorie.alle.any((k) => k.wert == _kategorie)) _kategorie: _kategorie,
              for (final k in Kategorie.alle) k.wert: k.text,
            },
            wert: _kategorie,
            geaendert: (v) => setState(() => _kategorie = v ?? _kategorie),
          ),
          SuchAuswahlFeld<Zustaendig>(
            name: 'zuweisung',
            titel: 'Zuständig',
            wert: _wer,
            text: (z) => z.name,
            untertitel: (z) => z.art,
            suchHinweis: 'Name oder Firma',
            hinweis: 'Technik-Team oder Handwerker. Technik-Mitglieder werden per WhatsApp/Push benachrichtigt.',
            suchen: (q) async {
              final l = await widget.zustaendige();
              final s = q.trim().toLowerCase();
              return [
                for (final z in l)
                  if (s.isEmpty || z.name.toLowerCase().contains(s)) z,
              ];
            },
            geaendert: (z) => setState(() => _wer = z),
          ),
          TextFeld(
            name: 'notiz',
            titel: 'Notiz (intern)',
            controller: _notiz,
            zeilen: 3,
            hinweis: 'Nur für Technik, Ausschuss und Verwaltung – die meldende Person sieht sie nicht.',
            pruefen: (v) => (v ?? '').length > 2000 ? 'Höchstens 2000 Zeichen.' : null,
          ),
          verlauf,
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text('Meldung #${m.id}')),
      body: RosenwegInhalt(child: inhalt),
    );
  }
}

/// Automatische Zuweisung: je Kategorie ein Standard-Zustaendiger, auf
/// Wunsch je STWEG anders ("Alle STWEG" = Standard, nur Technik/Praesident).
/// Neue Meldungen bekommen ihn sofort; Technik-Mitglieder werden
/// benachrichtigt.
class AutoZuweisung extends StatefulWidget {
  const AutoZuweisung({super.key, required this.api, required this.stwegs, required this.zustaendige});
  final ReparaturApi api;

  /// STWEGs, die die Person aendern darf (0 = alle STWEG).
  final List<int> stwegs;
  final Future<List<Zustaendig>> Function() zustaendige;

  @override
  State<AutoZuweisung> createState() => _AutoZuweisungState();
}

/// "niemand" in der Auswahl (Regel entfernen).
const _niemand = Zustaendig.technik('');

class _AutoZuweisungState extends State<AutoZuweisung> {
  late int _stweg = widget.stwegs.first;
  final _regeln = <String, Zustaendig>{}; // "kategorie|stweg"
  List<Zustaendig>? _liste;
  Object? _fehler;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  Future<void> _laden() async {
    setState(() => _fehler = null);
    try {
      final z = await widget.zustaendige();
      final r = await widget.api.autoRegeln(z);
      if (!mounted) return;
      setState(() {
        _liste = z;
        _regeln
          ..clear()
          ..addAll({
            for (final x in r)
              if (x.zustaendig != null) '${x.kategorie}|${x.stweg}': x.zustaendig!,
          });
      });
    } catch (e) {
      if (mounted) setState(() => _fehler = e);
    }
  }

  Future<void> _speichern() => widget.api.autoRegelnSpeichern([
    for (final s in widget.stwegs)
      for (final k in Kategorie.alle) AutoRegel(kategorie: k.wert, stweg: s, zustaendig: _regeln['${k.wert}|$s']),
  ]);

  String _stwegName(int n) => n == 0 ? 'Alle STWEG (Standard)' : stwegText(n);

  @override
  Widget build(BuildContext context) {
    final l = _liste;
    Widget inhalt;
    if (_fehler != null) {
      inhalt = FehlerAnzeige(text: fehlerText(_fehler!), nochmals: _laden);
    } else if (l == null) {
      inhalt = const LadeAnzeige();
    } else {
      final optionen = {_niemand: '— niemand —', for (final z in l) z: '${z.name} (${z.art})'};
      inhalt = RosenwegFormular(
        speichern: _speichern,
        gespeichert: () => Navigator.of(context).pop(),
        felder: [
          const Text(
            'Neue Meldungen gehen automatisch an diese Person bzw. Firma. '
            'Eine Regel für eine einzelne STWEG gilt vor „Alle STWEG“.',
          ),
          if (widget.stwegs.length > 1)
            AuswahlFeld<int>(
              titel: 'Für',
              optionen: {for (final s in widget.stwegs) s: _stwegName(s)},
              wert: _stweg,
              geaendert: (v) => setState(() => _stweg = v ?? _stweg),
            )
          else
            Text('Für ${_stwegName(_stweg)}', style: Theme.of(context).textTheme.titleMedium),
          for (final k in Kategorie.alle)
            AuswahlFeld<Zustaendig>(
              key: ValueKey('${k.wert}|$_stweg'),
              titel: k.text,
              optionen: {
                ...optionen,
                // Eintrag, der nicht (mehr) in der Liste steht, trotzdem zeigen
                if (_regeln['${k.wert}|$_stweg'] case final z? when !optionen.containsKey(z)) z: '${z.name} (${z.art})',
              },
              wert: _regeln['${k.wert}|$_stweg'] ?? _niemand,
              geaendert: (z) => setState(() {
                if (z == null || z == _niemand) {
                  _regeln.remove('${k.wert}|$_stweg');
                } else {
                  _regeln['${k.wert}|$_stweg'] = z;
                }
              }),
            ),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Automatische Zuweisung')),
      body: RosenwegInhalt(child: inhalt),
    );
  }
}
