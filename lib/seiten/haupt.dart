// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

import '../daten.dart';
import '../reparatur_api.dart';
import 'bearbeiten.dart';
import 'meine.dart';
import 'melden.dart';
import 'stweg.dart';

/// Seitenrecht der Bearbeitung (wie reklamationen.html und die API).
const reklamationenRecht = 'reklamationen';

/// Die App nach der Anmeldung: ein Vorgang von der Meldung bis zur
/// Erledigung. Bereiche – auf dem Handy unten, am Computer links:
///
///  * Melden: Schaden mit Foto melden, Melde-Ort per QR-Code (alle)
///  * Meine: eigene Meldungen mit Stand, Verlauf und Foto (alle)
///  * STWEG: Meldungen der eigenen STWEG ohne Namen, ersetzt
///    stwegN/pages/reklamationen.html (Bewohner, Eigentuemer, Ausschuss und
///    Verwaltung der STWEG; Technik/Praesident jede)
///  * Bearbeiten: Status, Zuweisung an Technik oder Handwerker, Notiz,
///    Arbeitsschritte, automatische Zuweisung (Seitenrecht reklamationen;
///    Ausschuss und Verwaltung nur ihre STWEG – das trennt die API)
///
/// Ohne Push (kein ntfy): beim Oeffnen, bei der Rueckkehr in den Vordergrund
/// und alle 5 Minuten fragt die App nach, was sich bei den eigenen Meldungen
/// und – fuer Bearbeitende – an neuen Meldungen getan hat.
class Haupt extends StatefulWidget {
  const Haupt({super.key, required this.sitzung, this.speicher});
  final RosenwegSitzung sitzung;

  /// Fuer Tests; sonst der Speicher der App.
  final AppSpeicher? speicher;

  @override
  State<Haupt> createState() => _HauptState();
}

class _HauptState extends State<Haupt> {
  late final ReparaturApi _api = ReparaturApi(widget.sitzung);
  ReparaturRechte? _rechte;

  /// Eigene Meldungen mit Neuigkeiten seit dem letzten Blick (Nummern).
  final _neuMeine = ValueNotifier<Set<int>>({});

