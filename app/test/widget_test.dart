import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iem_driver/models/eq_band.dart';
import 'package:iem_driver/main.dart';
import 'package:iem_driver/widgets/eq_band_slider_bank.dart';

void main() {
  testWidgets('IEM Driver EQ screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const IemDriverApp());
    await tester.pumpAndSettle();

    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.text('Preset slots'), findsOneWidget);
    expect(find.text('Empty slot'), findsNWidgets(8));
    expect(find.text('Band gain'), findsOneWidget);
    expect(find.byKey(const ValueKey('eq-band-fader-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('eq-band-fader-9')), findsOneWidget);
    expect(find.byTooltip('Appearance'), findsOneWidget);

    await tester.tap(find.byTooltip('Appearance'));
    await tester.pumpAndSettle();
    expect(find.text('Color grading'), findsOneWidget);
    expect(find.text('Accent color'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('EQ screen stays within a narrow phone viewport',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const IemDriverApp());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Parametric EQ'), findsOneWidget);
  });

  testWidgets('band fader selects and changes its linked PEQ band',
      (WidgetTester tester) async {
    var bands = List.generate(
      10,
      (index) => EqBand(
        enabled: false,
        type: EqFilterType.peaking,
        frequencyHz: 20 + index * 1000,
        gainDb: 0,
        q: 0.9,
      ),
    );
    var selectedIndex = 0;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: EqBandSliderBank(
              bands: bands,
              selectedIndex: selectedIndex,
              accent: const Color(0xFFFFB000),
              onSelectionChanged: (index) =>
                  setState(() => selectedIndex = index),
              onGainChanged: (index, gainDb) => setState(() {
                bands = List.of(bands);
                bands[index] = bands[index].copyWith(
                  enabled: true,
                  gainDb: gainDb,
                );
              }),
            ),
          );
        }),
      ),
    ));

    final fader = tester.getRect(find.byKey(const ValueKey('eq-band-fader-3')));
    await tester.tapAt(Offset(fader.center.dx, fader.top + 12));
    await tester.pump();

    expect(selectedIndex, 3);
    expect(bands[3].enabled, isTrue);
    expect(bands[3].gainDb, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}
