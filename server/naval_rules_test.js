import test from 'node:test';import assert from 'node:assert/strict';
import {SEA_ZONES,seaZonesForCountry,zoneAdjacent,taskForcePower,taskForceDetection,navalCombatRound,typedMissileRangeKm,layeredInterceptChance,missileDamage,airDefensePenetration} from './naval_rules.js';

test('strategic sea zones form an adjacency graph',()=>{assert.ok(Object.keys(SEA_ZONES).length>=20);assert.equal(zoneAdjacent('med_west','med_east'),true);assert.equal(zoneAdjacent('baltic','south_pacific'),false)});
test('major coastal countries receive realistic multi-theater access',()=>{assert.deepEqual(seaZonesForCountry({iso3:'USA',landlocked:false}).sort(),['gulf_mexico','north_atlantic','north_pacific'].sort());assert.deepEqual(seaZonesForCountry({iso3:'TUR',landlocked:false}).sort(),['black_sea','med_east'].sort());assert.deepEqual(seaZonesForCountry({iso3:'CHE',landlocked:true}),[])});
test('carrier and surface force is stronger than a tiny patrol',()=>{const strong=taskForcePower({surface:4,carriers:1,submarines:2,readiness:90,supply:90},{techAir:3,electronicWarfare:2});const weak=taskForcePower({surface:1,readiness:60,supply:60},{});assert.ok(strong>weak*4);assert.ok(taskForceDetection({surface:3,carriers:1},{radarLevel:3,satelliteRecon:2})>.5)});
test('naval combat produces bounded losses and edge',()=>{const r=navalCombatRound({surface:4,carriers:1,submarines:1,readiness:90,supply:90},{surface:2,carriers:0,submarines:1,readiness:70,supply:70},{techAir:2,radarLevel:2},{radarLevel:1},0);assert.ok(r.edge>0);assert.ok(r.defenderLosses.surface<=2);assert.ok(r.attackerLosses.carriers<=1)});
test('missile types have different range, damage, and interception difficulty',()=>{const c={missileProgram:4,techAir:3};assert.ok(typedMissileRangeKm(c,'hypersonic')>typedMissileRangeKm(c,'cruise'));assert.ok(missileDamage('hypersonic',.5)>missileDamage('cruise',.5));const d={radarLevel:4,earlyWarning:4,missileDefense:4,electronicWarfare:2,army:{airDefense:5}};assert.ok(layeredInterceptChance(d,{fortLevel:2},'cruise')>layeredInterceptChance(d,{fortLevel:2},'hypersonic'))});

test('radar and early warning reduce air penetration while EW helps attacker',()=>{
 const weak=airDefensePenetration({electronicWarfare:0,techIntel:0},{radarLevel:0,earlyWarning:0});
 const layered=airDefensePenetration({electronicWarfare:0,techIntel:0},{radarLevel:5,earlyWarning:5});
 const jammed=airDefensePenetration({electronicWarfare:5,techIntel:5},{radarLevel:5,earlyWarning:5});
 assert.ok(layered<weak);assert.ok(jammed>layered);
});
