// Server-owned initial world seed. Clients never provide the authoritative starting snapshot.
import fs from 'fs';
let worldData=[];try{worldData=JSON.parse(fs.readFileSync(new URL('./world_game_data.json',import.meta.url),'utf8'))}catch{}
export const WORLD_DATA=worldData;
export const WORLD_ADJACENCY=Object.fromEntries(worldData.map(c=>[c.iso3,Array.isArray(c.borders)?c.borders:[]]));
export const WORLD_COASTAL=new Set(worldData.filter(c=>!c.landlocked).map(c=>c.iso3));
export const PLAYABLE_COUNTRIES = new Set([...'USA CAN MEX BRA ARG GBR FRA ESP DEU ITA POL UKR RUS MAR DZA EGY GRC TUR GEO SYR LBN ISR JOR IRQ SAU YEM ARE OMN IRN AFG PAK IND BGD CHN KAZ MNG PRK KOR JPN MMR THA MYS IDN AUS'.split(' '),...worldData.map(c=>c.iso3)]);


const rows = [
  ['USA',335,10,9,12,15,10,18,'واشنطن'],
  ['CAN',40,10,15,10,7,4,8,'العاصمة'],
  ['MEX',129,13,9,5,7,4,8,'العاصمة'],
  ['BRA',216,18,13,5,7,4,8,'العاصمة'],
  ['ARG',46,16,9,5,7,4,8,'العاصمة'],
  ['GBR',68,10,9,5,7,4,12,'العاصمة'],
  ['FRA',68,12,9,5,10,4,12,'باريس'],
  ['ESP',48,10,9,5,7,4,8,'العاصمة'],
  ['DEU',84,10,9,5,7,10,14,'العاصمة'],
  ['ITA',59,10,9,5,7,4,8,'العاصمة'],
  ['POL',38,10,9,5,7,7,8,'العاصمة'],
  ['UKR',37,16,9,5,7,4,8,'العاصمة'],
  ['RUS',146,10,9,18,11,12,8,'العاصمة'],
  ['MAR',38,10,9,5,7,4,8,'العاصمة'],
  ['DZA',46,10,9,14,7,4,8,'العاصمة'],
  ['EGY',112,9,9,5,7,4,8,'العاصمة'],
  ['GRC',10,10,9,5,7,4,8,'العاصمة'],
  ['TUR',86,12,9,5,7,7,8,'أنقرة'],
  ['GEO',4,10,9,5,7,4,8,'العاصمة'],
  ['SYR',23,10,9,5,7,4,8,'العاصمة'],
  ['LBN',6,10,9,5,7,4,6,'بيروت'],
  ['ISR',10,10,9,5,9,4,11,'العاصمة'],
  ['JOR',11,10,4,5,7,4,8,'العاصمة'],
  ['IRQ',46,10,9,15,7,4,8,'العاصمة'],
  ['SAU',37,10,9,20,7,4,14,'العاصمة'],
  ['YEM',34,10,9,5,7,4,8,'العاصمة'],
  ['ARE',10,10,9,14,7,4,16,'العاصمة'],
  ['OMN',5,10,9,11,7,4,8,'العاصمة'],
  ['IRN',89,10,9,16,7,8,8,'العاصمة'],
  ['AFG',43,10,9,5,7,4,8,'العاصمة'],
  ['PAK',241,10,9,5,7,4,8,'العاصمة'],
  ['IND',1420,15,9,5,7,9,8,'العاصمة'],
  ['BGD',173,10,9,5,7,4,8,'العاصمة'],
  ['CHN',1410,10,9,5,15,16,14,'بكين'],
  ['KAZ',20,10,9,13,7,4,8,'العاصمة'],
  ['MNG',3,10,9,5,7,8,8,'العاصمة'],
  ['PRK',26,10,9,5,7,4,8,'العاصمة'],
  ['KOR',52,10,9,5,12,4,15,'العاصمة'],
  ['JPN',124,10,9,5,12,4,16,'العاصمة'],
  ['MMR',55,10,9,5,7,4,8,'العاصمة'],
  ['THA',72,13,9,5,7,4,8,'العاصمة'],
  ['MYS',34,10,9,8,7,4,8,'العاصمة'],
  ['IDN',279,12,9,9,7,4,8,'العاصمة'],
  ['AUS',27,14,9,5,7,12,8,'العاصمة']
];
const coastal = new Set(['ARE', 'ARG', 'AUS', 'BGD', 'BRA', 'CAN', 'CHN', 'DZA', 'EGY', 'ESP', 'FRA', 'GBR', 'GEO', 'IDN', 'IND', 'IRN', 'ISR', 'ITA', 'JPN', 'KOR', 'LBN', 'MAR', 'MEX', 'MMR', 'MYS', 'OMN', 'PAK', 'PRK', 'SAU', 'SYR', 'THA', 'TUR', 'USA', 'YEM']);

