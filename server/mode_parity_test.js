import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { battleLossSeverity, battleProgressDelta, attackPlanPower, attackPlanCostMultiplier } from './combat_rules.js';
import { movementCostProfile } from './advanced_rules.js';

const contract=JSON.parse(fs.readFileSync(new URL('./mode_parity_contract.json',import.meta.url),'utf8'));
const close=(actual,expected,eps=1e-9)=>assert.ok(Math.abs(Number(actual)-Number(expected))<=eps,`${actual} != ${expected}`);

test('v1.8 authoritative server matches offline/online parity contract',()=>{
  assert.equal(contract.protocol,9);
  assert.equal(contract.ruleset,'1.8.0-parity-1');
  for(const [plan,value] of Object.entries(contract.attackPlanPower))close(attackPlanPower(plan),value);
  for(const [plan,value] of Object.entries(contract.attackPlanCost))close(attackPlanCostMultiplier(plan),value);
  for(const c of contract.battleLossCases){const got=battleLossSeverity(c.ratio,c.wonRound);close(got.attacker,c.attacker);close(got.defender,c.defender);}
  for(const c of contract.frontlineCases){close(battleProgressDelta(c.ratio,{plan:c.plan,encircled:c.encircled,airEdge:c.airEdge,navalEdge:c.navalEdge,random:c.random}),c.delta,1e-8);}
  const m=contract.movementCase,p=m.province,got=movementCostProfile(p,p,m.distanceKm);assert.equal(got.fuelCost,m.fuelCost);assert.equal(got.supplyLoss,m.supplyLoss);close(got.routeEfficiency,m.routeEfficiency,0.0011);
});
