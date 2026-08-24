const clamp=(n,a,b)=>Math.max(a,Math.min(b,n));

export const SEA_ZONES={
 arctic:{nameEn:'Arctic Ocean',nameAr:'المحيط المتجمد الشمالي',lat:74,lng:20,adj:['north_atlantic','north_pacific','baltic']},
 north_atlantic:{nameEn:'North Atlantic',nameAr:'شمال الأطلسي',lat:49,lng:-32,adj:['arctic','mid_atlantic','caribbean','baltic','med_west']},
 mid_atlantic:{nameEn:'Central Atlantic',nameAr:'وسط الأطلسي',lat:15,lng:-30,adj:['north_atlantic','caribbean','south_atlantic','med_west']},
 caribbean:{nameEn:'Caribbean Sea',nameAr:'البحر الكاريبي',lat:18,lng:-73,adj:['north_atlantic','mid_atlantic','gulf_mexico']},
 gulf_mexico:{nameEn:'Gulf of Mexico',nameAr:'خليج المكسيك',lat:24,lng:-89,adj:['caribbean','north_atlantic']},
 south_atlantic:{nameEn:'South Atlantic',nameAr:'جنوب الأطلسي',lat:-25,lng:-20,adj:['mid_atlantic','southern_ocean','indian_ocean']},
 baltic:{nameEn:'Baltic Sea',nameAr:'بحر البلطيق',lat:58,lng:19,adj:['north_atlantic','arctic']},
 med_west:{nameEn:'Western Mediterranean',nameAr:'غرب المتوسط',lat:38,lng:5,adj:['north_atlantic','mid_atlantic','med_east']},
 med_east:{nameEn:'Eastern Mediterranean',nameAr:'شرق المتوسط',lat:34,lng:27,adj:['med_west','black_sea','red_sea']},
 black_sea:{nameEn:'Black Sea',nameAr:'البحر الأسود',lat:43,lng:34,adj:['med_east']},
 red_sea:{nameEn:'Red Sea',nameAr:'البحر الأحمر',lat:20,lng:38,adj:['med_east','arabian_sea']},
 persian_gulf:{nameEn:'Persian Gulf',nameAr:'الخليج',lat:26,lng:52,adj:['arabian_sea']},
 arabian_sea:{nameEn:'Arabian Sea',nameAr:'بحر العرب',lat:15,lng:65,adj:['red_sea','persian_gulf','indian_ocean','bay_bengal']},
 bay_bengal:{nameEn:'Bay of Bengal',nameAr:'خليج البنغال',lat:13,lng:87,adj:['arabian_sea','indian_ocean','south_china']},
 indian_ocean:{nameEn:'Indian Ocean',nameAr:'المحيط الهندي',lat:-18,lng:78,adj:['arabian_sea','bay_bengal','south_atlantic','southern_ocean','south_pacific','south_china']},
 south_china:{nameEn:'South China Sea',nameAr:'بحر الصين الجنوبي',lat:13,lng:114,adj:['bay_bengal','indian_ocean','east_china','central_pacific','south_pacific']},
 east_china:{nameEn:'East China Sea',nameAr:'بحر الصين الشرقي',lat:28,lng:126,adj:['south_china','sea_japan','north_pacific','central_pacific']},
 sea_japan:{nameEn:'Sea of Japan',nameAr:'بحر اليابان',lat:40,lng:135,adj:['east_china','north_pacific']},
 north_pacific:{nameEn:'North Pacific',nameAr:'شمال الهادئ',lat:43,lng:-160,adj:['arctic','sea_japan','east_china','central_pacific']},
 central_pacific:{nameEn:'Central Pacific',nameAr:'وسط الهادئ',lat:5,lng:-155,adj:['north_pacific','east_china','south_china','south_pacific']},
 south_pacific:{nameEn:'South Pacific',nameAr:'جنوب الهادئ',lat:-27,lng:-150,adj:['central_pacific','south_china','indian_ocean','southern_ocean']},
 southern_ocean:{nameEn:'Southern Ocean',nameAr:'المحيط الجنوبي',lat:-58,lng:20,adj:['south_atlantic','indian_ocean','south_pacific']},
};

