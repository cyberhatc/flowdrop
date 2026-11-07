import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowdrop/app/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('shows FlowDrop splash while starting', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: FlowDropApp()));
    await tester.pump();
    expect(find.text('FlowDrop'), findsWidgets);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