function countryState([id,pop,food,water,fuel,power,steel,money]) {
  return {
    id, controller:`AI:${id}`, population:pop, stability:72, approval:64,
    stock:{food:75+food*2,water:75+water*2,fuel:55+fuel*2,power:65+power*2,steel:45+steel*2,money:70+money*2,gold:30},
    production:{food,water,fuel,power,steel,money,gold:2},
    army:{
      soldiers:6+Math.min(32,Math.round(Math.sqrt(pop)*1.2)),
      tanks:Math.max(1,Math.min(5,Math.round((steel+money)/10))),
      artillery:Math.max(1,Math.min(4,Math.round((steel+money)/12))),
      airDefense:Math.max(1,Math.min(3,Math.round((power+money)/18))),
      aircraft:Math.max(1,Math.min(4,Math.round((power+money)/12))),
      helicopters:(power+money)>=28?1:0,drones:1,recon:1,
      navy:coastal.has(id)?Math.max(1,Math.min(3,Math.round((fuel+money)/14))):0
    },
    solar:0,nuclear:0,grid:1,farms:1,foodFactories:1,civilianIndustry:1,militaryIndustry:1,
    airBases:0,navalBases:0,supplyHubs:1,trainingCamps:0,borderDefense:0,recruitedThisTurn:0,supply:72,morale:70,intelligence:20,resistance:0,
    warExhaustion:0,commandPoints:6,occupationPolicy:'balanced',
    techAgriculture:0,techIndustry:0,techLogistics:0,techArmor:0,techAir:0,techIntel:0,
    missileStock:0,cruiseMissiles:0,ballisticMissiles:0,hypersonicMissiles:0,missileDefense:0,missileProgram:0,electronicWarfare:0,satelliteRecon:0,radarLevel:0,earlyWarning:0,carrierStock:0,submarineStock:0,airReadiness:70,fleetReadiness:70
  };
}

function sitesFor(row) {
  const [id,,,,,,,,capital] = row;
  const xs=[
    {id:`${id}_CAP`,countryId:id,name:capital,kind:'capital',dx:0,dy:0,health:100,level:1},
    {id:`${id}_FAC`,countryId:id,name:'المجمع الصناعي',kind:'factory',dx:.010,dy:.014,health:100,level:1},
    {id:`${id}_PWR`,countryId:id,name:'محطة الطاقة',kind:'power',dx:-.012,dy:.012,health:100,level:1},
    {id:`${id}_SUP`,countryId:id,name:'مركز الإمداد',kind:'supply',dx:.012,dy:-.014,health:100,level:1},
    {id:`${id}_AIR`,countryId:id,name:'القاعدة الجوية',kind:'airport',dx:-.013,dy:-.014,health:100,level:1},
  ];
  if(coastal.has(id)) xs.push({id:`${id}_PRT`,countryId:id,name:'الميناء الرئيسي',kind:'port',dx:.020,dy:.002,health:100,level:1});
  return xs;
}

function sitesForWorld(w) {
  const id=String(w.iso3||'').toUpperCase(),capital=String(w.capital||w.nameEn||id);if(!id)return [];
  const xs=[
    {id:`${id}_CAP`,countryId:id,name:capital,kind:'capital',dx:0,dy:0,health:100,level:1},
    {id:`${id}_FAC`,countryId:id,name:'المجمع الصناعي',kind:'factory',dx:.010,dy:.014,health:100,level:1},
    {id:`${id}_PWR`,countryId:id,name:'محطة الطاقة',kind:'power',dx:-.012,dy:.012,health:100,level:1},
    {id:`${id}_SUP`,countryId:id,name:'مركز الإمداد',kind:'supply',dx:.012,dy:-.014,health:100,level:1},
    {id:`${id}_AIR`,countryId:id,name:'القاعدة الجوية',kind:'airport',dx:-.013,dy:-.014,health:100,level:1},
  ];
  if(!w.landlocked)xs.push({id:`${id}_PRT`,countryId:id,name:'الميناء الرئيسي',kind:'port',dx:.020,dy:.002,health:100,level:1});
  return xs;
}