const MULTI_COAST={
 USA:['north_atlantic','gulf_mexico','north_pacific'],CAN:['north_atlantic','north_pacific','arctic'],MEX:['gulf_mexico','north_pacific'],
 GBR:['north_atlantic'],FRA:['north_atlantic','med_west'],ESP:['north_atlantic','med_west'],PRT:['north_atlantic'],ITA:['med_west','med_east'],GRC:['med_east'],TUR:['med_east','black_sea'],RUS:['arctic','baltic','black_sea','north_pacific'],
 EGY:['med_east','red_sea'],ISR:['med_east'],LBN:['med_east'],SYR:['med_east'],SAU:['red_sea','persian_gulf'],IRN:['persian_gulf'],IRQ:['persian_gulf'],ARE:['persian_gulf'],OMN:['arabian_sea'],YEM:['red_sea','arabian_sea'],
 IND:['arabian_sea','bay_bengal'],PAK:['arabian_sea'],BGD:['bay_bengal'],MMR:['bay_bengal'],THA:['bay_bengal','south_china'],MYS:['south_china','indian_ocean'],IDN:['south_china','indian_ocean','south_pacific'],
 CHN:['south_china','east_china'],JPN:['sea_japan','north_pacific'],KOR:['sea_japan','east_china'],PRK:['sea_japan'],PHL:['south_china','central_pacific'],VNM:['south_china'],
 AUS:['indian_ocean','south_pacific'],NZL:['south_pacific'],BRA:['mid_atlantic','south_atlantic'],ARG:['south_atlantic','southern_ocean'],CHL:['south_pacific'],ZAF:['south_atlantic','indian_ocean'],
};

function haversineKm(aLat,aLng,bLat,bLng){const r=6371,toRad=x=>Number(x||0)*Math.PI/180,dLat=toRad(Number(bLat)-Number(aLat)),dLng=toRad(Number(bLng)-Number(aLng)),x=Math.sin(dLat/2)**2+Math.cos(toRad(aLat))*Math.cos(toRad(bLat))*Math.sin(dLng/2)**2;return 2*r*Math.asin(Math.min(1,Math.sqrt(x)))}
export function seaZonesForCountry(meta={}){const id=String(meta.iso3||meta.id||'').toUpperCase();if(MULTI_COAST[id])return [...MULTI_COAST[id]];if(meta.landlocked===true)return[];const lat=Number(meta.lat||0),lng=Number(meta.lng||0);return Object.entries(SEA_ZONES).map(([id,z])=>({id,d:haversineKm(lat,lng,z.lat,z.lng)})).sort((a,b)=>a.d-b.d).slice(0,1).map(x=>x.id)}
export function zoneAdjacent(a,b){return a===b||(SEA_ZONES[a]?.adj||[]).includes(b)}
export function taskForcePower(tf={},country={}){const ready=.45+clamp(Number(tf.readiness??70),0,100)/180,supply=.50+clamp(Number(tf.supply??75),0,100)/200,tech=1+Math.max(0,Number(country.techAir||0))*.035+Math.max(0,Number(country.electronicWarfare||0))*.025;return (Number(tf.surface||0)*4.2+Number(tf.carriers||0)*11+Number(tf.submarines||0)*7.2)*ready*supply*tech}
export function carrierAirWing(tf={},country={}){return Number(tf.carriers||0)*(5+Math.max(0,Number(country.techAir||0))*1.35)*(.50+clamp(Number(tf.readiness??70),0,100)/180)}
export function taskForceDetection(tf={},country={}){return clamp(.20+Number(tf.surface||0)*.035+Number(tf.carriers||0)*.07+Number(country.radarLevel||0)*.06+Number(country.earlyWarning||0)*.05+Number(country.satelliteRecon||0)*.035-Number(tf.submarines||0)*.01,.12,.96)}
export function airDefensePenetration(attacker={},defender={}){const network=Math.max(0,Number(defender.radarLevel||0))*.032+Math.max(0,Number(defender.earlyWarning||0))*.028;const penetration=Math.max(0,Number(attacker.electronicWarfare||0))*.025+Math.max(0,Number(attacker.techIntel||0))*.008;return clamp(1-network+penetration,.68,1.06)}
export function navalCombatRound(attacker={},defender={},attackerCountry={},defenderCountry={},randomFactor=0){
 const aDetect=taskForceDetection(attacker,attackerCountry),dDetect=taskForceDetection(defender,defenderCountry);
 const aSub=Number(attacker.submarines||0)*7.2*(.45+dDetect*.55),dSub=Number(defender.submarines||0)*7.2*(.45+aDetect*.55);
 const a=taskForcePower(attacker,attackerCountry)+carrierAirWing(attacker,attackerCountry)+aSub;
 const d=taskForcePower(defender,defenderCountry)+carrierAirWing(defender,defenderCountry)+dSub;
 const edge=(a-d)/Math.max(1,a+d),swing=clamp(Number(randomFactor||0),-1,1)*.12,score=edge+swing;
 const aSeverity=clamp(.08-score*.12,.025,.24),dSeverity=clamp(.08+score*.12,.025,.24);
 const losses=(tf,severity)=>({surface:Math.min(Number(tf.surface||0),Math.floor(Number(tf.surface||0)*severity+.35)),carriers:Math.min(Number(tf.carriers||0),Math.floor(Number(tf.carriers||0)*severity*.55+.08)),submarines:Math.min(Number(tf.submarines||0),Math.floor(Number(tf.submarines||0)*severity*.75+.16))});
 return {attackerPower:a,defenderPower:d,edge:clamp(score,-1,1),attackerLosses:losses(attacker,aSeverity),defenderLosses:losses(defender,dSeverity)};
}

