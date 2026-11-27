// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

import '../daten.dart';
import '../reparatur_api.dart';

/// Schaden melden: Kategorie, was ist kaputt, wo, STWEG, Foto. Ein
/// Melde-QR-Code (Schild am Ort) fuellt Ort, STWEG und Kategorie vor.
///
/// Wie die Reparatur-PWA: Foto vor dem Senden verkleinert (1600 px, JPEG
/// 75 %), Bestaetigung per E-Mail kommt von der API.
class MeldenSeite extends StatefulWidget {
  const MeldenSeite({
    super.key,
    required this.api,
    required this.rechte,
    this.gemeldet,
    this.scannen,
    this.ortCode,
    this.ortVerbraucht,
  });
  final ReparaturApi api;

  /// null = noch nicht geladen (dann ohne Vorschlag der STWEG).
  final ReparaturRechte? rechte;

  /// Nach dem Senden (Neuigkeiten nachfuehren).
  final Future<void> Function()? gemeldet;

  /// Melde-Ort aus einem App-Link (QR-Code mit der Kamera des Telefons
  /// gescannt, App geoeffnet): gleich vorbelegen, danach [ortVerbraucht].
  final String? ortCode;
  final VoidCallback? ortVerbraucht;

  /// Fuer Tests: statt der Kamera bzw. des Eingabefelds.
  final Future<String?> Function(BuildContext context)? scannen;

  @override
  State<MeldenSeite> createState() => _MeldenSeiteState();
}

/// Wert fuer "Allgemein / weiss nicht" in der STWEG-Auswahl (API: null).
const _allgemein = 0;

class _MeldenSeiteState extends State<MeldenSeite> {
  final _beschreibung = TextEditingController();
  final _standort = TextEditingController();
  final _steuerung = FormularSteuerung();
  String? _kategorie;
  int? _stweg;
  DateiDaten? _foto;
  MeldeOrt? _ort;
  bool _ortLaedt = false;
  int? _nummer;
  int _runde = 0;

  @override
  void initState() {
    super.initState();
    _stwegVorschlagen();
    final c = widget.ortCode;
    if (c != null) {
      widget.ortVerbraucht?.call();
      WidgetsBinding.instance.addPostFrameCallback((_) => _ortLaden(c));
    }
  }

  @override
  void didUpdateWidget(MeldenSeite alt) {
    super.didUpdateWidget(alt);
    if (alt.rechte == null && widget.rechte != null) _stwegVorschlagen();
  }

  void _stwegVorschlagen() {
    if (_stweg != null || _ort != null) return;
    final e = widget.rechte?.eigeneStwegs ?? const [];
    if (e.isNotEmpty) _stweg = e.first;
  }

  @override
  void dispose() {
    _beschreibung.dispose();
    _standort.dispose();
    _steuerung.dispose();
    super.dispose();
  }

  Future<void> _ortScannen() async {
    final roh = widget.scannen != null
        ? await widget.scannen!(context)
        : await codeScannen(
            context,
            titel: 'Melde-Ort scannen',
            hinweis: 'Den QR-Code auf dem Schild „Schaden melden“ in den Rahmen halten.',
            pruefen: (w) => MeldeOrt.codeAus(w) == null ? 'Das ist kein Melde-QR-Code der Reparatur.' : null,
          );
    if (roh == null || !mounted) return;
    final code = MeldeOrt.codeAus(roh);
    if (code == null) {
      zeigeMeldung(context, 'Das ist kein Melde-QR-Code der Reparatur.', fehler: true);
      return;
    }
    await _ortLaden(code);
  }

  Future<void> _ortLaden(String code) async {
    if (!mounted) return;
    setState(() => _ortLaedt = true);
    try {
      final o = await widget.api.meldeOrt(code);
      if (!mounted) return;
      if (o == null) {
        zeigeMeldung(context, 'Diesen Melde-Ort gibt es nicht (mehr). Bitte den Ort von Hand eintragen.', fehler: true);
        return;
      }
      setState(() {
        _ort = o;
        if (o.kategorie != null && Kategorie.alle.any((k) => k.wert == o.kategorie)) _kategorie = o.kategorie;
        if (o.stweg != null) _stweg = o.stweg;
        if (_standort.text.trim().isEmpty) _standort.text = o.name;
      });
      _steuerung.markieren();
    } catch (e) {
      if (mounted) zeigeMeldung(context, fehlerText(e), fehler: true);
    } finally {
      if (mounted) setState(() => _ortLaedt = false);
    }
  }

  void _ortWeg() => setState(() {
    if (_standort.text == _ort?.name) _standort.clear();
    _ort = null;
  });

  Future<void> _senden() async {
    final n = await widget.api.melden(
      kategorie: _kategorie ?? 'sonstige',
      beschreibung: _beschreibung.text.trim(),
      stweg: _stweg == _allgemein ? null : _stweg,
      standort: _standort.text,
      foto: _foto,
    );
    _nummer = n;
  }

  void _gesendet() {
    setState(() {});
    widget.gemeldet?.call();
  }

  void _neu() => setState(() {
    _nummer = null;
    _beschreibung.clear();
    _standort.clear();
    _kategorie = null;
    _foto = null;
    _ort = null;
    _stweg = null;
    _stwegVorschlagen();
    _steuerung.zuruecksetzen();
    _runde++;
  });

