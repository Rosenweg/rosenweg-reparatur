// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

import '../daten.dart';
import '../reparatur_api.dart';
import 'haupt.dart';

/// Eigene Meldungen (`GET /api/reklamationen/meine`): Stand, Datum; antippen
/// = Verlauf und Foto. Ausblenden (archivieren) gilt nur fuer die eigene
/// Liste – die Technik sieht die Meldung weiter.
class MeineSeite extends StatefulWidget {
  const MeineSeite({super.key, required this.api, required this.neu});
  final ReparaturApi api;

  /// Nummern mit Neuigkeiten seit dem letzten Blick (Abfrage beim Oeffnen).
  final ValueNotifier<Set<int>> neu;

  @override
  State<MeineSeite> createState() => _MeineSeiteState();
}

class _MeineSeiteState extends State<MeineSeite> {
  bool _archivierte = false;

  @override
  Widget build(BuildContext context) => Laden<List<Meldung>>(
    laden: widget.api.meine,
    fertig: (context, alle, neu) {
      final liste = [
        for (final m in alle)
          if (m.melderArchiviert == _archivierte) m,
      ];
      final ausgeblendet = alle.where((m) => m.melderArchiviert).length;
      return RefreshIndicator(
        onRefresh: neu,
        child: ValueListenableBuilder<Set<int>>(
          valueListenable: widget.neu,
          builder: (context, neuNr, _) => ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              if (_archivierte)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Hinweis('Ausgeblendete Meldungen. Die Technik sieht sie weiter.'),
                ),
              if (liste.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Column(
                    children: [
                      const Icon(Icons.inbox_outlined, size: 48),
                      const SizedBox(height: 8),
                      Text(
                        _archivierte ? 'Keine ausgeblendeten Meldungen.' : 'Du hast noch nichts gemeldet.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              for (final m in liste)
                MeldungKachel(
                  m: m,
                  neu: neuNr.contains(m.id),
                  antippen: () async {
                    widget.neu.value = {...widget.neu.value}..remove(m.id);
                    final geaendert = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => MeineMeldung(api: widget.api, m: m),
                      ),
                    );
                    if (geaendert == true) await neu();
                  },
                ),
              if (ausgeblendet > 0 || _archivierte)
                Center(
                  child: TextButton.icon(
                    onPressed: () => setState(() => _archivierte = !_archivierte),
                    icon: Icon(_archivierte ? Icons.arrow_back : Icons.inventory_2_outlined),
                    label: Text(_archivierte ? 'Zurück zu den aktuellen' : 'Ausgeblendete zeigen ($ausgeblendet)'),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// Eine eigene Meldung: Beschreibung, Foto, Verlauf (Erfassung,
/// Statuswechsel, Nachrichten an dich), ausblenden.
class MeineMeldung extends StatelessWidget {
  const MeineMeldung({super.key, required this.api, required this.m});
  final ReparaturApi api;
  final Meldung m;

  Future<void> _archivieren(BuildContext context) async {
    final weg = !m.melderArchiviert;
    if (weg &&
        !await frage(
          context,
          'Meldung ausblenden?',
          'Sie verschwindet nur aus deiner Liste; die Technik bearbeitet sie weiter. Unter „Ausgeblendete zeigen“ holst du sie zurück.',
          ja: 'Ausblenden',
        )) {
      return;
    }
    try {
      await api.meineArchivieren(m.id, weg);
      if (context.mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (context.mounted) zeigeMeldung(context, fehlerText(e), fehler: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('Meldung #${m.id}'),
      actions: [
        IconButton(
          tooltip: m.melderArchiviert ? 'Wieder zeigen' : 'Ausblenden',
          icon: Icon(m.melderArchiviert ? Icons.unarchive_outlined : Icons.inventory_2_outlined),
          onPressed: () => _archivieren(context),
        ),
      ],
    ),
    body: RosenwegInhalt(
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          MeldungKachel(m: m),
          if (m.hatFoto)
            Abschnitt(
              titel: 'Foto',
              symbol: Icons.photo_outlined,
              kind: GeladenesBild(laden: () => api.meinFoto(m.id), titel: 'Foto zu #${m.id}'),
            ),
          Abschnitt(
            titel: 'Verlauf',
            symbol: Icons.history,
            kind: Laden<List<VerlaufEintrag>>(
              laden: () => api.meinVerlauf(m.id),
              fertig: (_, v, _) => VerlaufListe(eintraege: v),
            ),
          ),
        ],
      ),
    ),
  );
}