export const MISSILE_TYPES={
 cruise:{nameEn:'Cruise missile',nameAr:'صاروخ كروز',minProgram:1,baseRange:1050,programRange:420,damage:[22,40],interceptFactor:1.00,cost:{fuel:3,power:2,steel:6,money:11}},
 ballistic:{nameEn:'Ballistic missile',nameAr:'صاروخ باليستي',minProgram:2,baseRange:2200,programRange:720,damage:[32,55],interceptFactor:.76,cost:{fuel:4,power:4,steel:9,money:16}},
 hypersonic:{nameEn:'Hypersonic missile',nameAr:'صاروخ فرط صوتي',minProgram:4,baseRange:2800,programRange:900,damage:[40,64],interceptFactor:.42,cost:{fuel:5,power:6,steel:12,money:23}},
};
export function missileTypeSpec(type){return MISSILE_TYPES[String(type||'cruise')]||MISSILE_TYPES.cruise}
export function typedMissileRangeKm(country={},type='cruise'){const s=missileTypeSpec(type);return s.baseRange+Math.max(0,Number(country.missileProgram||0))*s.programRange+Math.max(0,Number(country.techAir||0))*180}
export function layeredInterceptChance(defender={},province={},type='cruise'){
 const s=missileTypeSpec(type),radar=Math.max(0,Number(defender.radarLevel||0)),warning=Math.max(0,Number(defender.earlyWarning||0)),md=Math.max(0,Number(defender.missileDefense||0)),ad=Math.max(0,Number(defender.army?.airDefense||0)),ew=Math.max(0,Number(defender.electronicWarfare||0)),fort=Math.max(0,Number(province?.fortLevel||0));
 const raw=.05+radar*.055+warning*.05+md*.105+ad*.010+ew*.018+fort*.008;
 return clamp(raw*s.interceptFactor,.03,type==='hypersonic'?0.58:0.88);
}
export function missileDamage(type='cruise',roll=.5){const [lo,hi]=missileTypeSpec(type).damage;return lo+(hi-lo)*clamp(Number(roll),0,1)}