  Map<int, String> get _stwegOptionen {
    final eigene = widget.rechte?.eigeneStwegs ?? const <int>[];
    return {
      for (final n in eigene) n: '${stwegText(n)} (meine)',
      for (var n = 1; n <= 8; n++)
        if (!eigene.contains(n)) n: stwegText(n),
      _allgemein: 'Allgemein / weiss nicht',
    };
  }

  @override
  Widget build(BuildContext context) {
    final nummer = _nummer;
    if (nummer != null) return _Danke(nummer: nummer, weitere: _neu);
    final t = Theme.of(context).textTheme;
    final ort = _ort;
    return RosenwegFormular(
      key: ValueKey(_runde),
      steuerung: _steuerung,
      speichern: _senden,
      speichernText: 'Meldung senden',
      gespeichertText: null,
      gespeichert: _gesendet,
      fragenBeimVerlassen: false,
      felder: [
        Text('Was ist kaputt? Beschreibe den Schaden, ein Foto hilft der Technik.', style: t.bodyMedium),
        if (ort == null)
          OutlinedButton.icon(
            onPressed: _ortLaedt ? null : _ortScannen,
            icon: _ortLaedt
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.qr_code_scanner),
            label: const Text('QR-Code am Ort scannen'),
          )
        else
          Card(
            child: ListTile(
              leading: const Icon(Icons.place),
              title: Text(ort.name),
              subtitle: Text('Ort per QR-Code · ${stwegText(ort.stweg)}'),
              trailing: IconButton(tooltip: 'Ort entfernen', icon: const Icon(Icons.close), onPressed: _ortWeg),
            ),
          ),
        _KategorieFeld(
          wert: _kategorie,
          geaendert: (k) {
            setState(() => _kategorie = k);
            _steuerung.markieren('kategorie');
          },
        ),
        TextFeld(
          name: 'beschreibung',
          titel: 'Was ist kaputt?',
          controller: _beschreibung,
          pflicht: true,
          zeilen: 4,
          hinweis: 'z. B. „Licht im Treppenhaus 2. OG brennt nicht mehr“',
          pruefen: (v) => (v ?? '').trim().length > 4000 ? 'Bitte kürzer fassen (höchstens 4000 Zeichen).' : null,
        ),
        TextFeld(
          name: 'standort',
          titel: 'Wo genau?',
          controller: _standort,
          hinweis: 'Haus, Stockwerk, Raum – freiwillig',
        ),
        AuswahlFeld<int>(
          // neu aufbauen, wenn der Melde-Ort die STWEG setzt
          key: ValueKey('stweg-$_stweg'),
          name: 'stweg',
          titel: 'STWEG',
          optionen: _stwegOptionen,
          wert: _stweg ?? _allgemein,
          geaendert: (v) => setState(() => _stweg = v),
        ),
        FotoFeld(
          name: 'foto',
          titel: 'Foto (freiwillig)',
          wert: _foto,
          hinweis: 'Wird vor dem Senden verkleinert.',
          geaendert: (f) => setState(() => _foto = f),
        ),
      ],
    );
  }
}

/// Kategorie als Knoepfe mit Symbol (wie die PWA), Pflicht.
class _KategorieFeld extends FormField<String> {
  _KategorieFeld({required String? wert, required ValueChanged<String> geaendert})
    : super(
        initialValue: wert,
        validator: (v) => v == null ? 'Bitte eine Kategorie wählen.' : null,
        builder: (feld) {
          final context = feld.context;
          final f = Theme.of(context).colorScheme;
          final aus = formularSteuerungVon(context)?.speichert ?? false;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Kategorie *', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final k in Kategorie.alle)
                    ChoiceChip(
                      avatar: Icon(k.symbol, size: 18),
                      label: Text(k.text),
                      selected: feld.value == k.wert,
                      onSelected: aus
                          ? null
                          : (_) {
                              feld.didChange(k.wert);
                              geaendert(k.wert);
                            },
                    ),
                ],
              ),
              if (feld.errorText != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(feld.errorText!, style: TextStyle(color: f.error)),
                ),
            ],
          );
        },
      );

  @override
  FormFieldState<String> createState() => _KategorieFeldState();
}

class _KategorieFeldState extends FormFieldState<String> {
  @override
  void didUpdateWidget(_KategorieFeld alt) {
    super.didUpdateWidget(alt);
    // Vorgabe vom Melde-Ort uebernehmen
    if (widget.initialValue != alt.initialValue && widget.initialValue != value) setValue(widget.initialValue);
  }
}

class _Danke extends StatelessWidget {
  const _Danke({required this.nummer, required this.weitere});
  final int nummer;
  final VoidCallback weitere;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline, size: 64, color: RosenwegFarben.gut),
            const SizedBox(height: 16),
            Text(
              'Danke! Deine Meldung${nummer > 0 ? ' #$nummer' : ''} ist eingegangen.',
              style: t.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Du bekommst eine Bestätigung per E-Mail. Wie es weitergeht, siehst du unter „Meine“.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(onPressed: weitere, icon: const Icon(Icons.add), label: const Text('Weitere Meldung')),
          ],
        ),
      ),
    );
  }
}
