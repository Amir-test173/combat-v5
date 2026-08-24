export const COMBAT_UNIT_KEYS=['soldiers','tanks','artillery','airDefense','aircraft','helicopters','drones','recon'];

export const ATTACK_PLAN_SPECS={
  cautious:{name:'حذر',attack:0.90,cost:0.86,exhaustion:3,command:2},
  balanced:{name:'متوازن',attack:1.00,cost:1.00,exhaustion:5,command:2},
  breakthrough:{name:'اختراق',attack:1.22,cost:1.28,exhaustion:9,command:3},
};
export function attackPlanSpec(value='balanced'){return ATTACK_PLAN_SPECS[value]||ATTACK_PLAN_SPECS.balanced}
export function attackPlanPower(value='balanced'){return attackPlanSpec(value).attack}
export function attackPlanCostMultiplier(value='balanced'){return attackPlanSpec(value).cost}

export function clampCombat(n,min,max){return Math.max(min,Math.min(max,n))}

export function applyArmyLosses(army={},severity=0.1){
  const s=clampCombat(Number(severity)||0,0,0.82);
  for(const key of COMBAT_UNIT_KEYS){
    const value=Math.max(0,Number(army[key]||0));
    const protection=key==='recon'?0.35:key==='aircraft'?0.22:key==='airDefense'?0.18:0;
    const effective=s*(1-protection);
    army[key]=Math.max(0,Math.round(value*(1-effective)));
  }
  return army;
}

export function battleProgressDelta(ratio,{plan='balanced',encircled=false,airEdge=0,navalEdge=0,random=0}={}){
  const planBonus=plan==='breakthrough'?7:plan==='cautious'?-4:0;
  const raw=(Number(ratio||0)-0.62)*52+planBonus+(encircled?9:0)+clampCombat(Number(airEdge||0),-1,1)*5+clampCombat(Number(navalEdge||0),-1,1)*4+clampCombat(Number(random||0),-1,1)*8;
  return clampCombat(raw,-18,48);
}

export function controlEdge(attacker,defender){
  const a=Math.max(0,Number(attacker||0)),d=Math.max(0,Number(defender||0));
  if(a+d<=0)return 0;
  return clampCombat((a-d)/(a+d),-1,1);
}

export function battleLossSeverity(ratio,wonRound=false){
  const r=Math.max(0.05,Number(ratio||1));
  const attacker=clampCombat((wonRound ? 0.06 : 0.10)+(r<1?(1-r)*.12:0),.035,.24);
  const defender=clampCombat((wonRound ? 0.13 : 0.08)+(r>1?(r-1)*.07:0),.04,.30);
  return {attacker,defender};
}