  /// Neue Meldungen fuer Bearbeitende seit dem letzten Blick.
  final _neuBearbeiten = ValueNotifier<Set<int>>({});

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.sitzung.rechte.laden().ignore();
      _rechteLaden();
    });
  }

  Future<void> _rechteLaden() async {
    try {
      final r = await _api.rechte();
      if (mounted) setState(() => _rechte = r);
    } catch (e) {
      Protokoll.schreiben('Reparatur-Rechte', e);
      if (mounted) setState(() => _rechte = const ReparaturRechte());
    }
  }

  Future<AppSpeicher> _speicher() async => widget.speicher ?? await AppSpeicher.app();

  /// Abfrage beim Oeffnen: was ist neu? Meldet es unten kurz und markiert
  /// die Eintraege in "Meine" bzw. "Bearbeiten".
  Future<void> _nachfragen() async {
    final sp = await _speicher();
    final saetze = <String>[];
    final meine = await _api.meine();
    final geaendert = await Neuigkeiten(sp, 'meine').vergleichen({for (final m in meine) '${m.id}': m.status.wert});
    if (geaendert.isNotEmpty) {
      _neuMeine.value = {..._neuMeine.value, ...geaendert.map(int.parse)};
      final ms = [
        for (final m in meine)
          if (geaendert.contains('${m.id}')) m,
      ];
      saetze.add(
        ms.length == 1
            ? 'Deine Meldung #${ms.first.id} ist jetzt „${ms.first.status.text}“.'
            : '${ms.length} deiner Meldungen haben einen neuen Stand.',
      );
    }
    final r = widget.sitzung.rechte.stand ?? await widget.sitzung.rechte.laden();
    if (r.darf(reklamationenRecht)) {
      final aktiv = await _api.bearbeiten('aktiv');
      // nur neue Nummern zaehlen; Statuswechsel macht man meist selbst
      final neu = await Neuigkeiten(sp, 'bearbeiten').vergleichen({for (final m in aktiv) '${m.id}': 'da'});
      if (neu.isNotEmpty) {
        _neuBearbeiten.value = {..._neuBearbeiten.value, ...neu.map(int.parse)};
        saetze.add(
          neu.length == 1
              ? 'Neue Meldung #${neu.first} zum Bearbeiten.'
              : '${neu.length} neue Meldungen zum Bearbeiten.',
        );
      }
    }
    if (saetze.isNotEmpty && mounted) zeigeMeldung(context, saetze.join(' '));
  }

  /// Nach dem Melden: die eigene neue Meldung nicht als "neu" melden.
  Future<void> _gemeldet() async {
    try {
      final meine = await _api.meine();
      await Neuigkeiten(await _speicher(), 'meine').vergleichen({for (final m in meine) '${m.id}': m.status.wert});
    } catch (e) {
      Protokoll.schreiben('Nach dem Melden', e);
    }
  }

  @override
  void dispose() {
    _neuMeine.dispose();
    _neuBearbeiten.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.sitzung;
    return BeimOeffnen(
      pruefen: _nachfragen,
      alle: const Duration(minutes: 5),
      child: ListenableBuilder(
        listenable: s.rechte,
        builder: (context, _) {
          final r = s.rechte.stand;
          final rechte = _rechte;
          final bearbeiten = r?.darf(reklamationenRecht) ?? false;
          final schreiben = r?.darf(reklamationenRecht, Zugriff.schreiben) ?? false;
          final mitStweg = rechte != null && rechte.uebersichtStwegs.isNotEmpty;
          return RosenwegGeruest(
            titel: Text(s.app.name),
            logo: Padding(
              padding: const EdgeInsets.all(10),
              child: Image.asset('assets/logo/rosenweg-reparatur-klein.png', semanticLabel: 'Logo'),
            ),
            aktionen: [_Menue(sitzung: s)],
            ziele: [
              GeruestZiel(
                titel: 'Melden',
                symbol: Icons.add_a_photo_outlined,
                gewaehltSymbol: Icons.add_a_photo,
                seite: (_) => MeldenSeite(api: _api, rechte: rechte, gemeldet: _gemeldet),
              ),
              GeruestZiel(
                titel: 'Meine',
                symbol: Icons.receipt_long_outlined,
                gewaehltSymbol: Icons.receipt_long,
                seite: (_) => MeineSeite(api: _api, neu: _neuMeine),
              ),
              if (mitStweg)
                GeruestZiel(
                  titel: 'STWEG',
                  symbol: Icons.apartment_outlined,
                  gewaehltSymbol: Icons.apartment,
                  seite: (_) => StwegSeite(api: _api, rechte: rechte),
                ),
              if (bearbeiten)
                GeruestZiel(
                  titel: 'Bearbeiten',
                  symbol: Icons.build_outlined,
                  gewaehltSymbol: Icons.build,
                  seite: (_) => BearbeitenSeite(api: _api, schreiben: schreiben, rechte: rechte, neu: _neuBearbeiten),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Menue oben rechts: Anmeldung (echter Stand, "Nach Updates suchen"),
/// Ueber, Abmelden (nicht auf geteilten Telefonen – dort meldet Rosenweg
/// Geraet ab).
class _Menue extends StatelessWidget {
  const _Menue({required this.sitzung});
  final RosenwegSitzung sitzung;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Mehr',
    onSelected: (w) async {
      switch (w) {
        case 'anmeldung':
          await zeigeAnmeldung(context, sitzung);
        case 'ueber':
          await zeigeUeber(context, sitzung.app);
        case 'abmelden':
          if (await frage(context, 'Abmelden?', 'Danach musst du dich neu anmelden.', ja: 'Abmelden')) {
            await sitzung.abmelden();
          }
      }
    },
    itemBuilder: (_) => [
      PopupMenuItem(value: 'anmeldung', child: Text('Anmeldung: ${sitzung.name ?? 'angemeldet'}')),
      PopupMenuItem(value: 'ueber', child: Text('Über ${sitzung.app.name}')),
      if (!sitzung.geteiltesTelefon) const PopupMenuItem(value: 'abmelden', child: Text('Abmelden')),
    ],
  );
}

/// Status als farbiges Schild.
class StatusSchild extends StatelessWidget {
  const StatusSchild(this.status, {super.key});
  final Status status;

  @override
  Widget build(BuildContext context) {
    final c = status.farbe(Theme.of(context).colorScheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        border: Border.all(color: c.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.text,
        style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Kleines "Neu"-Schild fuer Eintraege mit Neuigkeiten.
class NeuSchild extends StatelessWidget {
  const NeuSchild({super.key});
  @override
  Widget build(BuildContext context) {
    final f = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: f.primary, borderRadius: BorderRadius.circular(8)),
      child: Text(
        'Neu',
        style: TextStyle(color: f.onPrimary, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Verlauf einer Meldung als Liste.
class VerlaufListe extends StatelessWidget {
  const VerlaufListe({super.key, required this.eintraege, this.leer = 'Noch kein Verlauf.'});
  final List<VerlaufEintrag> eintraege;
  final String leer;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final f = Theme.of(context).colorScheme;
    if (eintraege.isEmpty) return Text(leer, style: t.bodySmall?.copyWith(color: f.onSurfaceVariant));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final e in eintraege)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 5, right: 8),
                  child: Icon(Icons.circle, size: 8, color: f.primary),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.text, style: t.bodyMedium),
                      Text(
                        [wannText(e.zeit), ?e.wer].where((x) => x.isNotEmpty).join(' · '),
                        style: t.bodySmall?.copyWith(color: f.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Eine Meldung als Karte in Listen: Kategorie, Nummer, Stand, Ort,
/// Beschreibung, Daten.
class MeldungKachel extends StatelessWidget {
  const MeldungKachel({
    super.key,
    required this.m,
    this.neu = false,
    this.unten,
    this.antippen,
    this.zeigeStweg = false,
  });
  final Meldung m;
  final bool neu;
  final Widget? unten;
  final VoidCallback? antippen;
  final bool zeigeStweg;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final f = Theme.of(context).colorScheme;
    final k = m.kat;
    final ort = [if (zeigeStweg) stwegText(m.stweg), ?m.standort].join(' · ');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: antippen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(k.symbol, size: 20, color: f.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(child: Text('${k.text} · #${m.id}', style: t.titleSmall)),
                  if (m.hatFoto)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(Icons.photo_outlined, size: 18, color: f.onSurfaceVariant, semanticLabel: 'mit Foto'),
                    ),
                  if (neu) const Padding(padding: EdgeInsets.only(right: 6), child: NeuSchild()),
                  StatusSchild(m.status),
                ],
              ),
              if (ort.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Icon(Icons.place_outlined, size: 16, color: f.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Expanded(child: Text(ort, style: t.bodySmall)),
                    ],
                  ),
                ),
              const SizedBox(height: 6),
              Text(
                m.beschreibung,
                maxLines: antippen == null ? null : 3,
                overflow: antippen == null ? null : TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                [
                  'gemeldet ${tagText(m.erstellt)}',
                  if (m.erledigtAm != null && m.status == Status.erledigt) 'erledigt ${tagText(m.erledigtAm)}',
                  if (!m.status.abgeschlossen && m.inBearbeitung) 'in Bearbeitung',
                ].join(' · '),
                style: t.bodySmall?.copyWith(color: f.onSurfaceVariant),
              ),
              ?unten,
            ],
          ),
        ),
      ),
    );
  }
}

/// Laedt einmal und zeigt Laden, Fehler mit "Nochmals" oder das Ergebnis.
class Laden<T> extends StatefulWidget {
  const Laden({super.key, required this.laden, required this.fertig});
  final Future<T> Function() laden;
  final Widget Function(BuildContext context, T wert, Future<void> Function() neu) fertig;

  @override
  State<Laden<T>> createState() => _LadenState<T>();
}

class _LadenState<T> extends State<Laden<T>> {
  late Future<T> _f = widget.laden();

  Future<void> _neu() async {
    final f = widget.laden();
    setState(() {
      _f = f;
    });
    await f.then((_) {}, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: _f,
    builder: (context, s) {
      if (s.hasError) return FehlerAnzeige(text: fehlerText(s.error!), nochmals: () => unawaited(_neu()));
      if (s.connectionState != ConnectionState.done && !s.hasData) return const LadeAnzeige();
      return widget.fertig(context, s.data as T, _neu);
    },
  );
}
