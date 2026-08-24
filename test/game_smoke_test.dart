import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_dominion/main.dart';

void main() {
  test('world seed keeps the launch countries and required route data', () {
    final game = GameState();
    expect(game.countries.length, 44);
    expect(game.countries.containsKey('USA'), isTrue);
    expect(game.countries.containsKey('TUR'), isTrue);
    expect(game.countries.containsKey('LBN'), isTrue);
    expect(game.countries['TUR']!.neighbors, contains('GRC'));
    expect(game.countries['LBN']!.neighbors, contains('SYR'));
    expect(kAlpha3To2.length, game.countries.length);
    game.dispose();
  });

  test('naval invasion opens the requested USA to Europe route', () async {
    final game = GameState();
    await game.choose('USA');
    final britain = game.countries['GBR']!;
    final source = game.attackSourceFor('GBR');
    expect(source?.id, 'USA');
    expect(game.isNavalAttack(source!, britain), isTrue);
    expect(game.canNavalInvade(source, britain), isTrue);
    expect(game.attackCommandCost(source, britain, 'balanced'), 3);
    game.dispose();
  });

  test('gameplay systems start with command and research progression', () async {
    final game = GameState();
    await game.choose('FRA');
    expect(game.commandCap, 6);
    expect(game.techLevel('logistics'), 0);
    expect(game.me.warExhaustion, 0);
    expect(game.leaderboard, isNotEmpty);
    game.dispose();
  });

  test('frontline combat math is gradual and bounded', () {
    final even = frontlineProgressDelta(1, randomFactor: 0);
    final strong = frontlineProgressDelta(1.5, plan: 'breakthrough', encircled: true, randomFactor: 0);
    expect(even, greaterThan(0));
    expect(even, lessThan(30));
    expect(strong, greaterThan(even));
    expect(strong, lessThanOrEqualTo(48));
    expect(frontlineControlEdge(10, 2), greaterThan(0));
    expect(frontlineControlEdge(2, 10), lessThan(0));
  });

  test('battle state survives snapshot round-trip without breaking old saves', () {
    final game = GameState();
    game.battles.add(FrontBattle(id:'B1',source:'FRA',target:'DEU',attacker:'P:FRA',defender:'AI:DEU',progress:42,round:2,attackerArmyIds:['A1']));
    final snapshot = game.snapshot();
    final restored = GameState();
    restored.applySnapshot(snapshot);
    expect(restored.battles.length, 1);
    expect(restored.battles.first.progress, 42);
    restored.applySnapshot({'countries': <String,dynamic>{}});
    expect(restored.battles, isEmpty);
    game.dispose();restored.dispose();
  });

  test('v1.4 pace changes strategic tempo while preserving campaign defaults', () async {
    final game = GameState();
    await game.choose('FRA');
    expect(game.commandCap, 6);
    game.setGamePace('rapid');
    expect(game.commandCap, 8);
    expect(game.hegemonyStartTurn, 15);
    game.setGamePace('grand');
    expect(game.commandCap, 5);
    expect(game.recommendedTurnMinutes, 720);
    game.dispose();
  });

  test('v1.4 provinces keep logistics and bilingual labels in snapshots', () {
    final game = GameState();
    final p = game.provinces.first;
    expect(p.supply, greaterThan(0));
    expect(p.infrastructure, greaterThan(0));
    final snapshot = game.snapshot();
    final restored = GameState();
    restored.applySnapshot(snapshot);
    expect(restored.provinces.first.supply, p.supply);
    restored.setLanguage('en');
    expect(restored.tr('هجوم','Attack'), 'Attack');
    game.dispose();restored.dispose();
  });

  test('v1.5 modern warfare fields and province logistics survive snapshot round-trip', () async {
    final game = GameState();
    await game.choose('USA');
    game.me.missileProgram = 2;
    // Modern saves keep typed missile inventory authoritative. missileStock is the
    // compatibility total and must equal the sum of the typed inventories.
    game.me.cruiseMissiles = 3;
    game.me.ballisticMissiles = 0;
    game.me.hypersonicMissiles = 0;
    game.me.missileStock = 3;
    game.me.electronicWarfare = 1;
    game.me.satelliteRecon = 2;
    game.me.airReadiness = 83;
    final p = game.provinces.firstWhere((x) => x.countryId == 'USA');
    p.terrain = 'mountains'; p.weather = 'snow'; p.roads = 3; p.rail = 2; p.logisticsLevel = 2;
    final restored = GameState(); restored.applySnapshot(game.snapshot());
    expect(restored.me.missileProgram, 2);
    expect(restored.me.missileStock, 3);
    expect(restored.me.cruiseMissiles, 3);
    expect(restored.me.airReadiness, 83);
    final rp = restored.provinces.firstWhere((x) => x.id == p.id);
    expect(rp.terrain, 'mountains'); expect(rp.weather, 'snow'); expect(rp.roads, 3); expect(rp.rail, 2);
    expect(game.distanceCountries('USA','FRA'), greaterThan(1000));
    game.dispose(); restored.dispose();
  });

  test('legacy missileStock-only saves migrate into cruise missiles without data loss', () async {
    final game = GameState();
    await game.choose('USA');
    game.me.missileProgram = 2;
    game.me.missileStock = 4;
    final snapshot = game.snapshot();
    final countryMap = Map<String,dynamic>.from(snapshot['countries'] as Map);
    final usa = Map<String,dynamic>.from(countryMap['USA'] as Map);
    // v1.5-era saves did not have typed missile fields. Removing them here tests
    // the real backward-compatibility path instead of creating a mixed-format save.
    usa.remove('cruiseMissiles');
    usa.remove('ballisticMissiles');
    usa.remove('hypersonicMissiles');
    usa['missileStock'] = 4;
    countryMap['USA'] = usa;
    snapshot['countries'] = countryMap;

    final restored = GameState();
    restored.humanCountry = 'USA';
    restored.applySnapshot(snapshot);
    expect(restored.me.missileStock, 4);
    expect(restored.me.cruiseMissiles, 4);
    expect(restored.me.ballisticMissiles, 0);
    expect(restored.me.hypersonicMissiles, 0);
    game.dispose(); restored.dispose();
  });

  test('v1.6 carrier task force extends air reach and survives snapshot round-trip', () async {
    final game = GameState();
    await game.choose('USA');
    expect(game.canAirReach('GBR'), isFalse);
    game.navalTaskForces.add(NavalTaskForce(id:'TF-CV',name:'Atlantic Carrier Group',owner:game.me.controller,homeCountry:'USA',zoneId:'north_atlantic',mission:'carrier_strike',surface:1,carriers:1,submarines:1,createdTurn:game.turn,readiness:90,supply:90));
    expect(game.canAirReach('GBR'), isTrue);
    final restored = GameState(); restored.applySnapshot(game.snapshot());
    expect(restored.navalTaskForces.length, 1);
    expect(restored.navalTaskForces.first.carriers, 1);
    expect(restored.navalTaskForces.first.submarines, 1);
    game.dispose(); restored.dispose();
  });

  test('v1.6 alliances are checked through controller roots', () async {
    final game = GameState();
    await game.choose('FRA');
    game.alliances.add('FRA|TUR');
    expect(game.areAllies('FRA','TUR'), isTrue);
    game.countries['SYR']!.controller='AI:TUR';
    expect(game.areAllies('FRA','SYR'), isTrue);
    game.dispose();
  });

  test('v1.7 physical geography survives save round-trip without replacing strategic roads', () async {
    final game = GameState();
    await game.choose('FRA');
    final p = game.provinces.firstWhere((x) => x.countryId == 'FRA');
    p.elevationM = 1450; p.elevationMinM = 820; p.elevationMaxM = 2280; p.elevationSamples = 3; p.reliefM = 1460; p.landCover = 'tree_cover'; p.landCoverSamples = 3;
    p.actualRoadKm = 860; p.actualRailKm = 210; p.roadDensity = 48; p.railDensity = 11; p.roadClassKm = {'motorway':120,'primary':310,'secondary':430}; p.railClassKm = {'rail':210}; p.roads = 3; p.logisticsLevel = 2;
    p.physicalDataQuality = 'real_multi'; p.transportDataQuality = 'overture_strategic_z9';
    final restored = GameState(); restored.applySnapshot(game.snapshot());
    final rp = restored.provinces.firstWhere((x) => x.id == p.id);
    expect(rp.elevationM, 1450); expect(rp.elevationMinM, 820); expect(rp.elevationMaxM, 2280); expect(rp.elevationSamples, 3); expect(rp.reliefM, 1460);
    expect(rp.landCover, 'tree_cover'); expect(rp.landCoverSamples, 3); expect(rp.actualRoadKm, 860); expect(rp.actualRailKm, 210);
    expect(rp.roadDensity, 48); expect(rp.railDensity, 11); expect(rp.roadClassKm['primary'], 310); expect(rp.roads, 3); expect(rp.logisticsLevel, 2);
    expect(rp.physicalDataQuality, 'real_multi'); expect(rp.transportDataQuality, 'overture_strategic_z9');
    game.dispose(); restored.dispose();
  });

  test('v1.7 movement estimate uses physical route quality', () async {
    final game = GameState(); await game.choose('FRA');
    final neighbour = game.countries['FRA']!.neighbors.firstWhere((id) => game.countries.containsKey(id));
    game.countries[neighbour]!.controller = game.me.controller;
    for (final p in game.provinces.where((p) => p.countryId == neighbour)) { p.controller = game.me.controller; }
    final a = game.provinces.firstWhere((p) => p.countryId == 'FRA');
    final b = game.provinces.firstWhere((p) => p.countryId == neighbour);
    for (final p in [a,b]) { p.terrain='plains'; p.weather='clear'; p.landCover='grassland'; p.elevationM=50; p.reliefM=20; p.roads=4; p.rail=3; p.logisticsLevel=2; p.infrastructure=85; p.roadDensity=90; }
    final connected = game.movementCostBetween('FRA',neighbour);
    for (final p in [a,b]) { p.terrain='mountains'; p.weather='snow'; p.landCover='tree_cover'; p.elevationM=2100; p.reliefM=650; p.roads=0; p.rail=0; p.logisticsLevel=0; p.infrastructure=35; p.roadDensity=2; }
    final rough = game.movementCostBetween('FRA',neighbour);
    expect((rough['fuelCost'] as num), greaterThan(connected['fuelCost'] as num));
    expect((rough['supplyLoss'] as num), greaterThan(connected['supplyLoss'] as num));
    game.dispose();
  });

  test('v1.8 offline rules match the authoritative parity contract', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final raw = await rootBundle.loadString('assets/mode_parity_contract.json');
    final contract = jsonDecode(raw) as Map<String,dynamic>;
    expect(contract['protocol'], kProtocolVersion);
    expect(contract['ruleset'], kRulesetVersion);
    final power = Map<String,dynamic>.from(contract['attackPlanPower'] as Map);
    final cost = Map<String,dynamic>.from(contract['attackPlanCost'] as Map);
    for (final plan in ['cautious','balanced','breakthrough']) {
      expect(modeAttackPlanPower(plan), closeTo((power[plan] as num).toDouble(), 1e-9));
      expect(modeAttackPlanCost(plan), closeTo((cost[plan] as num).toDouble(), 1e-9));
    }
    for (final rawCase in contract['battleLossCases'] as List) {
      final c = Map<String,dynamic>.from(rawCase as Map);
      final got = modeBattleLossSeverity((c['ratio'] as num).toDouble(), c['wonRound'] == true);
      expect(got.attacker, closeTo((c['attacker'] as num).toDouble(), 1e-9));
      expect(got.defender, closeTo((c['defender'] as num).toDouble(), 1e-9));
    }
    for (final rawCase in contract['frontlineCases'] as List) {
      final c = Map<String,dynamic>.from(rawCase as Map);
      final got = frontlineProgressDelta((c['ratio'] as num).toDouble(), plan:c['plan'].toString(), encircled:c['encircled']==true, airEdge:(c['airEdge'] as num).toDouble(), navalEdge:(c['navalEdge'] as num).toDouble(), randomFactor:(c['random'] as num).toDouble());
      expect(got, closeTo((c['delta'] as num).toDouble(), 1e-8));
    }
  });

  testWidgets('launch screen exposes local and online entry points', (tester) async {
    await tester.pumpWidget(const WorldDominionApp());
    expect(find.text('WORLD DOMINION'), findsOneWidget);
    expect(find.text('مباراة أونلاين'), findsOneWidget);
    expect(find.byIcon(Icons.public), findsOneWidget);
  });
}
