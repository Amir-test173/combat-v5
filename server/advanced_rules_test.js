import test from 'node:test';
import assert from 'node:assert/strict';
import {provinceBattleEnvironment,infrastructureCapacity,actualTransportFactor,elevationProfile,landCoverProfile,haversineKm,airRangeKm,missileRangeKm,missileInterceptChance,nextWeather,ewEffect,movementCostProfile} from './advanced_rules.js';

test('terrain and weather materially change combat',()=>{const clear=provinceBattleEnvironment({terrain:'plains',weather:'clear',roads:2,rail:1,infrastructure:70});const mountain=provinceBattleEnvironment({terrain:'mountains',weather:'snow',roads:0,rail:0,infrastructure:45});assert.ok(clear.attack>mountain.attack);assert.ok(mountain.defense>clear.defense);assert.ok(clear.supply>mountain.supply)});
test('roads rail and logistics increase capacity',()=>{assert.ok(infrastructureCapacity({roads:4,rail:3,logisticsLevel:2,infrastructure:80})>infrastructureCapacity({roads:0,rail:0,logisticsLevel:0,infrastructure:40}))});
test('range helpers grow with technology and infrastructure',()=>{assert.ok(airRangeKm({techAir:4,airBases:2})>airRangeKm({techAir:0,airBases:0}));assert.ok(missileRangeKm({techAir:4,missileProgram:3})>missileRangeKm({techAir:0,missileProgram:0}));assert.ok(haversineKm(48.85,2.35,33.89,35.50)>2000)});
test('missile defense and EW are bounded strategic modifiers',()=>{assert.ok(missileInterceptChance({missileDefense:4,army:{airDefense:5}},{fortLevel:3})>.4);assert.ok(ewEffect({electronicWarfare:4},{electronicWarfare:1})>1);assert.ok(ewEffect({electronicWarfare:0},{electronicWarfare:5})<1)});
test('weather generator supports climates',()=>{assert.equal(nextWeather('arctic',.1),'snow');assert.equal(nextWeather('arid',.7),'heatwave');assert.equal(nextWeather('tropical',.2),'rain')});


test('real road density improves logistics without replacing player road upgrades',()=>{
  const sparse={roads:2,rail:1,logisticsLevel:1,infrastructure:65,roadDensity:4,railDensity:0};
  const connected={...sparse,roadDensity:85};
  assert.ok(actualTransportFactor(connected)>actualTransportFactor(sparse));
  assert.ok(infrastructureCapacity(connected)>infrastructureCapacity(sparse));
  assert.ok(infrastructureCapacity({...connected,roads:4})>infrastructureCapacity(connected));
});

test('elevation and relief create a defensive mountain advantage and slower movement',()=>{
  const low=elevationProfile({elevationM:90,reliefM:45});
  const high=elevationProfile({elevationM:2200,reliefM:700});
  assert.ok(high.defense>low.defense);
  assert.ok(high.mobility<low.mobility);
  assert.ok(high.armor<low.armor);
});

test('real land cover affects combat profile',()=>{
  const urban=landCoverProfile('built_up');
  const grass=landCoverProfile('grassland');
  assert.ok(urban.defense>grass.defense);
  assert.ok(urban.mobility<grass.mobility);
  const envUrban=provinceBattleEnvironment({terrain:'plains',weather:'clear',landCover:'built_up',elevationM:100,reliefM:40,roads:2,roadDensity:60,infrastructure:70});
  const envGrass=provinceBattleEnvironment({terrain:'plains',weather:'clear',landCover:'grassland',elevationM:100,reliefM:40,roads:2,roadDensity:60,infrastructure:70});
  assert.ok(envUrban.defense>envGrass.defense);
  assert.ok(envUrban.mobility<envGrass.mobility);
});


test('physical movement cost rises with distance and weak terrain logistics',()=>{
  const connected={terrain:'plains',weather:'clear',landCover:'grassland',elevationM:80,reliefM:30,roads:4,rail:3,logisticsLevel:2,infrastructure:82,roadDensity:90,railDensity:18};
  const rough={terrain:'mountains',weather:'snow',landCover:'tree_cover',elevationM:2100,reliefM:680,roads:0,rail:0,logisticsLevel:0,infrastructure:38,roadDensity:3,railDensity:0};
  const easy=movementCostProfile(connected,connected,260),hard=movementCostProfile(rough,rough,260),far=movementCostProfile(connected,connected,1100);
  assert.ok(hard.fuelCost>easy.fuelCost);assert.ok(hard.supplyLoss>easy.supplyLoss);assert.ok(far.fuelCost>easy.fuelCost);assert.ok(far.supplyLoss>easy.supplyLoss);
});
