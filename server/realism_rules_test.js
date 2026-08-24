import test from 'node:test';
import assert from 'node:assert/strict';
import {safePace,turnSecondsForPace,hegemonyStartTurn,commandBaseForPace,provinceReadiness} from './realism_rules.js';

test('pace presets support hours to long campaigns',()=>{assert.equal(turnSecondsForPace('rapid'),300);assert.equal(turnSecondsForPace('campaign'),3600);assert.equal(turnSecondsForPace('grand'),43200);assert.equal(safePace('bad'),'campaign')});
test('pace changes strategic tempo without deleting rules',()=>{assert.equal(commandBaseForPace('rapid'),8);assert.equal(commandBaseForPace('campaign'),6);assert.equal(commandBaseForPace('grand'),5);assert.deepEqual(['rapid','campaign','grand'].map(hegemonyStartTurn),[15,25,40])});
test('province infrastructure and supply change defensive readiness',()=>{assert.ok(provinceReadiness({infrastructure:90,supply:90})>provinceReadiness({infrastructure:35,supply:25}));assert.ok(provinceReadiness({infrastructure:60,supply:70})>0)});
