import test from 'node:test';
import assert from 'node:assert/strict';
import {applyArmyLosses,battleProgressDelta,controlEdge,battleLossSeverity} from './combat_rules.js';

test('frontline progress rewards superiority and encirclement',()=>{
  const even=battleProgressDelta(1,{random:0});
  const strong=battleProgressDelta(1.5,{plan:'breakthrough',encircled:true,random:0});
  assert.ok(even>0&&even<30);
  assert.ok(strong>even);
  assert.ok(strong<=48);
});

test('combat losses never create units',()=>{
  const army={soldiers:10,tanks:4,artillery:2,airDefense:2,aircraft:2,helicopters:1,drones:2,recon:1};
  const before={...army};applyArmyLosses(army,.2);
  for(const key of Object.keys(before))assert.ok(army[key]>=0&&army[key]<=before[key]);
});

test('air/naval control edge stays bounded',()=>{
  assert.equal(controlEdge(0,0),0);
  assert.ok(controlEdge(10,2)>0);
  assert.ok(controlEdge(2,10)<0);
  assert.ok(Math.abs(controlEdge(999,1))<=1);
});

test('loss model penalizes the weaker side appropriately',()=>{
  const strong=battleLossSeverity(1.6,true);
  assert.ok(strong.defender>strong.attacker);
  const weak=battleLossSeverity(.55,false);
  assert.ok(weak.attacker>weak.defender);
});
