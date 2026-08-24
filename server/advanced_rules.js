export const TERRAIN={
 plains:{attack:1,defense:1,mobility:1,armor:1,air:1},
 hills:{attack:.92,defense:1.12,mobility:.86,armor:.82,air:.96},
 mountains:{attack:.76,defense:1.32,mobility:.62,armor:.58,air:.90},
 desert:{attack:.93,defense:.94,mobility:.88,armor:1.05,air:1.04},
 forest:{attack:.84,defense:1.18,mobility:.72,armor:.68,air:.88},
 jungle:{attack:.74,defense:1.24,mobility:.54,armor:.48,air:.82},
 urban:{attack:.72,defense:1.34,mobility:.58,armor:.62,air:.84},
 arctic:{attack:.72,defense:1.12,mobility:.50,armor:.62,air:.78},
};
export const WEATHER={clear:{mobility:1,air:1,supply:1},rain:{mobility:.86,air:.86,supply:.91},storm:{mobility:.68,air:.58,supply:.72},snow:{mobility:.68,air:.78,supply:.76},heatwave:{mobility:.88,air:.94,supply:.82}};
export const LAND_COVER={
 unknown:{attack:1,defense:1,mobility:1,armor:1,supply:1,air:1},
 tree_cover:{attack:.89,defense:1.15,mobility:.78,armor:.73,supply:.93,air:.91},
 shrubland:{attack:.97,defense:1.04,mobility:.94,armor:.96,supply:.96,air:1},
 grassland:{attack:1.02,defense:.98,mobility:1.05,armor:1.06,supply:1.02,air:1.02},
 cropland:{attack:1,defense:.98,mobility:1.02,armor:1.02,supply:1.04,air:1},
 built_up:{attack:.80,defense:1.25,mobility:.72,armor:.74,supply:1.08,air:.89},
 bare_sparse:{attack:1.01,defense:.95,mobility:.96,armor:1.04,supply:.90,air:1.04},
 snow_ice:{attack:.75,defense:1.10,mobility:.55,armor:.64,supply:.72,air:.80},
 water:{attack:.68,defense:.75,mobility:.35,armor:.30,supply:.70,air:1.02},
 wetland:{attack:.76,defense:1.14,mobility:.50,armor:.46,supply:.82,air:.89},
 mangroves:{attack:.70,defense:1.23,mobility:.43,armor:.38,supply:.78,air:.82},
 moss_lichen:{attack:.84,defense:1.05,mobility:.72,armor:.77,supply:.84,air:.90},
};
const clamp=(n,a,b)=>Math.max(a,Math.min(b,n));
export function terrainProfile(value){return TERRAIN[String(value||'')]||TERRAIN.plains}
export function weatherProfile(value){return WEATHER[String(value||'')]||WEATHER.clear}
export function landCoverProfile(value){return LAND_COVER[String(value||'unknown')]||LAND_COVER.unknown}
export function actualTransportFactor(p={}){const road=Math.max(0,Number(p.roadDensity||0)),rail=Math.max(0,Number(p.railDensity||0));return clamp(.82+Math.min(.30,road/220)+Math.min(.18,rail/90),.78,1.30)}
export function elevationProfile(p={}){const elev=Math.max(-200,Number(p.elevationM||0)),relief=Math.max(0,Number(p.reliefM||0));const high=Math.max(0,elev-900)/2800,rough=Math.min(1,relief/650);return {attack:clamp(1-high*.11-rough*.13,.68,1.04),defense:clamp(1+high*.10+rough*.18,.95,1.34),mobility:clamp(1-high*.15-rough*.25,.52,1.03),armor:clamp(1-high*.12-rough*.26,.50,1.04),supply:clamp(1-high*.10-rough*.18,.62,1.02),air:clamp(1-high*.025,.92,1.02)}}
export function infrastructureCapacity(p={}){const roads=clamp(Number(p.roads||0),0,5),rail=clamp(Number(p.rail||0),0,5),hub=clamp(Number(p.logisticsLevel||0),0,5),infra=clamp(Number(p.infrastructure??60),15,100),physical=actualTransportFactor(p);return clamp((.45+roads*.10+rail*.07+hub*.11+infra/310)*physical,.32,1.95)}
export function provinceBattleEnvironment(p={}){const t=terrainProfile(p.terrain),w=weatherProfile(p.weather),lc=landCoverProfile(p.landCover),e=elevationProfile(p),cap=infrastructureCapacity(p);return {attack:t.attack*w.mobility*lc.attack*e.attack,defense:t.defense*lc.defense*e.defense,mobility:t.mobility*w.mobility*lc.mobility*e.mobility,supply:w.supply*cap*lc.supply*e.supply,air:t.air*w.air*lc.air*e.air,armor:t.armor*w.mobility*lc.armor*e.armor,transport:actualTransportFactor(p)}}
export function movementCostProfile(fromProvince={},toProvince={},distanceKm=250){const a=provinceBattleEnvironment(fromProvince),b=provinceBattleEnvironment(toProvince),distance=clamp(Number(distanceKm||0),25,4000),mobility=clamp(Math.sqrt(Math.max(.05,a.mobility)*Math.max(.05,b.mobility)),.30,1.35),supply=clamp(Math.sqrt(Math.max(.05,a.supply)*Math.max(.05,b.supply)),.30,1.65),routeEfficiency=clamp(Math.sqrt(mobility*supply),.32,1.48),distanceLoad=clamp(distance/500,.25,5.5),fuelCost=Math.ceil(clamp(.7+distanceLoad*1.08/routeEfficiency,1,9)),supplyLoss=Math.round(clamp(1.5+distanceLoad*3.2/routeEfficiency,2,22));return {fuelCost,supplyLoss,mobility:round3(mobility),supply:round3(supply),routeEfficiency:round3(routeEfficiency),distanceKm:Math.round(distance)}}
function round3(n){return Math.round(Number(n)*1000)/1000}
export function haversineKm(aLat,aLng,bLat,bLng){const r=6371,toRad=x=>Number(x||0)*Math.PI/180,dLat=toRad(Number(bLat)-Number(aLat)),dLng=toRad(Number(bLng)-Number(aLng)),x=Math.sin(dLat/2)**2+Math.cos(toRad(aLat))*Math.cos(toRad(bLat))*Math.sin(dLng/2)**2;return 2*r*Math.asin(Math.min(1,Math.sqrt(x)))}
export function airRangeKm(country={}){return 900+Math.max(0,Number(country.techAir||0))*260+Math.max(0,Number(country.airBases||0))*170}
export function missileRangeKm(country={}){return 1200+Math.max(0,Number(country.techAir||0))*350+Math.max(0,Number(country.missileProgram||0))*650}
export function missileInterceptChance(defender={},province={}){const base=.08+Math.max(0,Number(defender.missileDefense||0))*.11+Math.max(0,Number(defender.army?.airDefense||0))*.012+Math.max(0,Number(province?.fortLevel||0))*.01;return Math.max(.05,Math.min(.78,base))}
export function ewEffect(attacker={},defender={}){const edge=Math.max(-5,Math.min(5,Number(attacker.electronicWarfare||0)-Number(defender.electronicWarfare||0)));return 1+edge*.045}
export function nextWeather(climate='temperate',roll=.5){const r=Math.max(0,Math.min(.999,Number(roll)));if(climate==='arctic')return r<.55?'snow':r<.76?'storm':'clear';if(climate==='tropical')return r<.36?'rain':r<.50?'storm':r<.87?'clear':'heatwave';if(climate==='arid')return r<.68?'clear':r<.88?'heatwave':'storm';if(climate==='continental')return r<.20?'snow':r<.38?'rain':r<.48?'storm':'clear';return r<.22?'rain':r<.30?'storm':r<.36?'snow':'clear'}