export function createInitialSnapshot(countryOwners,{pace='campaign'}={}) {
  const countries=Object.fromEntries(rows.map(r=>[r[0],countryState(r)]));
  if(worldData.length){for(const w of worldData){const id=String(w.iso3||'').toUpperCase();if(!id)continue;if(!countries[id]){const pop=Math.max(.1,Number(w.population||1000000)/1000000),coastal=!w.landlocked;countries[id]={id,controller:`AI:${id}`,population:pop,stability:72,approval:64,stock:{food:95,water:95,fuel:70,power:80,steel:60,money:90,gold:28},production:{food:10,water:9,fuel:5,power:7,steel:5,money:8,gold:2},army:{soldiers:6+Math.min(30,Math.round(Math.sqrt(pop)*1.15)),tanks:1,artillery:1,airDefense:1,aircraft:1,helicopters:0,drones:1,recon:1,navy:coastal?1:0},solar:0,nuclear:0,grid:1,farms:1,foodFactories:1,civilianIndustry:1,militaryIndustry:1,airBases:0,navalBases:0,supplyHubs:1,trainingCamps:0,borderDefense:0,recruitedThisTurn:0,supply:72,morale:70,intelligence:20,resistance:0,warExhaustion:0,commandPoints:6,occupationPolicy:'balanced',techAgriculture:0,techIndustry:0,techLogistics:0,techArmor:0,techAir:0,techIntel:0,missileStock:0,cruiseMissiles:0,ballisticMissiles:0,hypersonicMissiles:0,missileDefense:0,missileProgram:0,electronicWarfare:0,satelliteRecon:0,radarLevel:0,earlyWarning:0,carrierStock:0,submarineStock:0,airReadiness:70,fleetReadiness:70};}}}
  for(const country of countryOwners.keys()) if(countries[country]) countries[country].controller=`P:${country}`;
  const paceBase=pace==='rapid'?8:(pace==='grand'?5:6);for(const c of Object.values(countries))c.commandPoints=paceBase;
  const provinces=[];if(worldData.length){for(const w of worldData){const c=countries[w.iso3];if(!c)continue;const rs=Array.isArray(w.regions)&&w.regions.length?w.regions:[{code:`${w.iso3}-CENTRAL`,nameEn:w.capital||'Central',nameAr:w.capital||'المركز',lat:w.lat,lng:w.lng}];for(let i=0;i<rs.length;i++){const raw=rs[i],r=(raw&&typeof raw==='object')?raw:{nameEn:String(raw),nameAr:String(raw)};provinces.push({id:`${w.iso3}_P${i}`,countryId:w.iso3,code:String(r.code||`${w.iso3}-P${i}`),name:String(r.nameAr||r.nameEn||`Region ${i+1}`),nameEn:String(r.nameEn||r.nameAr||`Region ${i+1}`),controller:c.controller,population:Math.max(.05,c.population/rs.length),lat:Number(r.lat??w.lat??0),lng:Number(r.lng??w.lng??0),resistance:0,infrastructure:i===0?82:58,supply:i===0?82:70,garrison:i===0?Math.max(1,Math.round(c.army.soldiers/5)):0,fortLevel:0,trainingCamps:0,terrain:String(r.terrain||'plains'),climate:String(r.climate||'temperate'),weather:'clear',roads:i===0?2:1,rail:i===0?1:0,logisticsLevel:i===0?1:0,elevationM:Number(r.elevationM||0),elevationMinM:Number(r.elevationMinM??r.elevationM??0),elevationMaxM:Number(r.elevationMaxM??r.elevationM??0),elevationSamples:Number(r.elevationSamples||0),reliefM:Number(r.reliefM||0),landCover:String(r.landCover||'unknown'),landCoverMix:(r.landCoverMix&&typeof r.landCoverMix==='object')?r.landCoverMix:{},landCoverSamples:Number(r.landCoverSamples||0),areaSqKm:Number(r.areaSqKm||0),actualRoadKm:Number(r.actualRoadKm||0),actualRailKm:Number(r.actualRailKm||0),roadDensity:Number(r.roadDensity||0),railDensity:Number(r.railDensity||0),roadClassKm:(r.roadClassKm&&typeof r.roadClassKm==='object')?r.roadClassKm:{},railClassKm:(r.railClassKm&&typeof r.railClassKm==='object')?r.railClassKm:{},physicalDataQuality:String(r.physicalDataQuality||'fallback'),transportDataQuality:String(r.transportDataQuality||'fallback')});}}}
  return {
    turn:1, gamePace:pace, alliances:[], sanctions:[], tradeDeals:[], diplomaticOffers:[], countries,
    logs:['الدور 1 — بدأت المباراة الأونلاين.'], fieldArmies:[], navalTaskForces:[], battles:[], provinces, strategicSites:[...rows.flatMap(sitesFor),...worldData.filter(w=>!rows.some(r=>r[0]===w.iso3)).flatMap(sitesForWorld)],
    events:[], winner:null, victoryType:null
  };
}
