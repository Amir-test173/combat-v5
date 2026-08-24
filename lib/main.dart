import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:countries_world_map/countries_world_map.dart';
import 'package:countries_world_map/data/maps/world_map.dart';
import 'package:url_launcher/url_launcher.dart';

const kAppVersion='1.8.0-clean-build-parity';
const kProtocolVersion=9;
const kRulesetVersion='1.8.0-parity-1';
const kDefaultServerUrl=String.fromEnvironment('DEFAULT_SERVER_URL',defaultValue:'');
const kPrivacyPolicyUrl=String.fromEnvironment('PRIVACY_POLICY_URL',defaultValue:'');
const kSupportEmail=String.fromEnvironment('SUPPORT_EMAIL',defaultValue:'');
const kAllowInsecureWs=bool.fromEnvironment('ALLOW_INSECURE_WS',defaultValue:false);
String _serverHttpBase(String value){var v=value.trim();if(v.startsWith('wss://'))v='https://${v.substring(6)}';if(v.startsWith('ws://'))v='http://${v.substring(5)}';return v.replaceAll(RegExp(r'/+$'),'');}
String get kEffectivePrivacyPolicyUrl=>kPrivacyPolicyUrl.isNotEmpty?kPrivacyPolicyUrl:(kDefaultServerUrl.isNotEmpty?'${_serverHttpBase(kDefaultServerUrl)}/privacy':'');
String get kEffectiveTermsUrl=>kDefaultServerUrl.isNotEmpty?'${_serverHttpBase(kDefaultServerUrl)}/terms':'';
int _jsonInt(dynamic value,[int fallback=0])=>value is num?value.toInt():fallback;
double _jsonDouble(dynamic value,[double fallback=0])=>value is num?value.toDouble():fallback;

const Map<String,String> kAlpha3To2={
'USA':'US','CAN':'CA','MEX':'MX','BRA':'BR','ARG':'AR','GBR':'GB','FRA':'FR','ESP':'ES','DEU':'DE','ITA':'IT','POL':'PL','UKR':'UA','RUS':'RU','MAR':'MA','DZA':'DZ','EGY':'EG','GRC':'GR','TUR':'TR','GEO':'GE','SYR':'SY','LBN':'LB','ISR':'IL','JOR':'JO','IRQ':'IQ','SAU':'SA','YEM':'YE','ARE':'AE','OMN':'OM','IRN':'IR','AFG':'AF','PAK':'PK','IND':'IN','BGD':'BD','CHN':'CN','KAZ':'KZ','MNG':'MN','PRK':'KP','KOR':'KR','JPN':'JP','MMR':'MM','THA':'TH','MYS':'MY','IDN':'ID','AUS':'AU'};
final Map<String,String> kAlpha2To3={for(final e in kAlpha3To2.entries)e.value:e.key};
const Map<String,List<String>> kSeaLanes={
  'USA':['GBR','FRA','JPN','AUS'],'CAN':['GBR'],'BRA':['MAR','ESP'],'ARG':['ESP'],
  'GBR':['USA','CAN'],'FRA':['USA'],'MAR':['BRA'],'ESP':['BRA','ARG'],
  'JPN':['USA'],'AUS':['USA']
};
String _worldMapKey(String iso2)=>iso2[0].toLowerCase()+iso2[1].toUpperCase();

double frontlineControlEdge(double attacker,double defender){final total=max(0,attacker)+max(0,defender);if(total<=0)return 0;return ((attacker-defender)/total).clamp(-1.0,1.0).toDouble();}
double frontlineProgressDelta(double ratio,{String plan='balanced',bool encircled=false,double airEdge=0,double navalEdge=0,double randomFactor=0}){final planBonus=plan=='breakthrough'?7.0:plan=='cautious'?-4.0:0.0;return ((ratio-.62)*52+planBonus+(encircled?9:0)+airEdge.clamp(-1,1)*5+navalEdge.clamp(-1,1)*4+randomFactor.clamp(-1,1)*8).clamp(-18.0,48.0).toDouble();}
double modeAttackPlanPower(String plan)=>plan=='breakthrough'?1.22:plan=='cautious'?0.90:1.0;
double modeAttackPlanCost(String plan)=>plan=='breakthrough'?1.28:plan=='cautious'?0.86:1.0;
({double attacker,double defender}) modeBattleLossSeverity(double ratio,bool wonRound){final r=max(0.05,ratio);return (attacker:((wonRound?0.06:0.10)+(r<1?(1-r)*0.12:0)).clamp(0.035,0.24).toDouble(),defender:((wonRound?0.13:0.08)+(r>1?(r-1)*0.07:0)).clamp(0.04,0.30).toDouble());}

const Map<String,Map<String,double>> kTerrainProfiles={
  'plains':{'attack':1,'defense':1,'mobility':1,'air':1},'hills':{'attack':.92,'defense':1.12,'mobility':.86,'air':.96},'mountains':{'attack':.76,'defense':1.32,'mobility':.62,'air':.90},'desert':{'attack':.93,'defense':.94,'mobility':.88,'air':1.04},'forest':{'attack':.84,'defense':1.18,'mobility':.72,'air':.88},'jungle':{'attack':.74,'defense':1.24,'mobility':.54,'air':.82},'urban':{'attack':.72,'defense':1.34,'mobility':.58,'air':.84},'arctic':{'attack':.72,'defense':1.12,'mobility':.50,'air':.78},
};
const Map<String,Map<String,double>> kWeatherProfiles={'clear':{'mobility':1,'air':1,'supply':1},'rain':{'mobility':.86,'air':.86,'supply':.91},'storm':{'mobility':.68,'air':.58,'supply':.72},'snow':{'mobility':.68,'air':.78,'supply':.76},'heatwave':{'mobility':.88,'air':.94,'supply':.82}};
const Map<String,Map<String,double>> kLandCoverProfiles={'unknown':{'attack':1,'defense':1,'mobility':1,'armor':1,'supply':1,'air':1},'tree_cover':{'attack':.89,'defense':1.15,'mobility':.78,'armor':.73,'supply':.93,'air':.91},'shrubland':{'attack':.97,'defense':1.04,'mobility':.94,'armor':.96,'supply':.96,'air':1},'grassland':{'attack':1.02,'defense':.98,'mobility':1.05,'armor':1.06,'supply':1.02,'air':1.02},'cropland':{'attack':1,'defense':.98,'mobility':1.02,'armor':1.02,'supply':1.04,'air':1},'built_up':{'attack':.80,'defense':1.25,'mobility':.72,'armor':.74,'supply':1.08,'air':.89},'bare_sparse':{'attack':1.01,'defense':.95,'mobility':.96,'armor':1.04,'supply':.90,'air':1.04},'snow_ice':{'attack':.75,'defense':1.10,'mobility':.55,'armor':.64,'supply':.72,'air':.80},'water':{'attack':.68,'defense':.75,'mobility':.35,'armor':.30,'supply':.70,'air':1.02},'wetland':{'attack':.76,'defense':1.14,'mobility':.50,'armor':.46,'supply':.82,'air':.89},'mangroves':{'attack':.70,'defense':1.23,'mobility':.43,'armor':.38,'supply':.78,'air':.82},'moss_lichen':{'attack':.84,'defense':1.05,'mobility':.72,'armor':.77,'supply':.84,'air':.90}};
const Map<String,Map<String,dynamic>> kSeaZones={
'arctic':{'ar':'المحيط المتجمد الشمالي','en':'Arctic Ocean','lat':74.0,'lng':20.0,'adj':['north_atlantic','north_pacific','baltic']},
'north_atlantic':{'ar':'شمال الأطلسي','en':'North Atlantic','lat':49.0,'lng':-32.0,'adj':['arctic','mid_atlantic','caribbean','baltic','med_west']},
'mid_atlantic':{'ar':'وسط الأطلسي','en':'Central Atlantic','lat':15.0,'lng':-30.0,'adj':['north_atlantic','caribbean','south_atlantic','med_west']},
'caribbean':{'ar':'البحر الكاريبي','en':'Caribbean Sea','lat':18.0,'lng':-73.0,'adj':['north_atlantic','mid_atlantic','gulf_mexico']},
'gulf_mexico':{'ar':'خليج المكسيك','en':'Gulf of Mexico','lat':24.0,'lng':-89.0,'adj':['caribbean','north_atlantic']},
'south_atlantic':{'ar':'جنوب الأطلسي','en':'South Atlantic','lat':-25.0,'lng':-20.0,'adj':['mid_atlantic','southern_ocean','indian_ocean']},
'baltic':{'ar':'بحر البلطيق','en':'Baltic Sea','lat':58.0,'lng':19.0,'adj':['north_atlantic','arctic']},
'med_west':{'ar':'غرب المتوسط','en':'Western Mediterranean','lat':38.0,'lng':5.0,'adj':['north_atlantic','mid_atlantic','med_east']},
'med_east':{'ar':'شرق المتوسط','en':'Eastern Mediterranean','lat':34.0,'lng':27.0,'adj':['med_west','black_sea','red_sea']},
'black_sea':{'ar':'البحر الأسود','en':'Black Sea','lat':43.0,'lng':34.0,'adj':['med_east']},
'red_sea':{'ar':'البحر الأحمر','en':'Red Sea','lat':20.0,'lng':38.0,'adj':['med_east','arabian_sea']},
'persian_gulf':{'ar':'الخليج','en':'Persian Gulf','lat':26.0,'lng':52.0,'adj':['arabian_sea']},
'arabian_sea':{'ar':'بحر العرب','en':'Arabian Sea','lat':15.0,'lng':65.0,'adj':['red_sea','persian_gulf','indian_ocean','bay_bengal']},
'bay_bengal':{'ar':'خليج البنغال','en':'Bay of Bengal','lat':13.0,'lng':87.0,'adj':['arabian_sea','indian_ocean','south_china']},
'indian_ocean':{'ar':'المحيط الهندي','en':'Indian Ocean','lat':-18.0,'lng':78.0,'adj':['arabian_sea','bay_bengal','south_atlantic','southern_ocean','south_pacific','south_china']},
'south_china':{'ar':'بحر الصين الجنوبي','en':'South China Sea','lat':13.0,'lng':114.0,'adj':['bay_bengal','indian_ocean','east_china','central_pacific','south_pacific']},
'east_china':{'ar':'بحر الصين الشرقي','en':'East China Sea','lat':28.0,'lng':126.0,'adj':['south_china','sea_japan','north_pacific','central_pacific']},
'sea_japan':{'ar':'بحر اليابان','en':'Sea of Japan','lat':40.0,'lng':135.0,'adj':['east_china','north_pacific']},
'north_pacific':{'ar':'شمال الهادئ','en':'North Pacific','lat':43.0,'lng':-160.0,'adj':['arctic','sea_japan','east_china','central_pacific']},
'central_pacific':{'ar':'وسط الهادئ','en':'Central Pacific','lat':5.0,'lng':-155.0,'adj':['north_pacific','east_china','south_china','south_pacific']},
'south_pacific':{'ar':'جنوب الهادئ','en':'South Pacific','lat':-27.0,'lng':-150.0,'adj':['central_pacific','south_china','indian_ocean','southern_ocean']},
'southern_ocean':{'ar':'المحيط الجنوبي','en':'Southern Ocean','lat':-58.0,'lng':20.0,'adj':['south_atlantic','indian_ocean','south_pacific']},
};
const Map<String,List<String>> kMultiCoastZones={'USA':['north_atlantic','gulf_mexico','north_pacific'],'CAN':['north_atlantic','north_pacific','arctic'],'MEX':['gulf_mexico','north_pacific'],'GBR':['north_atlantic'],'FRA':['north_atlantic','med_west'],'ESP':['north_atlantic','med_west'],'ITA':['med_west','med_east'],'TUR':['med_east','black_sea'],'RUS':['arctic','baltic','black_sea','north_pacific'],'EGY':['med_east','red_sea'],'LBN':['med_east'],'ISR':['med_east'],'SAU':['red_sea','persian_gulf'],'IRN':['persian_gulf'],'ARE':['persian_gulf'],'OMN':['arabian_sea'],'YEM':['red_sea','arabian_sea'],'IND':['arabian_sea','bay_bengal'],'CHN':['south_china','east_china'],'JPN':['sea_japan','north_pacific'],'AUS':['indian_ocean','south_pacific'],'BRA':['mid_atlantic','south_atlantic'],'ARG':['south_atlantic','southern_ocean'],'ZAF':['south_atlantic','indian_ocean'],'IDN':['south_china','indian_ocean','south_pacific']};
const Map<String,Map<String,dynamic>> kMissileTypes={'cruise':{'ar':'كروز','en':'Cruise','minProgram':1,'baseRange':1050.0,'programRange':420.0,'damageLo':22.0,'damageHi':40.0,'intercept':1.0},'ballistic':{'ar':'باليستي','en':'Ballistic','minProgram':2,'baseRange':2200.0,'programRange':720.0,'damageLo':32.0,'damageHi':55.0,'intercept':.76},'hypersonic':{'ar':'فرط صوتي','en':'Hypersonic','minProgram':4,'baseRange':2800.0,'programRange':900.0,'damageLo':40.0,'damageHi':64.0,'intercept':.42}};
Map<String,double> _terrainProfile(String v)=>kTerrainProfiles[v]??kTerrainProfiles['plains']!;
Map<String,double> _weatherProfile(String v)=>kWeatherProfiles[v]??kWeatherProfiles['clear']!;
Map<String,double> _landCoverProfile(String v)=>kLandCoverProfiles[v]??kLandCoverProfiles['unknown']!;
double _actualTransportFactor(Province? p){if(p==null)return 1;final road=max(0.0,p.roadDensity),rail=max(0.0,p.railDensity);return (.82+min(.30,road/220)+min(.18,rail/90)).clamp(.78,1.30).toDouble();}
Map<String,double> _elevationProfile(Province? p){if(p==null)return const {'attack':1,'defense':1,'mobility':1,'armor':1,'supply':1,'air':1};final elev=max(-200.0,p.elevationM),relief=max(0.0,p.reliefM),high=max(0.0,elev-900)/2800,rough=min(1.0,relief/650);return {'attack':(1-high*.11-rough*.13).clamp(.68,1.04).toDouble(),'defense':(1+high*.10+rough*.18).clamp(.95,1.34).toDouble(),'mobility':(1-high*.15-rough*.25).clamp(.52,1.03).toDouble(),'armor':(1-high*.12-rough*.26).clamp(.50,1.04).toDouble(),'supply':(1-high*.10-rough*.18).clamp(.62,1.02).toDouble(),'air':(1-high*.025).clamp(.92,1.02).toDouble()};}
double _provinceInfrastructureCapacity(Province? p){if(p==null)return 1;return ((.45+p.roads*.10+p.rail*.07+p.logisticsLevel*.11+p.infrastructure/310)*_actualTransportFactor(p)).clamp(.32,1.95).toDouble();}
Map<String,num> _movementCostProfile(Province? from,Province? to,double distanceKm){Map<String,double> env(Province? p){if(p==null)return const {'mobility':1,'supply':1};final t=_terrainProfile(p.terrain),w=_weatherProfile(p.weather),lc=_landCoverProfile(p.landCover),e=_elevationProfile(p),cap=_provinceInfrastructureCapacity(p);return {'mobility':(t['mobility']??1)*(w['mobility']??1)*(lc['mobility']??1)*(e['mobility']??1),'supply':(w['supply']??1)*cap*(lc['supply']??1)*(e['supply']??1)};}final a=env(from),b=env(to),distance=distanceKm.clamp(25.0,4000.0),mobility=sqrt(max(.05,a['mobility']!)*max(.05,b['mobility']!)).clamp(.30,1.35),supply=sqrt(max(.05,a['supply']!)*max(.05,b['supply']!)).clamp(.30,1.65),eff=sqrt(mobility*supply).clamp(.32,1.48),load=(distance/500).clamp(.25,5.5);return {'fuelCost':(.7+load*1.08/eff).clamp(1,9).ceil(),'supplyLoss':(1.5+load*3.2/eff).clamp(2,22).round(),'routeEfficiency':eff,'distanceKm':distance.round()};}
double _haversineKm(double aLat,double aLng,double bLat,double bLng){const r=6371.0;double rad(double x)=>x*pi/180;final dLat=rad(bLat-aLat),dLng=rad(bLng-aLng),x=pow(sin(dLat/2),2)+cos(rad(aLat))*cos(rad(bLat))*pow(sin(dLng/2),2);return 2*r*asin(min(1,sqrt(x)));}
String _nextWeather(Random rng,String climate){final r=rng.nextDouble();if(climate=='arctic')return r<.55?'snow':r<.76?'storm':'clear';if(climate=='tropical')return r<.36?'rain':r<.50?'storm':r<.87?'clear':'heatwave';if(climate=='arid')return r<.68?'clear':r<.88?'heatwave':'storm';if(climate=='continental')return r<.20?'snow':r<.38?'rain':r<.48?'storm':'clear';return r<.22?'rain':r<.30?'storm':r<.36?'snow':'clear';}

void main() => runApp(const WorldDominionApp());

class WorldDominionApp extends StatelessWidget {
  const WorldDominionApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'World Dominion',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal, brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xFF09131C),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class Resources {
  double food, water, fuel, power, steel, money, gold;
  Resources({this.food=100, this.water=100, this.fuel=100, this.power=100, this.steel=80, this.money=100, this.gold=30});
  Resources copy() => Resources(food:food,water:water,fuel:fuel,power:power,steel:steel,money:money,gold:gold);
  Resources scaled(double f)=>Resources(food:food*f,water:water*f,fuel:fuel*f,power:power*f,steel:steel*f,money:money*f,gold:gold*f);
  Map<String,dynamic> toJson()=>{'food':food,'water':water,'fuel':fuel,'power':power,'steel':steel,'money':money,'gold':gold};
  static Resources fromJson(Map<String,dynamic> j)=>Resources(food:(j['food']??0).toDouble(),water:(j['water']??0).toDouble(),fuel:(j['fuel']??0).toDouble(),power:(j['power']??0).toDouble(),steel:(j['steel']??0).toDouble(),money:(j['money']??0).toDouble(),gold:(j['gold']??30).toDouble());
  bool canPay(Resources c)=>food>=c.food&&water>=c.water&&fuel>=c.fuel&&power>=c.power&&steel>=c.steel&&money>=c.money&&gold>=c.gold;
  void pay(Resources c){food-=c.food;water-=c.water;fuel-=c.fuel;power-=c.power;steel-=c.steel;money-=c.money;gold-=c.gold;}
  void add(Resources r){food+=r.food;water+=r.water;fuel+=r.fuel;power+=r.power;steel+=r.steel;money+=r.money;gold+=r.gold;}
}

class Army {
  int soldiers, tanks, artillery, airDefense, aircraft, helicopters, drones, recon, navy;
  Army({this.soldiers=8,this.tanks=2,this.artillery=1,this.airDefense=1,this.aircraft=1,this.helicopters=0,this.drones=1,this.recon=1,this.navy=0});
  double get power => soldiers*1.0+tanks*3.2+artillery*2.7+airDefense*2.2+aircraft*4.5+helicopters*3.5+drones*2.0+recon*1.5+navy*4.0;
  Map<String,dynamic> toJson()=>{'soldiers':soldiers,'tanks':tanks,'artillery':artillery,'airDefense':airDefense,'aircraft':aircraft,'helicopters':helicopters,'drones':drones,'recon':recon,'navy':navy};
  static Army fromJson(Map<String,dynamic> j)=>Army(soldiers:_jsonInt(j['soldiers']),tanks:_jsonInt(j['tanks']),artillery:_jsonInt(j['artillery']),airDefense:_jsonInt(j['airDefense']),aircraft:_jsonInt(j['aircraft']),helicopters:_jsonInt(j['helicopters']),drones:_jsonInt(j['drones']),recon:_jsonInt(j['recon']),navy:_jsonInt(j['navy']));
}


class MajorCity {
  final String name;
  final Offset offset; // relative to country's map anchor
  final bool capital;
  const MajorCity(this.name,this.offset,{this.capital=false});
}


class StrategicSite {
  final String id;
  final String countryId;
  final String name;
  final String kind; // capital, airport, port, factory, power, supply
  final Offset offset;
  double health;
  int level;
  StrategicSite({required this.id,required this.countryId,required this.name,required this.kind,required this.offset,this.health=100,this.level=1});
  bool get operational=>health>=25;
  Map<String,dynamic> toJson()=>{'id':id,'countryId':countryId,'name':name,'kind':kind,'dx':offset.dx,'dy':offset.dy,'health':health,'level':level};
  static StrategicSite fromJson(Map<String,dynamic> j)=>StrategicSite(id:j['id']?.toString()??'',countryId:j['countryId']?.toString()??'',name:j['name']?.toString()??'منشأة',kind:j['kind']?.toString()??'factory',offset:Offset((j['dx']??0).toDouble(),(j['dy']??0).toDouble()),health:_jsonDouble(j['health'],100),level:_jsonInt(j['level'],1));
}

class FieldArmy {
  final String id;
  String name;
  String owner;
  String location;
  int soldiers,tanks,artillery,airDefense,aircraft,helicopters,drones,recon;
  double supply,morale;
  FieldArmy({required this.id,required this.name,required this.owner,required this.location,this.soldiers=3,this.tanks=0,this.artillery=0,this.airDefense=0,this.aircraft=0,this.helicopters=0,this.drones=0,this.recon=0,this.supply=80,this.morale=75});
  double get power=>soldiers+tanks*3.2+artillery*2.7+airDefense*2.2+aircraft*4.5+helicopters*3.5+drones*2.0+recon*1.5;
  Map<String,dynamic> toJson()=>{'id':id,'name':name,'owner':owner,'location':location,'soldiers':soldiers,'tanks':tanks,'artillery':artillery,'airDefense':airDefense,'aircraft':aircraft,'helicopters':helicopters,'drones':drones,'recon':recon,'supply':supply,'morale':morale};
  static FieldArmy fromJson(Map<String,dynamic> j)=>FieldArmy(id:j['id']?.toString()??'',name:j['name']?.toString()??'جيش ميداني',owner:j['owner']?.toString()??'',location:j['location']?.toString()??'',soldiers:_jsonInt(j['soldiers']),tanks:_jsonInt(j['tanks']),artillery:_jsonInt(j['artillery']),airDefense:_jsonInt(j['airDefense']),aircraft:_jsonInt(j['aircraft']),helicopters:_jsonInt(j['helicopters']),drones:_jsonInt(j['drones']),recon:_jsonInt(j['recon']),supply:_jsonDouble(j['supply'],70),morale:_jsonDouble(j['morale'],70));
}

class FrontBattle {
  final String id,source,target,attacker,defender;
  String? targetProvinceId;
  String plan,status;
  double progress,airControl,navalControl;
  int round,startedTurn,lastResolvedTurn;
  bool naval,encircled;
  final List<String> attackerArmyIds,defenderArmyIds;
  final List<Map<String,dynamic>> history;
  FrontBattle({required this.id,required this.source,required this.target,required this.attacker,required this.defender,this.plan='balanced',this.status='active',this.progress=0,this.round=0,this.startedTurn=1,this.lastResolvedTurn=0,this.naval=false,this.encircled=false,this.airControl=0,this.navalControl=0,this.targetProvinceId,List<String>? attackerArmyIds,List<String>? defenderArmyIds,List<Map<String,dynamic>>? history}):attackerArmyIds=attackerArmyIds??<String>[],defenderArmyIds=defenderArmyIds??<String>[],history=history??<Map<String,dynamic>>[];
  bool get active=>status=='active';
  Map<String,dynamic> toJson()=>{'id':id,'source':source,'target':target,'attacker':attacker,'defender':defender,'plan':plan,'status':status,'progress':progress,'round':round,'startedTurn':startedTurn,'lastResolvedTurn':lastResolvedTurn,'naval':naval,'encircled':encircled,'airControl':airControl,'navalControl':navalControl,'targetProvinceId':targetProvinceId,'attackerArmyIds':attackerArmyIds,'defenderArmyIds':defenderArmyIds,'history':history};
  static FrontBattle fromJson(Map<String,dynamic> j)=>FrontBattle(id:j['id']?.toString()??'',source:j['source']?.toString()??'',target:j['target']?.toString()??'',attacker:j['attacker']?.toString()??'',defender:j['defender']?.toString()??'',plan:j['plan']?.toString()??'balanced',status:j['status']?.toString()??'active',progress:_jsonDouble(j['progress']),round:_jsonInt(j['round']),startedTurn:_jsonInt(j['startedTurn'],1),lastResolvedTurn:_jsonInt(j['lastResolvedTurn']),naval:j['naval']==true,encircled:j['encircled']==true,airControl:_jsonDouble(j['airControl']),navalControl:_jsonDouble(j['navalControl']),targetProvinceId:j['targetProvinceId']?.toString(),attackerArmyIds:List<String>.from(j['attackerArmyIds']??const []),defenderArmyIds:List<String>.from(j['defenderArmyIds']??const []),history:(j['history'] is List)?(j['history'] as List).whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).toList():<Map<String,dynamic>>[]);
}

class NavalTaskForce {
  final String id;
  String name,owner,homeCountry,zoneId,mission;
  int surface,carriers,submarines,createdTurn;
  double readiness,supply;
  NavalTaskForce({required this.id,required this.name,required this.owner,required this.homeCountry,required this.zoneId,this.mission='patrol',this.surface=0,this.carriers=0,this.submarines=0,this.createdTurn=1,this.readiness=80,this.supply=85});
  int get units=>surface+carriers+submarines;
  double get power=>(surface*4.2+carriers*11+submarines*7.2)*(.45+readiness.clamp(0.0,100.0).toDouble()/180)*(.5+supply.clamp(0.0,100.0).toDouble()/200);
  Map<String,dynamic> toJson()=>{'id':id,'name':name,'owner':owner,'homeCountry':homeCountry,'zoneId':zoneId,'mission':mission,'surface':surface,'carriers':carriers,'submarines':submarines,'createdTurn':createdTurn,'readiness':readiness,'supply':supply};
  static NavalTaskForce fromJson(Map<String,dynamic> j)=>NavalTaskForce(id:j['id']?.toString()??'',name:j['name']?.toString()??'Task Force',owner:j['owner']?.toString()??'',homeCountry:j['homeCountry']?.toString()??'',zoneId:j['zoneId']?.toString()??'north_atlantic',mission:j['mission']?.toString()??'patrol',surface:_jsonInt(j['surface']),carriers:_jsonInt(j['carriers']),submarines:_jsonInt(j['submarines']),createdTurn:_jsonInt(j['createdTurn'],1),readiness:_jsonDouble(j['readiness'],80),supply:_jsonDouble(j['supply'],85));
}


const Map<String,List<MajorCity>> majorCities={
  'USA':[MajorCity('واشنطن',Offset(0,0),capital:true),MajorCity('نيويورك',Offset(.018,-.018)),MajorCity('شيكاغو',Offset(-.025,-.012)),MajorCity('لوس أنجلوس',Offset(-.045,.018))],
  'FRA':[MajorCity('باريس',Offset(0,0),capital:true),MajorCity('ليون',Offset(.009,.022)),MajorCity('مرسيليا',Offset(.006,.04))],
  'TUR':[MajorCity('أنقرة',Offset(0,0),capital:true),MajorCity('إسطنبول',Offset(-.018,-.012)),MajorCity('إزمير',Offset(-.025,.022))],
  'LBN':[MajorCity('بيروت',Offset(0,0),capital:true),MajorCity('طرابلس',Offset(-.005,-.014)),MajorCity('صيدا',Offset(.003,.014))],
  'DEU':[MajorCity('برلين',Offset(0,0),capital:true),MajorCity('هامبورغ',Offset(-.006,-.018)),MajorCity('ميونخ',Offset(.004,.026))],
  'RUS':[MajorCity('موسكو',Offset(0,0),capital:true),MajorCity('سان بطرسبورغ',Offset(-.018,-.025)),MajorCity('قازان',Offset(.025,.006))],
  'CHN':[MajorCity('بكين',Offset(0,0),capital:true),MajorCity('شنغهاي',Offset(.015,.02)),MajorCity('غوانزو',Offset(.005,.045))],
  'IND':[MajorCity('نيودلهي',Offset(0,0),capital:true),MajorCity('مومباي',Offset(-.018,.025)),MajorCity('كلكتا',Offset(.02,.018))],
  'BRA':[MajorCity('برازيليا',Offset(0,0),capital:true),MajorCity('ساو باولو',Offset(.012,.025)),MajorCity('ريو',Offset(.02,.028))],
  'EGY':[MajorCity('القاهرة',Offset(0,0),capital:true),MajorCity('الإسكندرية',Offset(-.012,-.014))],
};

class Province {
  final String id,countryId,name,nameEn,code;
  String controller,terrain,climate,weather,landCover,physicalDataQuality,transportDataQuality;
  double population,resistance,lat,lng,infrastructure,supply,elevationM,elevationMinM,elevationMaxM,reliefM,areaSqKm,actualRoadKm,actualRailKm,roadDensity,railDensity;
  Map<String,double> landCoverMix,roadClassKm,railClassKm;
  int garrison,fortLevel,trainingCamps,roads,rail,logisticsLevel,elevationSamples,landCoverSamples;
  Province({required this.id,required this.countryId,required this.name,String? nameEn,String? code,required this.controller,this.population=1,this.resistance=0,this.lat=0,this.lng=0,this.infrastructure=60,this.supply=70,this.garrison=0,this.fortLevel=0,this.trainingCamps=0,this.terrain='plains',this.climate='temperate',this.weather='clear',this.roads=1,this.rail=0,this.logisticsLevel=0,this.elevationM=0,this.elevationMinM=0,this.elevationMaxM=0,this.elevationSamples=0,this.reliefM=0,this.landCover='unknown',Map<String,double>? landCoverMix,this.landCoverSamples=0,this.areaSqKm=0,this.actualRoadKm=0,this.actualRailKm=0,this.roadDensity=0,this.railDensity=0,Map<String,double>? roadClassKm,Map<String,double>? railClassKm,this.physicalDataQuality='fallback',this.transportDataQuality='fallback'}):nameEn=nameEn??name,code=code??id,landCoverMix=landCoverMix??{},roadClassKm=roadClassKm??{},railClassKm=railClassKm??{};
  double get defensePower=>garrison*(1+fortLevel*.22)*(0.72+infrastructure/180)*(0.7+supply/230)*(.85+(_terrainProfile(terrain)['defense']??1)*.15)*(.88+(_landCoverProfile(landCover)['defense']??1)*.12)*(_elevationProfile(this)['defense']??1);
  double get logisticsCapacity=>_provinceInfrastructureCapacity(this);
  bool get hasRealPhysicalData=>physicalDataQuality.startsWith('real')||physicalDataQuality=='partial';
  bool get hasRealRoadData=>transportDataQuality.startsWith('overture')||transportDataQuality.startsWith('real');
  Map<String,dynamic> toJson()=>{'id':id,'countryId':countryId,'name':name,'nameEn':nameEn,'code':code,'controller':controller,'population':population,'resistance':resistance,'lat':lat,'lng':lng,'infrastructure':infrastructure,'supply':supply,'garrison':garrison,'fortLevel':fortLevel,'trainingCamps':trainingCamps,'terrain':terrain,'climate':climate,'weather':weather,'roads':roads,'rail':rail,'logisticsLevel':logisticsLevel,'elevationM':elevationM,'elevationMinM':elevationMinM,'elevationMaxM':elevationMaxM,'elevationSamples':elevationSamples,'reliefM':reliefM,'landCover':landCover,'landCoverMix':landCoverMix,'landCoverSamples':landCoverSamples,'areaSqKm':areaSqKm,'actualRoadKm':actualRoadKm,'actualRailKm':actualRailKm,'roadDensity':roadDensity,'railDensity':railDensity,'roadClassKm':roadClassKm,'railClassKm':railClassKm,'physicalDataQuality':physicalDataQuality,'transportDataQuality':transportDataQuality};
  static Province fromJson(Map<String,dynamic> j){Map<String,double> numMap(dynamic raw){final out=<String,double>{};if(raw is Map){for(final e in raw.entries){if(e.value is num)out[e.key.toString()]=(e.value as num).toDouble();}}return out;}return Province(id:j['id']?.toString()??'',countryId:j['countryId']?.toString()??'',name:j['name']?.toString()??'',nameEn:j['nameEn']?.toString(),code:j['code']?.toString(),controller:j['controller']?.toString()??'',population:(j['population']??1).toDouble(),resistance:(j['resistance']??0).toDouble(),lat:(j['lat']??0).toDouble(),lng:(j['lng']??0).toDouble(),infrastructure:(j['infrastructure']??60).toDouble(),supply:(j['supply']??70).toDouble(),garrison:_jsonInt(j['garrison'],0),fortLevel:_jsonInt(j['fortLevel'],0),trainingCamps:_jsonInt(j['trainingCamps'],0),terrain:j['terrain']?.toString()??'plains',climate:j['climate']?.toString()??'temperate',weather:j['weather']?.toString()??'clear',roads:_jsonInt(j['roads'],1),rail:_jsonInt(j['rail'],0),logisticsLevel:_jsonInt(j['logisticsLevel'],0),elevationM:(j['elevationM']??0).toDouble(),elevationMinM:(j['elevationMinM']??j['elevationM']??0).toDouble(),elevationMaxM:(j['elevationMaxM']??j['elevationM']??0).toDouble(),elevationSamples:_jsonInt(j['elevationSamples'],0),reliefM:(j['reliefM']??0).toDouble(),landCover:j['landCover']?.toString()??'unknown',landCoverMix:numMap(j['landCoverMix']),landCoverSamples:_jsonInt(j['landCoverSamples'],0),areaSqKm:(j['areaSqKm']??0).toDouble(),actualRoadKm:(j['actualRoadKm']??0).toDouble(),actualRailKm:(j['actualRailKm']??0).toDouble(),roadDensity:(j['roadDensity']??0).toDouble(),railDensity:(j['railDensity']??0).toDouble(),roadClassKm:numMap(j['roadClassKm']),railClassKm:numMap(j['railClassKm']),physicalDataQuality:j['physicalDataQuality']?.toString()??'fallback',transportDataQuality:j['transportDataQuality']?.toString()??'fallback');}
}

class ProvinceShape {
  final String countryId,code,name,nameEn;
  final double lat,lng;
  final List<List<Offset>> rings;
  ProvinceShape({required this.countryId,required this.code,required this.name,required this.nameEn,required this.lat,required this.lng,required this.rings});
  static ProvinceShape fromJson(String countryId,Map<String,dynamic> j){
    final rings=<List<Offset>>[];
    for(final rawRing in (j['rings'] is List?j['rings'] as List:const [])){if(rawRing is! List)continue;final pts=<Offset>[];for(final raw in rawRing){if(raw is List&&raw.length>=2&&raw[0] is num&&raw[1] is num)pts.add(Offset((raw[0] as num).toDouble(),(raw[1] as num).toDouble()));}if(pts.length>=3)rings.add(pts);}
    return ProvinceShape(countryId:countryId,code:j['code']?.toString()??'',name:j['nameAr']?.toString()??j['nameEn']?.toString()??'',nameEn:j['nameEn']?.toString()??j['nameAr']?.toString()??'',lat:(j['lat']??0).toDouble(),lng:(j['lng']??0).toDouble(),rings:rings);
  }
}

class TransportLine {
  final String countryId,kind,roadClass,provinceCode;
  final List<Offset> points;
  TransportLine({required this.countryId,required this.kind,required this.roadClass,required this.provinceCode,required this.points});
  static TransportLine? fromJson(String countryId,Map<String,dynamic> j){final pts=<Offset>[];for(final raw in (j['points'] is List?j['points'] as List:const [])){if(raw is List&&raw.length>=2&&raw[0] is num&&raw[1] is num)pts.add(Offset((raw[0] as num).toDouble(),(raw[1] as num).toDouble()));}if(pts.length<2)return null;return TransportLine(countryId:countryId,kind:j['kind']?.toString()??'road',roadClass:j['class']?.toString()??'',provinceCode:j['provinceCode']?.toString()??'',points:pts);}
}

class Country {
  final String id, name;
  final String capital;
  final Offset pos;
  final List<String> neighbors;
  String controller;
  double population;
  double stability;
  double approval;
  Resources stock;
  Resources production;
  Army army;
  int solar, nuclear, grid, farms, foodFactories, civilianIndustry, militaryIndustry;
  int airBases, navalBases, supplyHubs, trainingCamps, borderDefense, recruitedThisTurn;
  double supply, morale, intelligence, resistance, warExhaustion;
  int commandPoints,techAgriculture,techIndustry,techLogistics,techArmor,techAir,techIntel,missileStock,cruiseMissiles,ballisticMissiles,hypersonicMissiles,missileDefense,missileProgram,electronicWarfare,satelliteRecon,radarLevel,earlyWarning,carrierStock,submarineStock;
  double airReadiness,fleetReadiness;
  String occupationPolicy;
  Country({required this.id,required this.name,this.capital='العاصمة',required this.pos,required this.neighbors,required this.controller,required this.population,required this.stock,required this.production,required this.army,this.stability=72,this.approval=64,this.solar=0,this.nuclear=0,this.grid=1,this.farms=1,this.foodFactories=1,this.civilianIndustry=1,this.militaryIndustry=1,this.airBases=0,this.navalBases=0,this.supplyHubs=1,this.trainingCamps=0,this.borderDefense=0,this.recruitedThisTurn=0,this.supply=72,this.morale=70,this.intelligence=20,this.resistance=0,this.warExhaustion=0,this.commandPoints=6,this.occupationPolicy='balanced',this.techAgriculture=0,this.techIndustry=0,this.techLogistics=0,this.techArmor=0,this.techAir=0,this.techIntel=0,this.missileStock=0,this.cruiseMissiles=0,this.ballisticMissiles=0,this.hypersonicMissiles=0,this.missileDefense=0,this.missileProgram=0,this.electronicWarfare=0,this.satelliteRecon=0,this.radarLevel=0,this.earlyWarning=0,this.carrierStock=0,this.submarineStock=0,this.airReadiness=70,this.fleetReadiness=70});
  Map<String,dynamic> toJson()=>{'id':id,'controller':controller,'population':population,'stability':stability,'approval':approval,'stock':stock.toJson(),'production':production.toJson(),'army':army.toJson(),'solar':solar,'nuclear':nuclear,'grid':grid,'farms':farms,'foodFactories':foodFactories,'civilianIndustry':civilianIndustry,'militaryIndustry':militaryIndustry,'airBases':airBases,'navalBases':navalBases,'supplyHubs':supplyHubs,'trainingCamps':trainingCamps,'borderDefense':borderDefense,'recruitedThisTurn':recruitedThisTurn,'supply':supply,'morale':morale,'intelligence':intelligence,'resistance':resistance,'warExhaustion':warExhaustion,'commandPoints':commandPoints,'occupationPolicy':occupationPolicy,'techAgriculture':techAgriculture,'techIndustry':techIndustry,'techLogistics':techLogistics,'techArmor':techArmor,'techAir':techAir,'techIntel':techIntel,'missileStock':missileStock,'cruiseMissiles':cruiseMissiles,'ballisticMissiles':ballisticMissiles,'hypersonicMissiles':hypersonicMissiles,'missileDefense':missileDefense,'missileProgram':missileProgram,'electronicWarfare':electronicWarfare,'satelliteRecon':satelliteRecon,'radarLevel':radarLevel,'earlyWarning':earlyWarning,'carrierStock':carrierStock,'submarineStock':submarineStock,'airReadiness':airReadiness,'fleetReadiness':fleetReadiness};
  void applyJson(Map<String,dynamic> j){controller=j['controller']??controller;population=(j['population']??population).toDouble();stability=(j['stability']??stability).toDouble();approval=(j['approval']??approval).toDouble();stock=Resources.fromJson(Map<String,dynamic>.from(j['stock']??{}));production=Resources.fromJson(Map<String,dynamic>.from(j['production']??production.toJson()));army=Army.fromJson(Map<String,dynamic>.from(j['army']??{}));solar=_jsonInt(j['solar'],solar);nuclear=_jsonInt(j['nuclear'],nuclear);grid=_jsonInt(j['grid'],grid);farms=_jsonInt(j['farms'],farms);foodFactories=_jsonInt(j['foodFactories'],foodFactories);civilianIndustry=_jsonInt(j['civilianIndustry'],civilianIndustry);militaryIndustry=_jsonInt(j['militaryIndustry'],militaryIndustry);airBases=_jsonInt(j['airBases'],airBases);navalBases=_jsonInt(j['navalBases'],navalBases);supplyHubs=_jsonInt(j['supplyHubs'],supplyHubs);trainingCamps=_jsonInt(j['trainingCamps'],trainingCamps);borderDefense=_jsonInt(j['borderDefense'],borderDefense);recruitedThisTurn=_jsonInt(j['recruitedThisTurn'],recruitedThisTurn);supply=(j['supply']??supply).toDouble();morale=(j['morale']??morale).toDouble();intelligence=(j['intelligence']??intelligence).toDouble();resistance=(j['resistance']??resistance).toDouble();warExhaustion=(j['warExhaustion']??warExhaustion).toDouble();commandPoints=_jsonInt(j['commandPoints'],commandPoints);occupationPolicy=j['occupationPolicy']?.toString()??occupationPolicy;techAgriculture=_jsonInt(j['techAgriculture'],techAgriculture);techIndustry=_jsonInt(j['techIndustry'],techIndustry);techLogistics=_jsonInt(j['techLogistics'],techLogistics);techArmor=_jsonInt(j['techArmor'],techArmor);techAir=_jsonInt(j['techAir'],techAir);techIntel=_jsonInt(j['techIntel'],techIntel);missileStock=_jsonInt(j['missileStock'],missileStock);final typedPresent=j.containsKey('cruiseMissiles')||j.containsKey('ballisticMissiles')||j.containsKey('hypersonicMissiles');cruiseMissiles=_jsonInt(j['cruiseMissiles'],typedPresent?cruiseMissiles:missileStock);ballisticMissiles=_jsonInt(j['ballisticMissiles'],ballisticMissiles);hypersonicMissiles=_jsonInt(j['hypersonicMissiles'],hypersonicMissiles);missileStock=cruiseMissiles+ballisticMissiles+hypersonicMissiles;missileDefense=_jsonInt(j['missileDefense'],missileDefense);missileProgram=_jsonInt(j['missileProgram'],missileProgram);electronicWarfare=_jsonInt(j['electronicWarfare'],electronicWarfare);satelliteRecon=_jsonInt(j['satelliteRecon'],satelliteRecon);radarLevel=_jsonInt(j['radarLevel'],radarLevel);earlyWarning=_jsonInt(j['earlyWarning'],earlyWarning);carrierStock=_jsonInt(j['carrierStock'],carrierStock);submarineStock=_jsonInt(j['submarineStock'],submarineStock);airReadiness=(j['airReadiness']??airReadiness).toDouble();fleetReadiness=(j['fleetReadiness']??fleetReadiness).toDouble();}
}

class GameState extends ChangeNotifier {
  final Random rng=Random();
  late Map<String,Country> countries;
  String? humanCountry;
  String selected='FRA';
  int turn=1;
  final List<String> logs=[];
  final Set<String> alliances={};
  final Set<String> sanctions={};
  final List<String> tradeDeals=[];
  final List<Map<String,dynamic>> diplomaticOffers=[];
  final List<Map<String,dynamic>> events=[];
  String president='رئيس الدولة';
  String defenseMinister='وزير الدفاع';
  String economyMinister='وزير الاقتصاد';
  String foreignMinister='وزير الخارجية';
  MultiplayerClient? multiplayer;
  final Map<String,String> onlineCountryOwners={};
  final List<Map<String,dynamic>> onlinePlayers=[];
  final List<FieldArmy> fieldArmies=[];
  final List<NavalTaskForce> navalTaskForces=[];
  final List<FrontBattle> battles=[];
  final List<Province> provinces=[];
  final Map<String,List<ProvinceShape>> provinceShapesByCountry={};
  final Map<String,List<TransportLine>> transportLinesByCountry={};
  Map<String,dynamic> geodataManifest={};
  String? selectedProvinceId;
  final Map<String,String> alpha3To2={...kAlpha3To2};
  final Map<String,String> countryNamesEn={};
  final Map<String,String> alpha2To3={...kAlpha2To3};
  final Set<String> coastalCountries={'ARE','ARG','AUS','BGD','BRA','CAN','CHN','DZA','EGY','ESP','FRA','GBR','GEO','IDN','IND','IRN','ISR','ITA','JPN','KOR','LBN','MAR','MEX','MMR','MYS','OMN','PAK','PRK','SAU','SYR','THA','TUR','USA','YEM'};
  final List<StrategicSite> strategicSites=[];
  String? selectedSiteId;
  String? winnerController;
  String? victoryType;
  String aiDifficulty='normal';
  String battleMode='manual';
  String appLanguage='ar';
  String gamePace='campaign';
  bool worldDataLoaded=false;

  GameState(){countries=_seedCountries();strategicSites.addAll(_seedStrategicSites(countries));_seedFallbackProvinces();logs.add('اختر دولتك وابدأ بناء قوتك.');}
  Country get me {if(humanCountry==null)return countries.values.first;final original=countries[humanCountry]!;if(original.controller=='P:$humanCountry')return original;for(final c in countries.values){if(c.controller=='P:$humanCountry')return c;}return original;}
  Country get selectedCountry=>countries[selected]!;
  Province? bestRouteProvince(String countryId){final rows=provinces.where((p)=>p.countryId==countryId&&p.controller==me.controller).toList();if(rows.isEmpty)return null;rows.sort((a,b)=>b.logisticsCapacity.compareTo(a.logisticsCapacity));return rows.first;}
  Map<String,num> movementCostBetween(String fromId,String toId){final from=countries[fromId],to=countries[toId],fp=bestRouteProvince(fromId),tp=bestRouteProvince(toId);if(from==null||to==null)return const {'fuelCost':2,'supplyLoss':5,'distanceKm':0};final distance=(fp!=null&&tp!=null)?_haversineKm(fp.lat,fp.lng,tp.lat,tp.lng):_haversineKm(90-from.pos.dy*180,from.pos.dx*360-180,90-to.pos.dy*180,to.pos.dx*360-180);return _movementCostProfile(fp,tp,distance);}
  bool get eliminated=>humanCountry!=null&&!countries.values.any((c)=>c.controller=='P:$humanCountry');
  String? get winnerName {final w=winnerController;if(w==null)return null;final id=controllerRoot(w);return countries[id]?.name??id;}
  StrategicSite? get selectedSite { if(selectedSiteId==null)return null; for(final s in strategicSites){if(s.id==selectedSiteId)return s;} return null; }
  List<StrategicSite> sitesForCountry(String id)=>strategicSites.where((s)=>s.countryId==id).toList();
  double siteFactor(String id,String kind){final xs=strategicSites.where((s)=>s.countryId==id&&s.kind==kind).toList();if(xs.isEmpty)return 1;return xs.map((s)=>s.health/100).reduce((a,b)=>a+b)/xs.length;}
  double infrastructureIntegrity(String id){final xs=sitesForCountry(id);if(xs.isEmpty)return 100;return xs.map((s)=>s.health).reduce((a,b)=>a+b)/xs.length;}
  void selectSite(String? id){selectedSiteId=id;if(id!=null){for(final s in strategicSites){if(s.id==id){selected=s.countryId;break;}}}notifyListeners();}
  String controllerRoot(String controller)=>controller.replaceFirst(RegExp(r'^(P:|AI:)'),'');
  String _allianceKey(String a,String b){final xs=[a,b]..sort();return xs.join('|');}
  bool areAllies(String a,String b){final ca=countries[a],cb=countries[b];final ra=ca==null?a:controllerRoot(ca.controller),rb=cb==null?b:controllerRoot(cb.controller);return ra!=rb&&alliances.contains(_allianceKey(ra,rb));}
  bool isOccupied(Country c)=>(c.controller.startsWith('P:')||c.controller.startsWith('AI:'))&&controllerRoot(c.controller)!=c.id;
  String tr(String ar,String en)=>appLanguage=='en'?en:ar;
  String countryDisplayName(Country c)=>appLanguage=='en'?(countryNamesEn[c.id]??c.id):c.name;
  void setLanguage(String value){if(value!='ar'&&value!='en')return;appLanguage=value;notifyListeners();}
  void setBattleMode(String value){if(value!='manual'&&value!='auto')return;battleMode=value;notifyListeners();}
  void setGamePace(String value){if(!{'rapid','campaign','grand'}.contains(value))return;gamePace=value;notifyListeners();}
  String get gamePaceLabel=>gamePace=='rapid'?tr('سريعة','Rapid'):gamePace=='grand'?tr('حرب طويلة','Grand War'):tr('حملة','Campaign');
  int get hegemonyStartTurn=>gamePace=='rapid'?15:gamePace=='grand'?40:25;
  int get recommendedTurnMinutes=>gamePace=='rapid'?5:gamePace=='grand'?720:60;
  List<Province> provincesFor(String countryId)=>provinces.where((p)=>p.countryId==countryId).toList();
  Province? provinceById(String? id){if(id==null)return null;for(final p in provinces){if(p.id==id)return p;}return null;}
  List<Province> enemyProvinces(String countryId)=>provincesFor(countryId).where((p)=>p.controller!=me.controller).toList();
  int get recruitCapacity=>max(3,min(80,(me.population/12).round()+me.trainingCamps*6));
  int get recruitRemaining=>max(0,recruitCapacity-me.recruitedThisTurn);
  String seaZoneName(String id)=>tr((kSeaZones[id]?['ar']??id).toString(),(kSeaZones[id]?['en']??id).toString());
  List<String> seaZonesForCountry(String countryId){final c=countries[countryId];if(c==null||!coastalCountries.contains(countryId))return const [];final fixed=kMultiCoastZones[countryId];if(fixed!=null)return List<String>.from(fixed);final lat=90-c.pos.dy*180,lng=c.pos.dx*360-180;final xs=kSeaZones.entries.map((e)=>MapEntry(e.key,_haversineKm(lat,lng,(e.value['lat'] as num).toDouble(),(e.value['lng'] as num).toDouble()))).toList()..sort((a,b)=>a.value.compareTo(b.value));return xs.isEmpty?const []:[xs.first.key];}
  List<String> adjacentSeaZones(String zoneId)=>List<String>.from(kSeaZones[zoneId]?['adj']??const []);
  List<NavalTaskForce> get myTaskForces=>navalTaskForces.where((x)=>x.owner==me.controller).toList();
  List<NavalTaskForce> taskForcesInZone(String zoneId)=>navalTaskForces.where((x)=>x.zoneId==zoneId).toList();
  int missileCount(String type)=>type=='ballistic'?me.ballisticMissiles:type=='hypersonic'?me.hypersonicMissiles:me.cruiseMissiles;
  double typedMissileRangeKm(Country c,String type){final s=kMissileTypes[type]??kMissileTypes['cruise']!;return (s['baseRange'] as num).toDouble()+c.missileProgram*(s['programRange'] as num).toDouble()+c.techAir*180;}
  bool canTypedMissileReach(String targetId,String type){if(humanCountry==null)return false;final t=countries[targetId];if(t==null)return false;return countries.values.where((x)=>x.controller==me.controller).any((x)=>_haversineKm(90-x.pos.dy*180,x.pos.dx*360-180,90-t.pos.dy*180,t.pos.dx*360-180)<=typedMissileRangeKm(me,type));}
  bool _fleetCanResupply(NavalTaskForce tf){for(final c in countries.values){if(c.controller!=tf.owner)continue;if(seaZonesForCountry(c.id).contains(tf.zoneId)&&siteFactor(c.id,'port')>.25)return true;}return false;}
  void navalBuild(String kind){if(multiplayer?.isConnected==true){multiplayer!.sendGameAction('navalBuild',value:kind);return;}final c=me;final cost=kind=='carrier'?Resources(fuel:10,power:7,steel:28,money:42):Resources(fuel:6,power:5,steel:18,money:28);if(!c.stock.canPay(cost))return _noRes();if(!_spendCommand(1))return;c.stock.pay(cost);if(kind=='carrier')c.carrierStock++;else c.submarineStock++;_log(kind=='carrier'?tr('تم تدشين حاملة طائرات.','Aircraft carrier commissioned.'):tr('تم تدشين غواصة.','Submarine commissioned.'));_sync();notifyListeners();}
  void deployTaskForce(String sourceId,String zoneId,{int surface=1,int carriers=0,int submarines=0}){final source=countries[sourceId];if(source==null||source.controller!=me.controller||!seaZonesForCountry(sourceId).contains(zoneId)||surface+carriers+submarines<1)return;if(multiplayer?.isConnected==true){multiplayer!.sendGameAction('navalDeploy',value:'$zoneId|$surface|$carriers|$submarines',target:sourceId);return;}if(me.army.navy<surface||me.carrierStock<carriers||me.submarineStock<submarines)return _noRes();final fuel=4+surface+carriers*2+submarines;if(me.stock.fuel<fuel)return _noRes();if(!_spendCommand(1))return;me.stock.fuel-=fuel;me.army.navy-=surface;me.carrierStock-=carriers;me.submarineStock-=submarines;navalTaskForces.add(NavalTaskForce(id:'TF${DateTime.now().millisecondsSinceEpoch}${rng.nextInt(999)}',name:'Task Force ${navalTaskForces.length+1}',owner:me.controller,homeCountry:sourceId,zoneId:zoneId,surface:surface,carriers:carriers,submarines:submarines,createdTurn:turn,readiness:88,supply:90));_log('${tr('انتشرت قوة بحرية في','Task force deployed to')} ${seaZoneName(zoneId)}.');_sync();notifyListeners();}
  void moveTaskForce(String id,String zoneId){NavalTaskForce? tf;for(final x in navalTaskForces){if(x.id==id){tf=x;break;}}if(tf==null||tf.owner!=me.controller||!adjacentSeaZones(tf.zoneId).contains(zoneId))return;if(multiplayer?.isConnected==true){multiplayer!.sendGameAction('navalMove',value:id,target:zoneId);return;}final fuel=max(3,tf.units*2).toDouble();if(me.stock.fuel<fuel)return _noRes();if(!_spendCommand(1))return;me.stock.fuel-=fuel;tf.zoneId=zoneId;tf.supply=max(0.0,tf.supply-8);tf.readiness=max(0.0,tf.readiness-5);_log('${tf.name} → ${seaZoneName(zoneId)}.');_sync();notifyListeners();}
  void setTaskForceMission(String id,String mission){NavalTaskForce? tf;for(final x in navalTaskForces){if(x.id==id){tf=x;break;}}if(tf==null||tf.owner!=me.controller)return;if(multiplayer?.isConnected==true){multiplayer!.sendGameAction('navalMission',value:'$id|$mission');return;}if(!_spendCommand(1))return;tf.mission=mission;if(mission=='sea_control')tf.readiness=min(100.0,tf.readiness+8);_log('${tf.name}: $mission.');_sync();notifyListeners();}
  void engageTaskForce(String ownId,String enemyId){NavalTaskForce? a,d;for(final x in navalTaskForces){if(x.id==ownId)a=x;if(x.id==enemyId)d=x;}if(a==null||d==null||a.owner!=me.controller||d.owner==me.controller||a.zoneId!=d.zoneId)return;if(multiplayer?.isConnected==true){multiplayer!.sendGameAction('navalEngage',value:ownId,target:enemyId);return;}if(!_spendCommand(2))return;final edge=((a.power-d.power)/max(1,a.power+d.power)+(rng.nextDouble()*2-1)*.12).clamp(-1.0,1.0).toDouble(),aLoss=(.08-edge*.12).clamp(.025,.24).toDouble(),dLoss=(.08+edge*.12).clamp(.025,.24).toDouble();int loss(int n,double sev,double bias)=>min(n,(n*sev+bias).floor()).toInt();a.surface-=loss(a.surface,aLoss,.35);a.carriers-=loss(a.carriers,aLoss*.55,.08);a.submarines-=loss(a.submarines,aLoss*.75,.16);d.surface-=loss(d.surface,dLoss,.35);d.carriers-=loss(d.carriers,dLoss*.55,.08);d.submarines-=loss(d.submarines,dLoss*.75,.16);a.readiness=max(0.0,a.readiness-8);d.readiness=max(0.0,d.readiness-9);a.supply=max(0.0,a.supply-7);d.supply=max(0.0,d.supply-8);navalTaskForces.removeWhere((x)=>x.units<=0);_log('${tr('اشتباك بحري في','Naval engagement in')} ${seaZoneName(a.zoneId)}: ${edge>=0?tr('تفوق لقواتك','advantage to your fleet'):tr('تفوق للخصم','enemy advantage')}.');_sync();notifyListeners();}
  void _seedFallbackProvinces(){
    const special=<String,List<String>>{
      'USA':['California','Texas','New York','Florida','Pennsylvania'],'FRA':['Île-de-France','Auvergne-Rhône-Alpes','Nouvelle-Aquitaine','Occitanie','Provence-Alpes-Côte d’Azur'],'TUR':['İstanbul','Ankara','İzmir','Bursa','Antalya','Gaziantep'],'LBN':['بيروت','جبل لبنان','الشمال','عكار','البقاع','بعلبك الهرمل','الجنوب','النبطية'],'DEU':['Bavaria','Berlin','Hesse','Saxony','North Rhine-Westphalia'],'GBR':['England','Scotland','Wales','Northern Ireland']};
    for(final c in countries.values){final names=special[c.id]??<String>[c.capital];for(var i=0;i<names.length;i++){provinces.add(Province(id:'${c.id}_P$i',countryId:c.id,name:names[i],code:'${c.id}-P$i',controller:c.controller,population:max(.1,c.population/names.length),lat:90-c.pos.dy*180,lng:c.pos.dx*360-180,infrastructure:i==0?78:58,supply:i==0?78:68,garrison:i==0?max(1,(c.army.soldiers/4).round()):0,roads:i==0?2:1,rail:i==0?1:0,logisticsLevel:i==0?1:0));}}
  }
  Future<void> initializeWorldData()async{
    if(worldDataLoaded)return;
    try{
      final raw=await rootBundle.loadString('assets/world_game_data.json'),data=jsonDecode(raw);if(data is! List)return;provinces.clear();
      for(final item in data.whereType<Map>()){
        final j=Map<String,dynamic>.from(item),id=(j['iso3']??'').toString().toUpperCase();if(id.length!=3)continue;
        final iso2=(j['iso2']??'').toString().toUpperCase(),pop=((j['population']??10) as num).toDouble()/1000000.0,lat=((j['lat']??0) as num).toDouble(),lng=((j['lng']??0) as num).toDouble(),borders=List<String>.from(j['borders']??const []);
        if(!countries.containsKey(id)){countries[id]=Country(id:id,name:(j['nameAr']??j['nameEn']??id).toString(),capital:(j['capital']??'العاصمة').toString(),pos:Offset(((lng+180)/360).clamp(0,1).toDouble(),((90-lat)/180).clamp(0,1).toDouble()),neighbors:borders.where((x)=>x.length==3).toList(),controller:'AI:$id',population:max(.1,pop),stock:Resources(food:95,water:95,fuel:70,power:80,steel:60,money:90,gold:28),production:Resources(food:10,water:9,fuel:5,power:7,steel:5,money:8,gold:2),army:Army(soldiers:(6+min(30,(sqrt(max(1,pop))*1.15).round())).toInt(),navy:j['landlocked']==true?0:1));}
        alpha3To2[id]=iso2;countryNamesEn[id]=(j['nameEn']??id).toString();alpha2To3[iso2]=id;final c=countries[id]!;if(j['landlocked']!=true)coastalCountries.add(id);
        final rawRegions=(j['regions'] is List)?j['regions'] as List:const [];final regionRows=<Map<String,dynamic>>[];
        for(final r in rawRegions){if(r is Map){regionRows.add(Map<String,dynamic>.from(r));}else{final n=r.toString().trim();if(n.isNotEmpty)regionRows.add({'nameEn':n,'nameAr':n});}}
        if(regionRows.isEmpty)regionRows.add({'nameEn':c.capital,'nameAr':c.capital,'code':'$id-CAP','lat':lat,'lng':lng});
        final weightTotal=regionRows.length+1.2;
        for(var i=0;i<regionRows.length;i++){final r=regionRows[i],en=(r['nameEn']??r['nameAr']??'Region ${i+1}').toString(),ar=(r['nameAr']??en).toString(),rcode=(r['code']??'$id-P$i').toString(),rlat=(r['lat'] is num?(r['lat'] as num).toDouble():lat),rlng=(r['lng'] is num?(r['lng'] as num).toDouble():lng),isCapital=en.toLowerCase().contains(c.capital.toLowerCase())||ar.contains(c.capital),infra=(isCapital?82.0:58.0)+(pop>80?5:0),provPop=max(.03,pop*((isCapital?2.2:1)/weightTotal));provinces.add(Province(id:'${id}_P$i',countryId:id,name:ar,nameEn:en,code:rcode,controller:c.controller,population:provPop,lat:rlat,lng:rlng,infrastructure:infra.clamp(35,92).toDouble(),supply:isCapital?82:70,garrison:i==0?max(1,(c.army.soldiers/5).round()):0,terrain:(r['terrain']??'plains').toString(),climate:(r['climate']??'temperate').toString(),weather:'clear',roads:isCapital?2:1,rail:isCapital?1:0,logisticsLevel:isCapital?1:0,elevationM:(r['elevationM']??0).toDouble(),elevationMinM:(r['elevationMinM']??r['elevationM']??0).toDouble(),elevationMaxM:(r['elevationMaxM']??r['elevationM']??0).toDouble(),elevationSamples:r['elevationSamples']??0,reliefM:(r['reliefM']??0).toDouble(),landCover:(r['landCover']??'unknown').toString(),landCoverMix:{for(final e in ((r['landCoverMix'] is Map)?(r['landCoverMix'] as Map):const {}).entries)if(e.value is num)e.key.toString():(e.value as num).toDouble()},landCoverSamples:r['landCoverSamples']??0,areaSqKm:(r['areaSqKm']??0).toDouble(),actualRoadKm:(r['actualRoadKm']??0).toDouble(),actualRailKm:(r['actualRailKm']??0).toDouble(),roadDensity:(r['roadDensity']??0).toDouble(),railDensity:(r['railDensity']??0).toDouble(),roadClassKm:{for(final e in ((r['roadClassKm'] is Map)?(r['roadClassKm'] as Map):const {}).entries)if(e.value is num)e.key.toString():(e.value as num).toDouble()},railClassKm:{for(final e in ((r['railClassKm'] is Map)?(r['railClassKm'] as Map):const {}).entries)if(e.value is num)e.key.toString():(e.value as num).toDouble()},physicalDataQuality:(r['physicalDataQuality']??'fallback').toString(),transportDataQuality:(r['transportDataQuality']??'fallback').toString()));}
      }
      strategicSites.removeWhere((s)=>!countries.containsKey(s.countryId));for(final c in countries.values){if(!strategicSites.any((s)=>s.countryId==c.id)){strategicSites.add(StrategicSite(id:'${c.id}_CAP',countryId:c.id,name:c.capital,kind:'capital',offset:Offset.zero));strategicSites.add(StrategicSite(id:'${c.id}_SUP',countryId:c.id,name:tr('مركز الإمداد','Supply hub'),kind:'supply',offset:const Offset(.012,-.014)));if(coastalCountries.contains(c.id))strategicSites.add(StrategicSite(id:'${c.id}_PRT',countryId:c.id,name:tr('الميناء الرئيسي','Main port'),kind:'port',offset:const Offset(.020,.002)));}}
      await _loadProvinceGeometry();await _loadPhysicalGeodata();worldDataLoaded=true;_log(tr('تم تحميل عالم المحافظات: ${countries.length} دولة و${provinces.length} محافظة/ولاية.','World loaded: ${countries.length} countries and ${provinces.length} provinces/states.'));notifyListeners();
    }catch(e){worldDataLoaded=true;_log(tr('تعذر تحميل بيانات العالم الموسعة؛ تم استخدام البيانات الاحتياطية.','Extended world data failed to load; fallback data is active.'));notifyListeners();}
  }
  Future<void> _loadProvinceGeometry()async{
    provinceShapesByCountry.clear();
    try{final raw=await rootBundle.loadString('assets/province_map.json'),data=jsonDecode(raw);if(data is! Map)return;final cs=data['countries'];if(cs is! Map)return;for(final e in cs.entries){final id=e.key.toString().toUpperCase();final list=<ProvinceShape>[];if(e.value is List){for(final r in e.value as List){if(r is Map){final shape=ProvinceShape.fromJson(id,Map<String,dynamic>.from(r));if(shape.rings.isNotEmpty)list.add(shape);}}}if(list.isNotEmpty)provinceShapesByCountry[id]=list;}
    }catch(_){provinceShapesByCountry.clear();}
  }
  Future<void> _loadPhysicalGeodata()async{
    transportLinesByCountry.clear();geodataManifest={};
    try{final raw=await rootBundle.loadString('assets/transport_map.json'),data=jsonDecode(raw);if(data is Map&&data['countries'] is Map){for(final e in (data['countries'] as Map).entries){final id=e.key.toString().toUpperCase(),list=<TransportLine>[];if(e.value is List){for(final r in e.value as List){if(r is Map){final line=TransportLine.fromJson(id,Map<String,dynamic>.from(r));if(line!=null)list.add(line);}}}if(list.isNotEmpty)transportLinesByCountry[id]=list;}}}catch(_){transportLinesByCountry.clear();}
    try{final raw=await rootBundle.loadString('assets/geodata_manifest.json'),data=jsonDecode(raw);if(data is Map)geodataManifest=Map<String,dynamic>.from(data);}catch(_){geodataManifest={};}
  }
  String landCoverLabel(String value)=>switch(value){'tree_cover'=>tr('غطاء شجري','Tree cover'),'shrubland'=>tr('شجيرات','Shrubland'),'grassland'=>tr('مراعٍ/أعشاب','Grassland'),'cropland'=>tr('أراضٍ زراعية','Cropland'),'built_up'=>tr('عمران','Built-up'),'bare_sparse'=>tr('أرض جرداء','Bare/sparse'),'snow_ice'=>tr('ثلج/جليد','Snow/ice'),'water'=>tr('مياه','Water'),'wetland'=>tr('أراضٍ رطبة','Wetland'),'mangroves'=>tr('مانغروف','Mangroves'),'moss_lichen'=>tr('طحالب/أشنات','Moss/lichen'),_=>tr('غير محدد','Unknown')};
  Province? provinceForShape(ProvinceShape shape){final xs=provincesFor(shape.countryId);for(final p in xs){if(p.code.isNotEmpty&&shape.code.isNotEmpty&&p.code==shape.code)return p;}String norm(String x)=>x.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\u0600-\u06ff]+'),'');final n=norm(shape.nameEn);for(final p in xs){if(norm(p.nameEn)==n||norm(p.name)==norm(shape.name))return p;}return null;}
  void selectProvince(String? id){selectedProvinceId=id;final p=provinceById(id);if(p!=null)selected=p.countryId;notifyListeners();}
  void buildTrainingCamp(){if(multiplayer?.isConnected==true){multiplayer!.sendGameAction('buildTrainingCamp');return;}final cost=Resources(steel:8,money:12,gold:4);if(!me.stock.canPay(cost))return _noRes();me.stock.pay(cost);me.trainingCamps++;_log('تم بناء معسكر تدريب. سعة التجنيد أصبحت $recruitCapacity وحدة مشاة/دور.');_sync();notifyListeners();}
  void buildBorderDefense(){if(multiplayer?.isConnected==true){multiplayer!.sendGameAction('buildBorderDefense');return;}final cost=Resources(steel:10,money:10,gold:3);if(!me.stock.canPay(cost))return _noRes();me.stock.pay(cost);me.borderDefense=min(10,me.borderDefense+1);_log('تم تعزيز دفاعات الحدود إلى المستوى ${me.borderDefense}.');_sync();notifyListeners();}
  void buildProvinceDefense(String provinceId){final p=provinces.where((x)=>x.id==provinceId).cast<Province?>().firstWhere((x)=>x!=null,orElse:()=>null);if(p==null||p.controller!=me.controller)return;if(multiplayer?.isConnected==true){multiplayer!.sendGameAction('buildProvinceDefense',value:provinceId);return;}final cost=Resources(steel:6,money:7,gold:2);if(!me.stock.canPay(cost))return _noRes();me.stock.pay(cost);p.fortLevel=min(8,p.fortLevel+1);_log('تم تحصين ${p.name} إلى المستوى ${p.fortLevel}.');_sync();notifyListeners();}
  void reinforceProvince(String provinceId,{int amount=2}){Province? p;for(final x in provinces){if(x.id==provinceId){p=x;break;}}if(p==null||p.controller!=me.controller||me.army.soldiers<amount)return;if(multiplayer?.isConnected==true){multiplayer!.sendGameAction('reinforceProvince',value:'$provinceId|$amount');return;}me.army.soldiers-=amount;p.garrison+=amount;_log('تم إرسال $amount مشاة إلى ${p.name}.');_sync();notifyListeners();}

  String terrainLabel(String value)=>switch(value){'mountains'=>tr('جبال','Mountains'),'hills'=>tr('تلال','Hills'),'desert'=>tr('صحراء','Desert'),'forest'=>tr('غابات','Forest'),'jungle'=>tr('أدغال','Jungle'),'urban'=>tr('مدن كثيفة','Urban'),'arctic'=>tr('قطبي','Arctic'),_=>tr('سهول','Plains')};
  String weatherLabel(String value)=>switch(value){'rain'=>tr('أمطار','Rain'),'storm'=>tr('عاصفة','Storm'),'snow'=>tr('ثلوج','Snow'),'heatwave'=>tr('موجة حر','Heatwave'),_=>tr('صحو','Clear')};
  double airRangeKm(Country c)=>900+c.techAir*260+c.airBases*170;
  double missileRangeKm(Country c)=>typedMissileRangeKm(c,'cruise');
  double distanceCountries(String a,String b){final x=countries[a],y=countries[b];if(x==null||y==null)return 99999;final ax=90-x.pos.dy*180,ay=x.pos.dx*360-180,bx=90-y.pos.dy*180,by=y.pos.dx*360-180;return _haversineKm(ax,ay,bx,by);}
  bool _hasLandAirReach(String targetId,Country base){final range=airRangeKm(base);return countries.values.where((x)=>x.controller==base.controller).any((x)=>siteFactor(x.id,'airport')>.25&&distanceCountries(x.id,targetId)<=range);}
  NavalTaskForce? _carrierLaunchTaskForce(String targetId,Country base){final zones=seaZonesForCountry(targetId);for(final tf in navalTaskForces){if(tf.owner==base.controller&&tf.carriers>0&&tf.readiness>=35&&tf.supply>=30&&zones.contains(tf.zoneId)&&{'carrier_strike','sea_control','patrol'}.contains(tf.mission))return tf;}return null;}
  bool canAirReach(String targetId)=>_hasLandAirReach(targetId,me)||_carrierLaunchTaskForce(targetId,me)!=null;
  double _airDefensePenetration(Country attacker,Country defender){final network=defender.radarLevel*.032+defender.earlyWarning*.028,penetration=attacker.electronicWarfare*.025+attacker.techIntel*.008;return (1-network+penetration).clamp(.68,1.06).toDouble();}
  bool canMissileReach(String targetId)=>canTypedMissileReach(targetId,'cruise');
  void upgradeProvinceInfrastructure(String provinceId,String kind){final p=provinceById(provinceId);if(p==null||p.controller!=me.controller)return;if(multiplayer?.isConnected==true){multiplayer!.sendGameAction('provinceInfrastructure',value:'$provinceId|$kind');return;}Resources cost;int current;if(kind=='roads'){cost=Resources(steel:5,money:8);current=p.roads;}else if(kind=='rail'){cost=Resources(steel:8,money:12);current=p.rail;}else{cost=Resources(fuel:2,steel:6,money:10);current=p.logisticsLevel;}if(current>=5){_log(tr('وصل هذا التطوير إلى الحد الأقصى.','This upgrade is already at maximum.'));return;}if(!me.stock.canPay(cost))return _noRes();me.stock.pay(cost);if(kind=='roads')p.roads++;else if(kind=='rail')p.rail++;else p.logisticsLevel++;p.infrastructure=min(100,p.infrastructure+(kind=='logistics'?3:5));p.supply=min(100,p.supply+(kind=='logistics'?10:4));_log('${p.name}: ${kind=='roads'?tr('طرق','roads'):kind=='rail'?tr('سكك','rail'):tr('لوجستيات','logistics')} ${kind=='roads'?p.roads:kind=='rail'?p.rail:p.logisticsLevel}.');_sync();notifyListeners();}
  void modernBuild(String kind){
    if(multiplayer?.isConnected==true){multiplayer!.sendGameAction('modernBuild',value:kind);return;}
    final c=me,missileKind=kind=='missile'||kind=='cruiseMissile'?'cruise':kind=='ballisticMissile'?'ballistic':kind=='hypersonicMissile'?'hypersonic':null;
    int current=0;if(kind=='missileDefense')current=c.missileDefense;else if(kind=='missileProgram')current=c.missileProgram;else if(kind=='ew')current=c.electronicWarfare;else if(kind=='satellite')current=c.satelliteRecon;else if(kind=='radar')current=c.radarLevel;else if(kind=='earlyWarning')current=c.earlyWarning;if(missileKind==null&&current>=5){_log(tr('وصلت هذه القدرة إلى المستوى الأقصى.','This capability is already at maximum.'));return;}
    Resources cost;if(missileKind=='cruise')cost=Resources(fuel:3,power:2,steel:6,money:11);else if(missileKind=='ballistic')cost=Resources(fuel:4,power:4,steel:9,money:16);else if(missileKind=='hypersonic')cost=Resources(fuel:5,power:6,steel:12,money:23);else if(kind=='missileDefense')cost=Resources(power:5,steel:12,money:18);else if(kind=='missileProgram')cost=Resources(power:7,steel:16,money:26);else if(kind=='ew')cost=Resources(power:6,steel:8,money:18);else if(kind=='satellite')cost=Resources(power:8,steel:12,money:24);else if(kind=='radar')cost=Resources(power:5,steel:10,money:16);else if(kind=='earlyWarning')cost=Resources(power:6,steel:12,money:20);else return;
    if(missileKind!=null){final minProgram=(kMissileTypes[missileKind]?['minProgram'] as num?)?.toInt()??1;if(c.missileProgram<minProgram){_log(tr('مستوى البرنامج الصاروخي غير كافٍ.','Missile program level is too low.'));return;}}if(!c.stock.canPay(cost))return _noRes();if(missileKind==null&&!_spendCommand(1))return;c.stock.pay(cost);
    if(missileKind=='cruise')c.cruiseMissiles++;if(missileKind=='ballistic')c.ballisticMissiles++;if(missileKind=='hypersonic')c.hypersonicMissiles++;c.missileStock=c.cruiseMissiles+c.ballisticMissiles+c.hypersonicMissiles;if(kind=='missileDefense')c.missileDefense=min(5,c.missileDefense+1);if(kind=='missileProgram')c.missileProgram=min(5,c.missileProgram+1);if(kind=='ew')c.electronicWarfare=min(5,c.electronicWarfare+1);if(kind=='satellite')c.satelliteRecon=min(5,c.satelliteRecon+1);if(kind=='radar')c.radarLevel=min(5,c.radarLevel+1);if(kind=='earlyWarning')c.earlyWarning=min(5,c.earlyWarning+1);_log(tr('تم تطوير قدرة الحرب الحديثة.','Modern warfare capability upgraded.'));_sync();notifyListeners();
  }
  void readinessMission(String kind){if(multiplayer?.isConnected==true){multiplayer!.sendGameAction('readinessMission',value:kind);return;}final fuel=kind=='air'?6.0:8.0;if(me.stock.fuel<fuel)return _noRes();if(!_spendCommand(1))return;me.stock.fuel-=fuel;if(kind=='air')me.airReadiness=100;else me.fleetReadiness=100;_log(kind=='air'?tr('رفعنا جاهزية القوات الجوية للسيطرة الجوية.','Air forces raised to air-superiority readiness.'):tr('أُرسل الأسطول في دورية سيطرة بحرية.','Fleet sent on a sea-control patrol.'));_sync();notifyListeners();}
  void missileStrike(String targetId,{String? siteId,String type='cruise'}){
    if(humanCountry==null||isMine(targetId))return;if(!kMissileTypes.containsKey(type))type='cruise';
    if(multiplayer?.isConnected==true){multiplayer!.sendGameAction('missileStrike',value:'$type|${siteId??''}',target:targetId);return;}
    final c=me,target=countries[targetId],count=type=='ballistic'?c.ballisticMissiles:type=='hypersonic'?c.hypersonicMissiles:c.cruiseMissiles,minProgram=(kMissileTypes[type]?['minProgram'] as num?)?.toInt()??1;if(target==null||count<1||c.missileProgram<minProgram){_log(tr('لا يوجد هذا النوع من الصواريخ جاهزًا.','No missile of this type is ready.'));return;}if(!canTypedMissileReach(targetId,type)){_log(tr('الهدف خارج مدى هذا الصاروخ.','Target is outside this missile range.'));return;}if(!_spendCommand(2))return;if(type=='ballistic')c.ballisticMissiles--;else if(type=='hypersonic')c.hypersonicMissiles--;else c.cruiseMissiles--;c.missileStock=c.cruiseMissiles+c.ballisticMissiles+c.hypersonicMissiles;
    final ps=provincesFor(targetId).where((x)=>x.controller==target.controller).toList(),prov=ps.isNotEmpty?ps.first:null,spec=kMissileTypes[type]!,rawIntercept=.05+target.radarLevel*.055+target.earlyWarning*.05+target.missileDefense*.105+target.army.airDefense*.010+target.electronicWarfare*.018+(prov?.fortLevel??0)*.008,intercept=(rawIntercept*(spec['intercept'] as num).toDouble()).clamp(.03,type=='hypersonic'?0.58:0.88),blocked=rng.nextDouble()<intercept;if(blocked){_log(tr('اعترض الدفاع متعدد الطبقات الضربة.','Layered defense intercepted the strike.'));_sync();notifyListeners();return;}
    StrategicSite? site;if(siteId!=null){for(final x in strategicSites){if(x.id==siteId&&x.countryId==targetId){site=x;break;}}}final lo=(spec['damageLo'] as num).toDouble(),hi=(spec['damageHi'] as num).toDouble(),dmg=lo+rng.nextDouble()*(hi-lo);if(site!=null){site.health=max(0,site.health-dmg);_applySiteShock(target,site.kind,dmg);}else{target.supply=max(0,target.supply-dmg*.22);target.stability=max(0,target.stability-dmg*.08);if(prov!=null){prov.infrastructure=max(15,prov.infrastructure-dmg*.18);prov.supply=max(0,prov.supply-dmg*.22);}}_log('${tr('أصابت ضربة','A')} ${tr((spec['ar']??type).toString(),(spec['en']??type).toString())} ${tr('الهدف بأضرار','strike hit for')} ${dmg.toStringAsFixed(0)}%.');_sync();notifyListeners();
  }
  void setAiDifficulty(String value){if(!{'easy','normal','hard'}.contains(value))return;aiDifficulty=value;notifyListeners();}
  bool _spendCommand(int amount){if(me.commandPoints<amount){_log('نقاط القيادة غير كافية. أنهِ الدور لاستعادتها أو طوّر اللوجستيات.');return false;}me.commandPoints-=amount;return true;}
  double combatPower(Country owner,[Army? army]){final a=army??owner.army;final armor=1+owner.techArmor*.06,air=1+owner.techAir*.06;return a.soldiers+a.tanks*3.2*armor+a.artillery*2.7*armor+a.airDefense*2.2+a.aircraft*4.5*air+a.helicopters*3.5*air+a.drones*2*air+a.recon*1.5+a.navy*4;}
  String attackPlanLabel(String p)=>p=='breakthrough'?'اختراق':p=='cautious'?'حذر':'متوازن';
  double attackPlanPower(String p)=>modeAttackPlanPower(p);
  double attackPlanCost(String p)=>modeAttackPlanCost(p);
  int attackPlanCommand(String p)=>p=='breakthrough'?3:2;
  bool isNavalAttack(Country from,Country target)=>isSeaLane(from.id,target.id)&&!from.neighbors.contains(target.id);
  bool canNavalInvade(Country from,Country target)=>isNavalAttack(from,target)&&me.army.navy>0&&siteFactor(from.id,'port')>.25;
  int attackCommandCost(Country from,Country target,String plan)=>attackPlanCommand(plan)+(isNavalAttack(from,target)?1:0);
  Resources attackCost(Country from,{String plan='balanced',Country? target}){final naval=target!=null&&isNavalAttack(from,target);return Resources(food:4+from.army.soldiers*.08+from.army.artillery*.12,water:3,fuel:5+from.army.tanks*.8+from.army.aircraft*1.2+from.army.helicopters*.7+(naval?7:0),power:1+from.army.drones*.08,steel:1+(naval?2:0),money:5+(naval?5:0)).scaled(attackPlanCost(plan)*(naval?1.18:1));}
  double estimatedAttackChance(Country from,Country target,String plan,{List<String>? armyIds}){final active=battleFor(from.id,target.id,from.controller),ids=active?.attackerArmyIds??armyIds;final field=fieldArmies.where((a)=>a.owner==from.controller&&a.location==from.id&&(ids==null||ids.contains(a.id))).fold<double>(0,(v,a)=>v+a.power*(a.supply/100)*(a.morale/100));final atk=(combatPower(me,from.army)+field)*(from.supply/100).clamp(.45,1.1)*supplyLineFactor(from.id)*attackPlanPower(plan)*(isNavalAttack(from,target)?(.72+min(3,me.army.navy)*.06):1)*(1-me.warExhaustion/230).clamp(.55,1.0),def=max(1.0,combatPower(target,target.army)*(target.supply/100).clamp(.5,1.1)*(target.stability/100).clamp(.35,1.1));return (50+(atk/def-1)*28).clamp(8,92).toDouble();}
  double intelConfidence(Country target){if(isMine(target.id))return 1;final raw=(me.intelligence+me.techIntel*11+me.army.recon*2.2+me.army.drones*1.1+me.satelliteRecon*4-target.intelligence*.28)/100;return raw.clamp(.22,.97).toDouble();}
  ({double low,double high,double confidence}) estimatedAttackRange(Country from,Country target,String plan,{List<String>? armyIds}){final center=estimatedAttackChance(from,target,plan,armyIds:armyIds),conf=intelConfidence(target),spread=(1-conf)*28+3;return (low:(center-spread).clamp(5,95).toDouble(),high:(center+spread).clamp(5,95).toDouble(),confidence:conf);}
  String enemyPowerLabel(Country target){if(isMine(target.id))return combatPower(target,target.army).toStringAsFixed(0);final conf=intelConfidence(target),actual=combatPower(target,target.army),step=conf>.78?5.0:conf>.5?15.0:30.0,rounded=(actual/step).round()*step;return conf>.78?'≈ ${rounded.toStringAsFixed(0)}':conf>.5?tr('تقدير ${max(1,rounded-step).toStringAsFixed(0)}–${(rounded+step).toStringAsFixed(0)}','Estimate ${max(1,rounded-step).toStringAsFixed(0)}–${(rounded+step).toStringAsFixed(0)}'):tr('معلومات محدودة','Limited intel');}
  double controllerScore(String controller){final owned=countries.values.where((c)=>c.controller==controller).toList();if(owned.isEmpty)return 0;final base=controllerBase(controller)??owned.first;final territory=owned.length*24.0,pop=owned.fold<double>(0,(n,c)=>n+c.population)*.02,economy=owned.fold<double>(0,(n,c)=>n+c.stock.money*.08+c.stock.steel*.06+c.production.money*.8),military=owned.fold<double>(0,(n,c)=>n+combatPower(base,c.army))*1.35,internal=owned.fold<double>(0,(n,c)=>n+c.stability+c.approval)/owned.length*.35;return territory+pop+economy+military+internal;}
  List<MapEntry<String,double>> get leaderboard {final ctrls=countries.values.map((c)=>c.controller).toSet();final out=ctrls.map((x)=>MapEntry(x,controllerScore(x))).toList()..sort((a,b)=>b.value.compareTo(a.value));return out;}
  List<Map<String,dynamic>> get pendingEvents=>events.where((e)=>e['controller']==me.controller&&e['status']!='resolved').toList();
  List<String> get strategicWarnings{
    final out=<String>[];final c=me;
    if(pendingEvents.isNotEmpty)out.add('لديك ${pendingEvents.length} حدث داخلي لم تحسمه.');
    if(c.stock.food<12)out.add('مخزون الغذاء منخفض (${c.stock.food.toStringAsFixed(0)}).');
    if(c.stock.water<12)out.add('مخزون المياه منخفض (${c.stock.water.toStringAsFixed(0)}).');
    if(c.stock.fuel<8)out.add('الوقود منخفض وقد يتأثر الجيش والإمداد.');
    if(c.stock.power<8)out.add('الكهرباء منخفضة وقد ينخفض الاستقرار والإنتاج.');
    if(c.warExhaustion>60)out.add('إرهاق الحرب مرتفع (${c.warExhaustion.toStringAsFixed(0)}%).');
    final isolated=countries.values.where((x)=>x.controller==c.controller&&!isSupplyConnected(x.id)).length;
    if(isolated>0)out.add('لديك $isolated إقليم/أقاليم معزولة عن مركز القيادة.');
    final fronts=activeBattles.where((b)=>b.attacker==c.controller||b.defender==c.controller).length;if(fronts>0)out.add('لديك $fronts جبهة قتالية نشطة تحتاج متابعة.');
    if(c.commandPoints>0)out.add('لا تزال لديك ${c.commandPoints} نقطة قيادة غير مستخدمة.');
    return out;
  }

  List<FrontBattle> get activeBattles=>battles.where((b)=>b.active).toList();
  FrontBattle? battleFor(String source,String target,String attacker){for(final b in battles){if(b.active&&b.source==source&&b.target==target&&b.attacker==attacker)return b;}return null;}
  FrontBattle? battleById(String id){for(final b in battles){if(b.id==id)return b;}return null;}
  FrontBattle? battleUsingArmy(String armyId){for(final b in activeBattles){if(b.attackerArmyIds.contains(armyId)||b.defenderArmyIds.contains(armyId))return b;}return null;}
  List<FieldArmy> availableBattleArmies(String location,String owner)=>fieldArmies.where((a)=>a.owner==owner&&a.location==location&&battleUsingArmy(a.id)==null).toList();
  List<String> _retreatOptionsFor(String owner,String from){final out=<String>[];for(final n in countries[from]?.neighbors??const <String>[]){if(countries[n]?.controller==owner)out.add(n);}for(final n in countries.keys.where((x)=>x!=from&&isSeaLane(from,x))){if(countries[n]?.controller==owner&&_seaSupplyAvailable(owner,from,n)&&!out.contains(n))out.add(n);}return out;}
  bool _battleEncircled(FrontBattle battle)=>_retreatOptionsFor(battle.defender,battle.target).isEmpty;
  double _fieldBattlePower(Country base,FieldArmy a)=>combatPower(base,Army(soldiers:a.soldiers,tanks:a.tanks,artillery:a.artillery,airDefense:a.airDefense,aircraft:a.aircraft,helicopters:a.helicopters,drones:a.drones,recon:a.recon,navy:0))*(a.supply/100).clamp(.35,1.08)*(a.morale/100).clamp(.35,1.08);
  double _participantPower(Country base,List<String> ids){var total=0.0;for(final id in ids){for(final a in fieldArmies){if(a.id==id){total+=_fieldBattlePower(base,a);break;}}}return total;}
  double _airAssets(Country c,List<String> ids){var total=c.army.aircraft*2+c.army.drones+c.army.helicopters*.6;for(final id in ids){for(final a in fieldArmies){if(a.id==id){total+=a.aircraft*2+a.drones+a.helicopters*.6;break;}}}return total*(.62+c.airReadiness.clamp(0,100)/260);}
  void _applyArmyLossesToArmy(Army a,double severity){final s=severity.clamp(0.0,.82);int cut(int value,double protection)=>max(0,(value*(1-s*(1-protection))).round());a.soldiers=cut(a.soldiers,0);a.tanks=cut(a.tanks,0);a.artillery=cut(a.artillery,0);a.airDefense=cut(a.airDefense,.18);a.aircraft=cut(a.aircraft,.22);a.helicopters=cut(a.helicopters,.12);a.drones=cut(a.drones,.10);a.recon=cut(a.recon,.35);}
  void _applyArmyLossesToField(FieldArmy a,double severity){final s=severity.clamp(0.0,.82);int cut(int value,double protection)=>max(0,(value*(1-s*(1-protection))).round());a.soldiers=cut(a.soldiers,0);a.tanks=cut(a.tanks,0);a.artillery=cut(a.artillery,0);a.airDefense=cut(a.airDefense,.18);a.aircraft=cut(a.aircraft,.22);a.helicopters=cut(a.helicopters,.12);a.drones=cut(a.drones,.10);a.recon=cut(a.recon,.35);}
  ({double attacker,double defender}) _battleLosses(double ratio,bool wonRound)=>modeBattleLossSeverity(ratio,wonRound);
  void _captureLocalBattle(FrontBattle battle,Country base,Country from,Country target){
    final province=provinceById(battle.targetProvinceId);
    if(province!=null&&province.countryId==target.id){province.controller=battle.attacker;province.garrison=max(0,(province.garrison*.25).round());province.resistance=45;battle.status='won';battle.progress=100;final remaining=provincesFor(target.id).any((p)=>p.controller!=battle.attacker);if(remaining){_log('سقطت محافظة ${province.name} في ${target.name}. بقي ${provincesFor(target.id).where((p)=>p.controller!=battle.attacker).length} محافظة قبل سقوط الدولة.');return;}}
    final old=target.controller,retreatOptions=_retreatOptionsFor(battle.defender,battle.target),defendingIds=fieldArmies.where((a)=>a.owner==battle.defender&&a.location==battle.target).map((a)=>a.id).toList();
    target.controller=battle.attacker;for(final p in provincesFor(target.id)){p.controller=battle.attacker;}target.approval=36;target.stability=50;target.resistance=52;target.supply=45;target.morale=46;target.occupationPolicy='balanced';
    base.population+=target.population*.03;base.stock.add(Resources(food:target.stock.food*.26,water:target.stock.water*.20,fuel:target.stock.fuel*.28,power:target.stock.power*.16,steel:target.stock.steel*.28,money:target.stock.money*.20));target.army=Army(soldiers:2,tanks:0,artillery:0,airDefense:0,aircraft:0,helicopters:0,drones:0,recon:0,navy:0);
    for(final id in battle.attackerArmyIds){for(final a in fieldArmies){if(a.id==id&&a.owner==battle.attacker&&a.location==battle.source){a.location=battle.target;a.supply=max(0,a.supply-5);break;}}}
    for(final id in defendingIds){FieldArmy? a;for(final x in fieldArmies){if(x.id==id){a=x;break;}}if(a==null||a.owner!=battle.defender||a.location!=battle.target)continue;if(retreatOptions.isNotEmpty)a.location=retreatOptions.first;else if(battle.encircled)fieldArmies.remove(a);}
    battle.status='won';battle.progress=100;_log('حُسمت جبهة ${from.name} → ${target.name}: احتلال تدريجي ناجح من $old بعد ${battle.round} جولة.');
  }

  ({double ratio,double delta}) _resolveLocalBattleRound(FrontBattle battle,Country base,Country from,Country target,String plan){final attackers=<FieldArmy>[],defenders=<FieldArmy>[];for(final id in battle.attackerArmyIds){for(final a in fieldArmies){if(a.id==id){attackers.add(a);break;}}}for(final id in battle.defenderArmyIds){for(final a in fieldArmies){if(a.id==id){defenders.add(a);break;}}}battle.encircled=_battleEncircled(battle);battle.airControl=frontlineControlEdge(_airAssets(base,battle.attackerArmyIds),_airAssets(target,battle.defenderArmyIds));battle.navalControl=battle.naval?frontlineControlEdge(base.army.navy*(.62+base.fleetReadiness/260),target.army.navy*(.62+target.fleetReadiness/260)):0;final line=_supplyConnectedFor(battle.attacker,battle.source)?1.0:(.58+base.techLogistics*.035),navalFactor=battle.naval?(.72+min(3,base.army.navy)*.06):1.0;final atk=(combatPower(base,from.army)+_participantPower(base,battle.attackerArmyIds))*(.86+rng.nextDouble()*.28)*(from.stability/100)*(from.supply/100).clamp(.45,1.12)*(from.morale/100).clamp(.45,1.12)*line*attackPlanPower(plan)*navalFactor*(1-base.warExhaustion/230).clamp(.55,1.0)*(1+battle.airControl*.08);final localProvince=provinceById(battle.targetProvinceId),provinceFort=1+(localProvince?.fortLevel??0)*.12,provinceGarrison=(localProvince?.garrison??0)*1.4,provinceReadiness=(.72+(localProvince?.infrastructure??60)/180)*(.70+(localProvince?.supply??70)/230);final def=(combatPower(target,target.army)+_participantPower(target,battle.defenderArmyIds)+provinceGarrison)*(1+target.borderDefense*.07)*provinceFort*provinceReadiness*(.90+rng.nextDouble()*.24)*(target.stability/100)*(target.supply/100).clamp(.5,1.1)*(1-target.warExhaustion/280).clamp(.60,1.0)*(battle.encircled?0.78:1.0)*(1-battle.airControl*.05);final terrain=_terrainProfile(localProvince?.terrain??'plains'),weather=_weatherProfile(localProvince?.weather??'clear'),land=_landCoverProfile(localProvince?.landCover??'unknown'),elev=_elevationProfile(localProvince),infraCap=_provinceInfrastructureCapacity(localProvince),envAtk=.72+((terrain['attack']??1)*(weather['mobility']??1)*(land['attack']??1)*(elev['attack']??1))*.28,envDef=.72+((terrain['defense']??1)*(land['defense']??1)*(elev['defense']??1))*.28,route=.70+(infraCap*(weather['supply']??1)*(land['supply']??1)*(elev['supply']??1))*.30,airWeather=.70+((terrain['air']??1)*(weather['air']??1)*(land['air']??1)*(elev['air']??1))*.30,ew=(1+(base.electronicWarfare-target.electronicWarfare).clamp(-5,5)*.045);final ratio=(atk*envAtk*route*ew*(1+battle.airControl*.08*airWeather))/max(1,def*envDef),delta=frontlineProgressDelta(ratio,plan:plan,encircled:battle.encircled,airEdge:battle.airControl,navalEdge:battle.navalControl,randomFactor:rng.nextDouble()*2-1),loss=_battleLosses(ratio,delta>=0);battle.progress=(battle.progress+delta).clamp(0,100).toDouble();battle.round++;battle.lastResolvedTurn=turn;battle.plan=plan;_applyArmyLossesToArmy(base.army,loss.attacker*.55);for(final a in attackers){_applyArmyLossesToField(a,loss.attacker);a.supply=max(0,a.supply-3);a.morale=(a.morale+(delta>=0?1:-4)).clamp(0,100).toDouble();}_applyArmyLossesToArmy(target.army,loss.defender);for(final a in defenders){_applyArmyLossesToField(a,loss.defender);a.supply=max(0,a.supply-2);a.morale=(a.morale+(delta>=0?-4:1)).clamp(0,100).toDouble();}target.morale=(target.morale+(delta>=0?-3:1)).clamp(0,100).toDouble();base.warExhaustion=(base.warExhaustion+(plan=='breakthrough'?9:plan=='cautious'?3:5)*.65).clamp(0,100).toDouble();battle.history.insert(0,{'turn':turn,'round':battle.round,'delta':double.parse(delta.toStringAsFixed(1)),'ratio':double.parse(ratio.toStringAsFixed(2)),'encircled':battle.encircled,'terrain':localProvince?.terrain??'plains','weather':localProvince?.weather??'clear','landCover':localProvince?.landCover??'unknown','elevationM':localProvince?.elevationM??0,'roadDensity':localProvince?.roadDensity??0});if(battle.history.length>12)battle.history.removeLast();return (ratio:ratio,delta:delta);}

  Future<void> attack(String targetId,{String plan='balanced',List<String>? armyIds,String? sourceId,String? mode,String? targetProvinceId}) async {
    if(humanCountry==null)return;final source=sourceId!=null&&countries[sourceId]?.controller==me.controller?countries[sourceId]:attackSourceFor(targetId);if(source==null){_log('لا توجد جبهة تابعة لك ومجاورة لـ ${countries[targetId]?.name??targetId}. حرّك توسعك عبر دول متصلة.');return;}
    if(multiplayer?.isConnected==true){final ok=await multiplayer!.sendAttack(source.id,targetId,plan:plan,armyIds:armyIds,mode:mode??battleMode,targetProvinceId:targetProvinceId);if(!ok)_log('رفض السيرفر الهجوم أو تعذر تنفيذه.');return;}
    final from=source,target=countries[targetId]!;if(isMine(targetId)){_log('هذه المنطقة تحت سيطرتك.');return;}if(areAllies(from.id,targetId)){_log('لا يمكنك مهاجمة حليف قبل إنهاء التحالف.');return;}final naval=isNavalAttack(from,target);if(naval&&!canNavalInvade(from,target)){_log('الغزو البرمائي يحتاج أسطولاً وميناءً صالحًا في إقليم الانطلاق.');return;}
    var battle=battleFor(from.id,targetId,from.controller);if(battle!=null&&battle.defender!=target.controller){battle.status='stale';battle=null;}
    final cp=attackCommandCost(from,target,plan);if(!_spendCommand(cp))return;final cost=attackCost(from,plan:plan,target:target);if(!me.stock.canPay(cost)){me.commandPoints+=cp;_log('الموارد غير كافية للهجوم.');return;}me.stock.pay(cost);
    if(battle==null){final available=availableBattleArmies(from.id,from.controller),requested=(armyIds??available.map((a)=>a.id).toList()).toSet(),selected=available.where((a)=>requested.contains(a.id)).map((a)=>a.id).toList(),defenders=availableBattleArmies(targetId,target.controller).map((a)=>a.id).toList();final provinceId=targetProvinceId??(enemyProvinces(targetId).isNotEmpty?enemyProvinces(targetId).first.id:null);battle=FrontBattle(id:'B${DateTime.now().millisecondsSinceEpoch}',source:from.id,target:targetId,attacker:from.controller,defender:target.controller,plan:plan,naval:naval,startedTurn:turn,targetProvinceId:provinceId,attackerArmyIds:selected,defenderArmyIds:defenders);battles.add(battle);}
    var result=_resolveLocalBattleRound(battle,me,from,target,plan);if((mode??battleMode)=='auto'){var guard=0;while(battle.progress<100&&battle.progress>0&&guard<12&&battle.active){result=_resolveLocalBattleRound(battle,me,from,target,plan);guard++;}}if(battle.progress>=100){_captureLocalBattle(battle,me,from,target);}else{_log('${(mode??battleMode)=='auto'?'حسم آلي':'جبهة'} ${from.name} → ${target.name}: الجولة ${battle.round} والسيطرة ${battle.progress.toStringAsFixed(0)}%${battle.encircled?' • تطويق':''}.');}_updateLocalOutcome();_sync();notifyListeners();
  }

  void reinforceBattle(String battleId,String armyId){final battle=battleById(battleId);if(battle==null||!battle.active||humanCountry==null)return;FieldArmy? a;for(final x in fieldArmies){if(x.id==armyId){a=x;break;}}if(a==null||a.owner!=me.controller||battleUsingArmy(armyId)!=null)return;final attackerSide=me.controller==battle.attacker,defenderSide=me.controller==battle.defender;if(!attackerSide&&!defenderSide)return;final required=attackerSide?battle.source:battle.target;if(a.location!=required){_log('هذا الجيش ليس موجودًا على الجبهة المطلوبة.');return;}if(multiplayer?.isConnected==true){multiplayer!.sendGameAction('reinforceBattle',value:'$battleId|$armyId');return;}if(!_spendCommand(1))return;(attackerSide?battle.attackerArmyIds:battle.defenderArmyIds).add(armyId);a.supply=max(0,a.supply-4);_log('${a.name} دخلت كتعزيز إلى الجبهة.');notifyListeners();}
  void retreatBattle(String battleId){final battle=battleById(battleId);if(battle==null||!battle.active||humanCountry==null)return;final attackerSide=me.controller==battle.attacker,defenderSide=me.controller==battle.defender;if(!attackerSide&&!defenderSide)return;String? destination;if(defenderSide){final options=_retreatOptionsFor(battle.defender,battle.target);if(options.isNotEmpty)destination=options.first;if(destination==null){_log('لا يوجد ممر انسحاب بري أو بحري آمن للمدافع.');return;}}if(multiplayer?.isConnected==true){multiplayer!.sendGameAction('retreatBattle',value:battleId,target:destination);return;}if(!_spendCommand(1))return;if(attackerSide){for(final id in battle.attackerArmyIds){for(final a in fieldArmies){if(a.id==id){a.morale=max(0,a.morale-6);a.supply=max(0,a.supply-2);break;}}}battle.status='retreated';_log('تم الانسحاب تكتيكيًا من جبهة ${countries[battle.target]?.name??battle.target}.');}else{for(final id in battle.defenderArmyIds){for(final a in fieldArmies){if(a.id==id){a.location=destination!;break;}}}battle.defenderArmyIds.clear();battle.progress=(battle.progress+35).clamp(0,100).toDouble();if(battle.progress>=100){final from=countries[battle.source],target=countries[battle.target],base=controllerBase(battle.attacker);if(from!=null&&target!=null&&base!=null)_captureLocalBattle(battle,base,from,target);}else _log('انسحاب دفاعي إلى ${countries[destination]?.name??destination}; تقدم المهاجم إلى ${battle.progress.toStringAsFixed(0)}%.');}notifyListeners();}

  Country? attackSourceFor(String targetId){
    final t=countries[targetId];if(t==null||humanCountry==null)return null;for(final b in activeBattles){if(b.target==targetId&&b.attacker==me.controller&&countries[b.source]?.controller==me.controller)return countries[b.source];}
    final owned=countries.values.where((c)=>isMine(c.id)&&(c.neighbors.contains(targetId)||canNavalInvade(c,t))).toList();
    if(owned.isEmpty)return null;
    owned.sort((a,b)=>(b.army.power+b.supply/12+(isNavalAttack(b,t)?-8:0)).compareTo(a.army.power+a.supply/12+(isNavalAttack(a,t)?-8:0)));
    return owned.first;
  }

  void formFieldArmy(String location){
    if(humanCountry==null||!isMine(location)){_log('يجب تشكيل الجيش داخل إقليم تسيطر عليه.');return;}
    if(multiplayer?.isConnected==true){multiplayer!.sendGameAction('formArmy',target:location);return;}
    final base=me;if(base.army.soldiers<3||base.stock.money<6||base.stock.food<2){_noRes();return;}
    base.army.soldiers-=3;base.stock.money-=6;base.stock.food-=2;
    fieldArmies.add(FieldArmy(id:'A${DateTime.now().millisecondsSinceEpoch}',name:'الجيش ${fieldArmies.length+1}',owner:base.controller,location:location));
    _log('تم تشكيل جيش ميداني في ${countries[location]!.name}.');notifyListeners();
  }

  void moveFieldArmy(String armyId,String destination){
    FieldArmy? a;for(final x in fieldArmies){if(x.id==armyId){a=x;break;}}
    if(a==null||humanCountry==null)return;if(battleUsingArmy(armyId)!=null){_log('هذا الجيش مرتبط بمعركة نشطة؛ عزّزه أو انسحب من الجبهة أولاً.');return;}
    final from=countries[a.location],to=countries[destination];
    if(from==null||to==null||!from.neighbors.contains(destination)||!isMine(destination)){_log('يمكن تحريك الجيش فقط إلى إقليم مجاور تسيطر عليه.');return;}
    if(multiplayer?.isConnected==true){multiplayer!.sendGameAction('moveArmy',value:armyId,target:destination);return;}
    final route=movementCostBetween(a.location,destination),fuel=(route['fuelCost'] as num).toInt(),loss=(route['supplyLoss'] as num).toInt();if(me.stock.fuel<fuel){_noRes();return;}if(!_spendCommand(1))return;me.stock.fuel-=fuel;a.location=destination;a.supply=max(0,a.supply-loss);_log('${a.name} تحرك إلى ${to.name} • وقود $fuel • استنزاف إمداد $loss.');notifyListeners();
  }

  void reinforceFieldArmy(String armyId,String type){
    FieldArmy? a;for(final x in fieldArmies){if(x.id==armyId){a=x;break;}}
    if(a==null||humanCountry==null||a.owner!=me.controller)return;
    if(multiplayer?.isConnected==true){multiplayer!.sendGameAction('reinforceArmy',value:'$armyId|$type');return;}
    final n=me.army;
    switch(type){
      case 'soldiers':if(n.soldiers<2)return _noRes();n.soldiers-=2;a.soldiers+=2;break;
      case 'tank':if(n.tanks<1)return _noRes();n.tanks--;a.tanks++;break;
      case 'artillery':if(n.artillery<1)return _noRes();n.artillery--;a.artillery++;break;
      case 'airDefense':if(n.airDefense<1)return _noRes();n.airDefense--;a.airDefense++;break;
      case 'air':if(n.aircraft<1)return _noRes();n.aircraft--;a.aircraft++;break;
      case 'heli':if(n.helicopters<1)return _noRes();n.helicopters--;a.helicopters++;break;
      case 'drone':if(n.drones<1)return _noRes();n.drones--;a.drones++;break;
      case 'recon':if(n.recon<1)return _noRes();n.recon--;a.recon++;break;
    }
    a.supply=min(100,a.supply+4);_log('تم تعزيز ${a.name}: $type.');notifyListeners();
  }

  void strikeSite(String siteId){
    StrategicSite? site;for(final s in strategicSites){if(s.id==siteId){site=s;break;}}
    if(site==null||humanCountry==null||isMine(site.countryId)){_log('اختر منشأة معادية لاستهدافها.');return;}
    if(multiplayer?.isConnected==true){multiplayer!.sendGameAction('siteStrike',value:siteId,target:site.countryId);return;}
    final target=countries[site.countryId]!;final c=me;if(!canAirReach(site.countryId)){_log(tr('الهدف خارج مدى الطيران الحالي.','Target is outside current air range.'));return;}
    if(c.army.aircraft+c.army.drones<2||c.stock.fuel<6||c.stock.money<7)return _noRes();
    if(!_spendCommand(2))return;c.stock.fuel-=6;c.stock.money-=7;
    final tp=provincesFor(site.countryId).where((p)=>p.controller==target.controller).isNotEmpty?provincesFor(site.countryId).firstWhere((p)=>p.controller==target.controller):null,airEnv=(_terrainProfile(tp?.terrain??'plains')['air']??1)*(_weatherProfile(tp?.weather??'clear')['air']??1),readiness=.55+c.airReadiness.clamp(0,100)/220,ew=(1+(c.electronicWarfare-target.electronicWarfare).clamp(-5,5)*.045),airDefense=_airDefensePenetration(c,target),carrierTf=_hasLandAirReach(site.countryId,c)?null:_carrierLaunchTaskForce(site.countryId,c);final chance=((.42+c.army.drones*.025+c.intelligence/340-target.army.airDefense*.022)*airEnv*readiness*ew*airDefense).clamp(.08,.92);if(carrierTf!=null){carrierTf.readiness=max(0.0,carrierTf.readiness-6);carrierTf.supply=max(0.0,carrierTf.supply-5);}
    if(rng.nextDouble()<chance){final dmg=18+rng.nextDouble()*24;site.health=max(0,site.health-dmg);_applySiteShock(target,site.kind,dmg);_log('غارة دقيقة ناجحة على ${site.name} في ${target.name}: أضرار ${dmg.toStringAsFixed(0)}%.');}
    else{if(c.army.aircraft>0)c.army.aircraft--;_log('فشلت الغارة الدقيقة على ${site.name} وخسرنا طائرة.');}
    _sync();notifyListeners();
  }

  void _applySiteShock(Country target,String kind,double damage){
    if(kind=='capital'){target.stability=max(0,target.stability-damage*.12);target.approval=max(0,target.approval-damage*.08);if(isOccupied(target))target.resistance=min(100,target.resistance+damage*.12);}
    if(kind=='airport'){target.morale=max(0,target.morale-damage*.10);target.supply=max(0,target.supply-damage*.08);}
    if(kind=='port'){target.stock.fuel=max(0,target.stock.fuel-damage*.18);target.stock.food=max(0,target.stock.food-damage*.12);}
    if(kind=='factory'){target.stock.steel=max(0,target.stock.steel-damage*.15);target.stock.money=max(0,target.stock.money-damage*.10);}
    if(kind=='power'){target.stock.power=max(0,target.stock.power-damage*.25);target.stability=max(0,target.stability-damage*.04);}
    if(kind=='supply'){target.supply=max(0,target.supply-damage*.25);target.morale=max(0,target.morale-damage*.08);}
  }

  void repairSite(String siteId){
    StrategicSite? site;for(final s in strategicSites){if(s.id==siteId){site=s;break;}}
    if(site==null||!isMine(site.countryId)){_log('يمكن إصلاح منشآت تقع تحت سيطرتك فقط.');return;}
    if(multiplayer?.isConnected==true){multiplayer!.sendGameAction('repairSite',value:siteId,target:site.countryId);return;}
    final c=me;final cost=Resources(power:3,steel:6,money:8);if(!c.stock.canPay(cost))return _noRes();c.stock.pay(cost);site.health=min(100,site.health+30);_log('تم إصلاح ${site.name} إلى ${site.health.toStringAsFixed(0)}%.');_sync();notifyListeners();
  }

  void buildSite(String countryId,String kind){
    if(!isMine(countryId)){_log('يجب بناء المنشأة داخل أرض تسيطر عليها.');return;}
    if(multiplayer?.isConnected==true){multiplayer!.sendGameAction('siteBuild',value:kind,target:countryId);return;}
    final c=me;Resources cost;
    if(kind=='airport')cost=Resources(fuel:3,power:4,steel:14,money:20);
    else if(kind=='port')cost=Resources(fuel:4,power:3,steel:16,money:22);
    else if(kind=='power')cost=Resources(steel:10,money:14);
    else if(kind=='supply')cost=Resources(food:3,fuel:2,steel:8,money:12);
    else cost=Resources(power:4,steel:12,money:16);
    if(!c.stock.canPay(cost))return _noRes();c.stock.pay(cost);
    final existing=strategicSites.where((x)=>x.countryId==countryId).length;final a=existing*1.7;final off=Offset(cos(a)*.014,sin(a)*.018);
    strategicSites.add(StrategicSite(id:'S${DateTime.now().millisecondsSinceEpoch}',countryId:countryId,name:_siteKindName(kind),kind:kind,offset:off));
    _log('تم بناء ${_siteKindName(kind)} في ${countries[countryId]!.name}.');_sync();notifyListeners();
  }

  String _siteKindName(String kind)=>switch(kind){'capital'=>'العاصمة','airport'=>'قاعدة جوية','port'=>'ميناء عسكري','power'=>'محطة طاقة','supply'=>'مركز إمداد',_=>'مجمع صناعي'};

  void strategicStrike(String targetId,String kind){
    if(humanCountry==null||isMine(targetId))return;
    if(multiplayer?.isConnected==true){multiplayer!.sendGameAction('strategicStrike',value:kind,target:targetId);return;}
    final target=countries[targetId]!;final c=me;
    if(kind=='air'){
      if(!canAirReach(targetId)){_log(tr('الهدف خارج مدى الطيران الحالي.','Target is outside current air range.'));return;}
      if(c.army.aircraft+c.army.drones<2||c.stock.fuel<7||c.stock.money<8)return _noRes();
      if(!_spendCommand(2))return;c.stock.fuel-=7;c.stock.money-=8;final tp=provincesFor(targetId).where((p)=>p.controller==target.controller).isNotEmpty?provincesFor(targetId).firstWhere((p)=>p.controller==target.controller):null,airEnv=(_terrainProfile(tp?.terrain??'plains')['air']??1)*(_weatherProfile(tp?.weather??'clear')['air']??1),readiness=.55+c.airReadiness.clamp(0,100)/220,ew=(1+(c.electronicWarfare-target.electronicWarfare).clamp(-5,5)*.045),airDefense=_airDefensePenetration(c,target),carrierTf=_hasLandAirReach(targetId,c)?null:_carrierLaunchTaskForce(targetId,c),success=((.40+c.army.drones*.025+c.intelligence/320-target.army.airDefense*.025)*airEnv*readiness*ew*airDefense).clamp(.08,.90);if(carrierTf!=null){carrierTf.readiness=max(0.0,carrierTf.readiness-7);carrierTf.supply=max(0.0,carrierTf.supply-6);}
      if(rng.nextDouble()<success){target.grid=max(0,target.grid-1);target.supply=max(0,target.supply-12);target.stability=max(0,target.stability-4);_log('غارة جوية ناجحة على ${target.name}: تضررت الكهرباء والإمدادات.');}else{c.army.aircraft=max(0,c.army.aircraft-1);_log('فشلت الغارة على ${target.name} وخسرنا طائرة.');}
    }else if(kind=='blockade'){
      if(c.army.navy<1||c.stock.fuel<5)return _noRes();if(!_spendCommand(2))return;c.stock.fuel-=5;final ourNaval=c.army.navy*(.62+c.fleetReadiness.clamp(0,100)/260),theirNaval=max(.4,target.army.navy*(.62+target.fleetReadiness.clamp(0,100)/260)),pressure=(.55+(log(max(.25,ourNaval/theirNaval))/ln2)*.22).clamp(.25,1.35);target.stock.fuel=max(0,target.stock.fuel-10*pressure);target.stock.food=max(0,target.stock.food-7*pressure);target.approval=max(0,target.approval-3*pressure);c.fleetReadiness=(c.fleetReadiness-4).clamp(25,100).toDouble();_log('${tr('حصار بحري','Naval blockade')} ${target.name}: ${tr('ضغط','pressure')} ${(pressure*100).toStringAsFixed(0)}%.');
    }
    _sync();notifyListeners();
  }

  void strategicBuild(String type){
    if(multiplayer?.isConnected==true){multiplayer!.sendGameAction('strategicBuild',value:type);return;}
    final c=me;
    Resources cost=Resources();
    if(type=='airbase')cost=Resources(fuel:3,steel:12,money:18,power:4);
    if(type=='navalbase')cost=Resources(fuel:4,steel:14,money:20,power:3);
    if(type=='supply')cost=Resources(food:4,fuel:3,steel:8,money:12);
    if(!c.stock.canPay(cost))return _noRes();
    c.stock.pay(cost);
    if(type=='airbase')c.airBases++;
    if(type=='navalbase')c.navalBases++;
    if(type=='supply'){c.supplyHubs++;c.supply=min(100,c.supply+12);}
    _log('تم إنشاء منشأة استراتيجية: $type.');_sync();notifyListeners();
  }

  void spy(String other){
    if(multiplayer?.isConnected==true){multiplayer!.sendGameAction('spy',target:other);return;}
    if(humanCountry==null||other==humanCountry)return;
    if(me.stock.money<8)return _noRes();
    if(!_spendCommand(1))return;me.stock.money-=8;
    final target=countries[other]!;
    final chance=.35+me.army.recon*.05+me.intelligence/250+me.techIntel*.045;
    if(rng.nextDouble()<chance){me.intelligence=min(100,me.intelligence+8);_log('نجحت عملية الاستطلاع في ${target.name}: القوة ${target.army.power.toStringAsFixed(0)} والمخزون الوقودي ${target.stock.fuel.toStringAsFixed(0)}.');}
    else {_log('فشلت عملية التجسس في ${target.name}.');me.approval-=1;}
    _sync();notifyListeners();
  }

  void toggleSanction(String other){
    if(multiplayer?.isConnected==true){multiplayer!.sendGameAction('sanction',target:other);return;}
    if(other==humanCountry)return;
    if(sanctions.contains(other)){sanctions.remove(other);_log('تم رفع العقوبات عن ${countries[other]!.name}.');}
    else {sanctions.add(other);countries[other]!.production.money=max(1,countries[other]!.production.money-1);_log('تم فرض عقوبات اقتصادية على ${countries[other]!.name}.');}
    _sync();notifyListeners();
  }

  void trade(String other){
    if(multiplayer?.isConnected==true){multiplayer!.sendGameAction('trade',target:other);return;}
    if(other==humanCountry)return; final t=countries[other]!;
    if(me.stock.money<10)return _noRes();
    me.stock.money-=10;me.stock.fuel+=8;me.stock.food+=8;t.stock.money+=6;tradeDeals.insert(0,'${me.name} ↔ ${t.name}: غذاء ووقود مقابل المال');
    if(tradeDeals.length>20)tradeDeals.removeLast();_log('تم توقيع صفقة تجارة مع ${t.name}.');_sync();notifyListeners();
  }

  void build(String type){
    if(multiplayer?.isConnected==true){multiplayer!.sendGameAction('build',value:type);return;}
    final c=me; Resources cost=Resources();
    switch(type){
      case 'solar': cost=Resources(steel:8,money:12); if(!c.stock.canPay(cost))return _noRes(); c.stock.pay(cost);c.solar++;break;
      case 'nuclear': cost=Resources(water:6,steel:18,money:30);if(!c.stock.canPay(cost))return _noRes();c.stock.pay(cost);c.nuclear++;break;
      case 'grid': cost=Resources(steel:10,money:12);if(!c.stock.canPay(cost))return _noRes();c.stock.pay(cost);c.grid++;break;
      case 'farm': cost=Resources(water:5,power:3,money:8);if(!c.stock.canPay(cost))return _noRes();c.stock.pay(cost);c.farms++;break;
      case 'food': cost=Resources(power:4,steel:4,money:10);if(!c.stock.canPay(cost))return _noRes();c.stock.pay(cost);c.foodFactories++;break;
      case 'civil': cost=Resources(power:6,steel:8,money:14);if(!c.stock.canPay(cost))return _noRes();c.stock.pay(cost);c.civilianIndustry++;break;
      case 'mil': cost=Resources(power:8,steel:12,money:18);if(!c.stock.canPay(cost))return _noRes();c.stock.pay(cost);c.militaryIndustry++;break;
      case 'training': return buildTrainingCamp();
      case 'borderDefense': return buildBorderDefense();
    }
    _log('تم إنشاء مشروع جديد: $type.');_sync();notifyListeners();
  }
  void _noRes()=>_log('الموارد غير كافية لهذا المشروع.');

  void recruit(String type){
    if(multiplayer?.isConnected==true){multiplayer!.sendGameAction('recruit',value:type);return;}
    final c=me; Resources cost;
    switch(type){
      case 'soldiers':final qty=min(5,recruitRemaining);if(qty<=0){_log('وصلت إلى سعة التدريب لهذا الدور. ابنِ معسكرات تدريب أو انتظر الدور التالي.');return;}cost=Resources(food:qty*.7,water:qty*.4,money:qty*.6,gold:qty*1.2);if(!c.stock.canPay(cost))return _noRes();c.stock.pay(cost);c.army.soldiers+=qty;c.recruitedThisTurn+=qty;break;
      case 'tank':cost=Resources(fuel:3,steel:8,money:10);if(!c.stock.canPay(cost))return _noRes();c.stock.pay(cost);c.army.tanks++;break;
      case 'artillery':cost=Resources(steel:6,money:8,power:2);if(!c.stock.canPay(cost))return _noRes();c.stock.pay(cost);c.army.artillery++;break;
      case 'airDefense':cost=Resources(steel:7,money:10,power:2);if(!c.stock.canPay(cost))return _noRes();c.stock.pay(cost);c.army.airDefense++;break;
      case 'air':cost=Resources(fuel:5,steel:10,money:15);if(!c.stock.canPay(cost))return _noRes();c.stock.pay(cost);c.army.aircraft++;break;
      case 'heli':cost=Resources(fuel:4,steel:8,money:12);if(!c.stock.canPay(cost))return _noRes();c.stock.pay(cost);c.army.helicopters++;break;
      case 'drone':cost=Resources(fuel:1,steel:3,power:2,money:7);if(!c.stock.canPay(cost))return _noRes();c.stock.pay(cost);c.army.drones++;break;
      case 'recon':cost=Resources(fuel:1,money:6);if(!c.stock.canPay(cost))return _noRes();c.stock.pay(cost);c.army.recon++;break;
      default:cost=Resources(fuel:5,steel:10,money:14);if(!c.stock.canPay(cost))return _noRes();c.stock.pay(cost);c.army.navy++;
    }
    _log('تم تعزيز القوات: $type.');_sync();notifyListeners();
  }

  void decision(String kind){
    if(multiplayer?.isConnected==true){multiplayer!.sendGameAction('decision',value:kind);return;}
    final c=me;
    if(kind=='ration'){c.stock.food+=12;c.stock.water+=8;c.approval-=6;_log('تم تطبيق التقنين: المخزون تحسن لكن التأييد الشعبي انخفض.');}
    if(kind=='subsidy'){if(c.stock.money<12)return _noRes();c.stock.money-=12;c.approval+=8;_log('دعم السلع الأساسية رفع التأييد الشعبي.');}
    if(kind=='mobilize'){if(c.stock.money<10||c.stock.food<5)return _noRes();c.stock.money-=10;c.stock.food-=5;c.army.soldiers+=5;c.approval-=4;_log('تعبئة عامة: زاد الجيش لكن الضغط على المجتمع ارتفع.');}
    if(kind=='peace'){c.approval+=4;c.stability+=3;c.stock.money+=4;c.warExhaustion=max(0,c.warExhaustion-14);_log('خطاب سلام وخطة تهدئة حسّنا الاستقرار وخفّضا إرهاق الحرب.');}
    _sync();notifyListeners();
  }

  int techLevel(String tech)=>switch(tech){'agriculture'=>me.techAgriculture,'industry'=>me.techIndustry,'logistics'=>me.techLogistics,'armor'=>me.techArmor,'air'=>me.techAir,'intel'=>me.techIntel,_=>0};
  Resources researchCost(String tech){final l=techLevel(tech);return Resources(power:5+l*3,steel:5+l*4,money:16+l*10);}
  void research(String tech){
    if(multiplayer?.isConnected==true){multiplayer!.sendGameAction('research',value:tech);return;}
    final level=techLevel(tech);if(level>=5){_log('وصل هذا المجال إلى المستوى الأقصى.');return;}final cost=researchCost(tech);if(!me.stock.canPay(cost))return _noRes();if(!_spendCommand(2))return;me.stock.pay(cost);
    switch(tech){case'agriculture':me.techAgriculture++;break;case'industry':me.techIndustry++;break;case'logistics':me.techLogistics++;me.commandPoints=min(commandCap,me.commandPoints+1);break;case'armor':me.techArmor++;break;case'air':me.techAir++;break;case'intel':me.techIntel++;break;}
    _log('اكتمل بحث ${_techName(tech)} — المستوى ${level+1}.');_sync();notifyListeners();
  }
  String _techName(String tech)=>switch(tech){'agriculture'=>'الزراعة','industry'=>'الصناعة','logistics'=>'اللوجستيات','armor'=>'المدرعات','air'=>'الطيران','intel'=>'الاستخبارات',_=>tech};
  String occupationPolicyName(String p)=>switch(p){'security'=>'أمنية','autonomy'=>'حكم ذاتي','extraction'=>'استخراج مكثف',_=>'متوازنة'};
  void setOccupationPolicy(String countryId,String policy){
    final c=countries[countryId];if(c==null||!isMine(countryId)||!isOccupied(c)){_log('هذه السياسة مخصصة للأقاليم المحتلة التي تسيطر عليها.');return;}
    if(multiplayer?.isConnected==true){multiplayer!.sendGameAction('occupationPolicy',value:policy,target:countryId);return;}
    if(!_spendCommand(1))return;c.occupationPolicy=policy;_log('تم اعتماد سياسة ${occupationPolicyName(policy)} في ${c.name}.');notifyListeners();
  }
  void _maybeCreateEvent(){
    if(humanCountry==null||pendingEvents.isNotEmpty||rng.nextDouble()>.30)return;const kinds=['drought','protests','industrial','refugees'];final kind=kinds[rng.nextInt(kinds.length)];final title=kind=='drought'?'جفاف إقليمي':kind=='protests'?'موجة احتجاجات':kind=='industrial'?'حادث صناعي':'موجة نزوح';final desc=kind=='drought'?'انخفضت المحاصيل ومخزون المياه.':kind=='protests'?'الشارع يطالب بإصلاحات وتخفيف الضغوط.':kind=='industrial'?'توقف جزء من الإنتاج بعد حادث في منشأة صناعية.':'وصل مدنيون فارون من مناطق الصراع ويحتاجون قرارًا سريعًا.';events.add({'id':'E${DateTime.now().millisecondsSinceEpoch}','controller':me.controller,'kind':kind,'title':title,'description':desc,'turn':turn});_log('حدث داخلي جديد: $title.');
  }
  void resolveEvent(String eventId,String choice){
    if(multiplayer?.isConnected==true){multiplayer!.sendGameAction('resolveEvent',value:'$eventId|$choice');return;}
    Map<String,dynamic>? e;for(final x in events){if(x['id']==eventId&&x['controller']==me.controller&&x['status']!='resolved'){e=x;break;}}if(e==null)return;final c=me;final kind=e['kind'];String text='';
    if(kind=='drought'){if(choice=='import'){if(c.stock.money<14)return _noRes();c.stock.money-=14;c.stock.food+=18;c.stock.water+=14;text='استيراد الغذاء والمياه';}else{c.stock.food+=9;c.stock.water+=8;c.approval=max(0,c.approval-5);text='تقنين مؤقت';}}
    else if(kind=='protests'){if(choice=='reform'){if(c.stock.money<12)return _noRes();c.stock.money-=12;c.approval=min(100,c.approval+9);c.stability=min(100,c.stability+5);text='حزمة إصلاحات';}else{c.stability=min(100,c.stability+5);c.approval=max(0,c.approval-7);c.warExhaustion=min(100,c.warExhaustion+5);text='إجراء أمني';}}
    else if(kind=='industrial'){if(choice=='repair'){if(c.stock.steel<7||c.stock.money<8)return _noRes();c.stock.steel-=7;c.stock.money-=8;c.stability=min(100,c.stability+2);text='إصلاح سريع';}else{c.stock.power=max(0,c.stock.power-10);c.stock.steel=max(0,c.stock.steel-6);text='تأجيل الإصلاح';}}
    else if(kind=='refugees'){if(choice=='accept'){c.population+=2;c.stock.food=max(0,c.stock.food-8);c.approval=min(100,c.approval+3);text='استقبال النازحين';}else{c.approval=max(0,c.approval-3);c.stability=min(100,c.stability+2);text='تشديد الحدود';}}
    e['status']='resolved';e['choice']=choice;e['resolvedTurn']=turn;_log('تم حسم الحدث: $text.');notifyListeners();
  }

  void nextTurn(){
    if(multiplayer?.isConnected==true){multiplayer!.sendNextTurn();return;}
    if(humanCountry==null)return;turn++;
    final controllers=countries.values.map((c)=>c.controller).toSet();final bases=<String,Country>{};for(final ctrl in controllers){final b=controllerBase(ctrl);if(b!=null)bases[ctrl]=b;}
    for(final c in countries.values){
      final base=bases[c.controller]??c,agri=1+base.techAgriculture*.08,industry=1+base.techIndustry*.08,logistics=base.techLogistics;
      final popFactor=max(.5,c.population/50),factoryFactor=siteFactor(c.id,'factory').clamp(.2,1.0),powerFactor=siteFactor(c.id,'power').clamp(.2,1.0),supplyFactor=siteFactor(c.id,'supply').clamp(.25,1.0);
      c.stock.food+=(c.production.food+c.farms*4+c.foodFactories*2)*agri-3.5*popFactor;c.stock.water+=c.production.water*(1+base.techAgriculture*.035)-3*popFactor;c.stock.fuel+=c.production.fuel-1.4*popFactor;
      c.stock.power+=(c.production.power+c.solar*5+c.nuclear*14+c.grid*1.5)*powerFactor-2.2*popFactor;c.stock.steel+=(c.production.steel+c.civilianIndustry*2+c.militaryIndustry*2)*factoryFactor*industry;c.stock.money+=(c.production.money+c.civilianIndustry*5)*factoryFactor*industry;c.stock.gold+=max(.5,c.production.gold+c.civilianIndustry*.25);
      c.supply=min(100,c.supply+c.supplyHubs*(2.2+logistics*.45)*supplyFactor-(c.army.tanks*.35+c.army.artillery*.18+c.army.aircraft*.45+c.army.helicopters*.3+c.army.navy*.4));if(c.stock.fuel<8)c.supply=max(0,c.supply-7);
      final connected=c.controller.startsWith('P:')?isSupplyConnected(c.id):_supplyConnectedFor(c.controller,c.id);if(!connected){c.supply=max(0,c.supply-(10-logistics));c.stability=max(0,c.stability-2);}if(c.supply<35)c.morale=max(0,c.morale-5);else c.morale=min(100,c.morale+1);
      final shortage=c.stock.food<8||c.stock.water<8||c.stock.power<5||c.stock.fuel<3;if(shortage){c.approval=max(0,c.approval-5);c.stability=max(0,c.stability-3);}else{c.approval=min(100,c.approval+1.2);c.stability=min(100,c.stability+.7);}
      if(isOccupied(c)){
        var delta=(shortage?5:1.2)+(c.supply<35?3:0)-(c.stability>65&&c.approval>50?2.5:0);final policy=c.occupationPolicy;
        if(policy=='security'){delta-=3;base.stock.money=max(0,base.stock.money-2);c.stability=min(100,c.stability+1);}else if(policy=='autonomy'){delta-=4;c.approval=min(100,c.approval+1.5);base.approval=min(100,base.approval+.3);}else if(policy=='extraction'){delta+=5;final takeMoney=min(4,c.stock.money*.08),takeSteel=min(2,c.stock.steel*.06),takeFuel=min(2,c.stock.fuel*.05);c.stock.money-=takeMoney;c.stock.steel-=takeSteel;c.stock.fuel-=takeFuel;base.stock.money+=takeMoney;base.stock.steel+=takeSteel;base.stock.fuel+=takeFuel;}
        c.resistance=(c.resistance+delta).clamp(0,100).toDouble();base.warExhaustion=min(100,base.warExhaustion+.6);if(c.resistance>86&&rng.nextDouble()<.18){final old=c.controller;c.controller='AI:${c.id}';c.occupationPolicy='balanced';c.resistance=0;c.stability=38;c.approval=40;c.army.soldiers=max(3,c.army.soldiers);_log('انتفاضة في ${c.name}: المقاومة أطاحت بالاحتلال $old.');}
      }else c.resistance=max(0,c.resistance-4);
      c.stock.food=max(0,c.stock.food);c.stock.water=max(0,c.stock.water);c.stock.fuel=max(0,c.stock.fuel);c.stock.power=max(0,c.stock.power);c.stock.steel=max(0,c.stock.steel);c.stock.money=max(0,c.stock.money);c.stock.gold=max(0,c.stock.gold);
    }
    for(final p in provinces){final owner=countries[p.countryId];if(owner==null)continue;final connected=_provinceSupplyConnected(p),capacity=p.logisticsCapacity;p.weather=_nextWeather(rng,p.climate);if(!connected){p.supply=max(0,p.supply-(8.5-capacity*1.5));p.infrastructure=max(25,p.infrastructure-.4);}else{p.supply=min(100,p.supply+1.2+capacity*1.2+owner.techLogistics*.25);if(p.supply>60)p.infrastructure=min(95,p.infrastructure+.18);}if(p.resistance>70){p.infrastructure=max(20,p.infrastructure-.5);p.supply=max(0,p.supply-2);}if(p.garrison>0&&p.supply<25)p.garrison=max(0,p.garrison-(rng.nextDouble()<.15?1:0));}
    for(final entry in bases.entries){final ctrl=entry.key,base=entry.value;if(base.controller!=ctrl)continue;final owned=countries.values.where((c)=>c.controller==ctrl);final force=owned.fold<double>(0,(n,c)=>n+combatPower(base,c.army))+fieldArmies.where((a)=>a.owner==ctrl).fold<double>(0,(n,a)=>n+a.power);final upkeep=Resources(food:force*.018,fuel:force*.012,money:force*.055);if(base.stock.canPay(upkeep))base.stock.pay(upkeep);else{base.supply=max(0,base.supply-9);base.morale=max(0,base.morale-7);base.approval=max(0,base.approval-3);_log('${controllerRoot(ctrl)} يعاني عجزًا في صيانة القوات.');}base.warExhaustion=max(0,base.warExhaustion-2.5);base.airReadiness=(base.airReadiness-6).clamp(35,100).toDouble();base.fleetReadiness=(base.fleetReadiness-5).clamp(35,100).toDouble();if(base.warExhaustion>50){base.approval=max(0,base.approval-1.5);base.morale=max(0,base.morale-2);}if(base.warExhaustion>75){base.stability=max(0,base.stability-2);base.approval=max(0,base.approval-2);}base.commandPoints=(gamePace=='rapid'?8:gamePace=='grand'?5:6)+base.techLogistics;base.recruitedThisTurn=0;}
    for(final a in fieldArmies){final base=bases[a.owner];final logistics=base?.techLogistics??0,cut=!_supplyConnectedFor(a.owner,a.location);a.supply=max(0,a.supply-(cut?max(5,10-logistics):max(1,2-logistics*.15)));a.morale=max(0,min(100,a.morale+(a.supply<30?-4:1)-(cut?3:0)));}
    for(final tf in List<NavalTaskForce>.from(navalTaskForces)){final base=bases[tf.owner];if(base==null)continue;final missionDrain={'sea_control':3,'carrier_strike':3,'convoy_raid':2,'silent':2}[tf.mission]??0,cost=Resources(fuel:max(1.0,tf.units*.8),money:max(1.0,tf.units*.65));if(base.stock.canPay(cost))base.stock.pay(cost);else{tf.supply=max(0.0,tf.supply-8);tf.readiness=max(0.0,tf.readiness-7);}if(_fleetCanResupply(tf)){tf.supply=min(100.0,tf.supply+10-missionDrain);tf.readiness=min(100.0,tf.readiness+5-missionDrain);}else{tf.supply=max(0.0,tf.supply-5-missionDrain);tf.readiness=max(0.0,tf.readiness-3-missionDrain);}if(tf.supply<12&&rng.nextDouble()<.12){if(tf.surface>0)tf.surface--;else if(tf.submarines>0)tf.submarines--;_log('${tf.name}: ${tr('خسارة بسبب انهيار الإمداد','loss from supply collapse')}.');}}
    navalTaskForces.removeWhere((x)=>x.units<=0);
    for(final b in activeBattles){if(countries[b.source]?.controller!=b.attacker||countries[b.target]?.controller!=b.defender)b.status='stale';}
    _aiTurn();_maybeCreateEvent();if(me.approval<35)_log('تحذير: نقمة شعبية حادة. حسّن الأساسيات أو استخدم قرارات حكومية.');_updateLocalOutcome();_sync();notifyListeners();unawaited(saveLocal());
  }

  bool _supplyConnectedFor(String controller,String countryId){final target=countries[countryId];if(target?.controller!=controller)return false;var root=controllerRoot(controller);if(countries[root]?.controller!=controller){root=countries.values.firstWhere((c)=>c.controller==controller,orElse:()=>target!).id;}if(root==countryId)return true;final seen=<String>{root},queue=<String>[root];while(queue.isNotEmpty){final cur=queue.removeAt(0);for(final n in _supplyNeighbors(controller,cur)){if(seen.contains(n)||countries[n]?.controller!=controller)continue;if(n==countryId)return true;seen.add(n);queue.add(n);}}return false;}
  bool _provinceSupplyConnected(Province p){final host=countries[p.countryId];if(host==null)return false;if(host.controller==p.controller)return _supplyConnectedFor(p.controller,p.countryId);for(final n in host.neighbors){if(countries[n]?.controller==p.controller&&_supplyConnectedFor(p.controller,n))return true;}for(final n in countries.keys.where((x)=>x!=p.countryId&&isSeaLane(p.countryId,x))){if(countries[n]?.controller==p.controller&&_supplyConnectedFor(p.controller,n))return true;}return false;}


  void _aiNavalTurn(Country c,String ctrl,int profile){
    final root=controllerRoot(ctrl),coastal=countries.values.where((x)=>x.controller==ctrl&&seaZonesForCountry(x.id).isNotEmpty&&siteFactor(x.id,'port')>.25).toList();if(coastal.isEmpty)return;
    if(c.carrierStock<1&&profile!=1&&rng.nextDouble()<.08){final cost=Resources(fuel:10,power:7,steel:28,money:42);if(c.stock.canPay(cost)){c.stock.pay(cost);c.carrierStock++;_log('AI $root: ${tr('دشنت حاملة طائرات','commissioned an aircraft carrier')}.');}}
    if(c.submarineStock<1&&rng.nextDouble()<.12){final cost=Resources(fuel:6,power:5,steel:18,money:28);if(c.stock.canPay(cost)){c.stock.pay(cost);c.submarineStock++;_log('AI $root: ${tr('دشنت غواصة','commissioned a submarine')}.');}}
    var own=navalTaskForces.where((x)=>x.owner==ctrl).toList();
    if(own.isEmpty&&c.commandPoints>=1&&(c.army.navy>0||c.carrierStock>0||c.submarineStock>0)){
      final source=coastal.first,zones=seaZonesForCountry(source.id);if(zones.isNotEmpty){final zone=zones.first,surface=c.army.navy>0?1:0,carriers=surface>0&&c.carrierStock>0&&profile!=1?1:0,submarines=c.submarineStock>0&&(carriers==0||rng.nextDouble()<.45)?1:0,fuel=4+surface+carriers*2+submarines;if(surface+carriers+submarines>0&&c.stock.fuel>=fuel){c.commandPoints--;c.stock.fuel-=fuel;c.army.navy=max(0,c.army.navy-surface);c.carrierStock=max(0,c.carrierStock-carriers);c.submarineStock=max(0,c.submarineStock-submarines);final tf=NavalTaskForce(id:'AITF${DateTime.now().millisecondsSinceEpoch}${rng.nextInt(9999)}',name:'$root Fleet',owner:ctrl,homeCountry:source.id,zoneId:zone,mission:carriers>0?'carrier_strike':submarines>0&&surface==0?'silent':'sea_control',surface:surface,carriers:carriers,submarines:submarines,createdTurn:turn,readiness:86,supply:88);navalTaskForces.add(tf);own=[tf];_log('AI $root: ${tr('نشر قوة بحرية في','deployed a task force to')} ${seaZoneName(zone)}.');}}
    }
    for(final tf in List<NavalTaskForce>.from(own)){
      NavalTaskForce? enemy;for(final e in navalTaskForces){if(e.owner==ctrl||e.zoneId!=tf.zoneId)continue;final allied=alliances.contains(_allianceKey(root,controllerRoot(e.owner)));if(!allied){enemy=e;break;}}
      if(enemy!=null&&c.commandPoints>=2){c.commandPoints-=2;final d=enemy!,edge=((tf.power-d.power)/max(1,tf.power+d.power)+(rng.nextDouble()*2-1)*.12).clamp(-1.0,1.0).toDouble(),aLoss=(.08-edge*.12).clamp(.025,.24).toDouble(),dLoss=(.08+edge*.12).clamp(.025,.24).toDouble();int loss(int n,double sev,double bias)=>min(n,(n*sev+bias).floor()).toInt();tf.surface-=loss(tf.surface,aLoss,.35);tf.carriers-=loss(tf.carriers,aLoss*.55,.08);tf.submarines-=loss(tf.submarines,aLoss*.75,.16);d.surface-=loss(d.surface,dLoss,.35);d.carriers-=loss(d.carriers,dLoss*.55,.08);d.submarines-=loss(d.submarines,dLoss*.75,.16);tf.readiness=max(0.0,tf.readiness-8);d.readiness=max(0.0,d.readiness-9);tf.supply=max(0.0,tf.supply-7);d.supply=max(0.0,d.supply-8);_log('AI $root: ${tr('اشتباك بحري في','naval engagement in')} ${seaZoneName(tf.zoneId)}.');continue;}
      if(c.commandPoints>=1&&c.stock.fuel>=3&&rng.nextDouble()<.22){final adj=adjacentSeaZones(tf.zoneId);if(adj.isNotEmpty){String? next;for(final z in adj){if(navalTaskForces.any((e)=>e.owner!=ctrl&&e.zoneId==z&&!alliances.contains(_allianceKey(root,controllerRoot(e.owner))))){next=z;break;}}final destination=next??adj[rng.nextInt(adj.length)],fuel=max(3,tf.units*2).toDouble();if(c.stock.fuel>=fuel){c.commandPoints--;c.stock.fuel-=fuel;tf.zoneId=destination;tf.supply=max(0.0,tf.supply-8);tf.readiness=max(0.0,tf.readiness-5);}}}
    }
    navalTaskForces.removeWhere((x)=>x.units<=0);
  }

  void _aiTurn(){
    final controllers=countries.values.map((c)=>c.controller).where((x)=>x.startsWith('AI:')).toSet().toList()..shuffle(rng);
    for(final ctrl in controllers){final c=controllerBase(ctrl);if(c==null)continue;final root=controllerRoot(ctrl),profile=(root.codeUnitAt(0)+root.codeUnitAt(root.length-1))%3;
      if((profile==2||rng.nextDouble()<.16)&&c.commandPoints>=2){final levels=<String,int>{'agriculture':c.techAgriculture,'industry':c.techIndustry,'logistics':c.techLogistics,'armor':c.techArmor,'air':c.techAir,'intel':c.techIntel};final tech=(levels.entries.toList()..sort((a,b)=>a.value.compareTo(b.value))).first;if(tech.value<5){final cost=Resources(power:4+tech.value*2,steel:4+tech.value*3,money:14+tech.value*8);if(c.stock.canPay(cost)){c.stock.pay(cost);c.commandPoints-=2;switch(tech.key){case'agriculture':c.techAgriculture++;break;case'industry':c.techIndustry++;break;case'logistics':c.techLogistics++;break;case'armor':c.techArmor++;break;case'air':c.techAir++;break;case'intel':c.techIntel++;break;}}}}
      if(profile==1&&rng.nextDouble()<.5&&c.stock.money>=12&&c.stock.steel>=7){c.stock.money-=12;c.stock.steel-=7;c.civilianIndustry++;}else if(c.stock.food>=3&&c.stock.money>=5&&rng.nextDouble()<.7){c.stock.food-=3;c.stock.money-=5;c.army.soldiers+=3;}if((profile==0||rng.nextDouble()<.25)&&c.stock.steel>=8&&c.stock.money>=10){c.stock.steel-=8;c.stock.money-=10;c.army.tanks++;}
      _aiNavalTurn(c,ctrl,profile);
      final fronts=<({Country source,Country target})>[];for(final source in countries.values.where((x)=>x.controller==ctrl)){for(final n in source.neighbors){final t=countries[n];if(t!=null&&t.controller!=ctrl&&!areAllies(source.id,t.id))fronts.add((source:source,target:t));}}if(fronts.isEmpty||c.commandPoints<2||c.stock.fuel<5||c.stock.food<4)continue;fronts.sort((a,b)=>combatPower(a.target,a.target.army).compareTo(combatPower(b.target,b.target.army)));final f=fronts.first,confidence=(combatPower(c,c.army)/max(1,combatPower(f.target,f.target.army)))*aiMultiplier,chance=(profile==0?0.45:profile==2?0.25:0.18)*aiMultiplier;if(confidence<.82||rng.nextDouble()>chance)continue;final plan=profile==0?'breakthrough':confidence<1.15?'cautious':'balanced',cp=attackPlanCommand(plan),cost=attackCost(f.source,plan:plan);if(c.commandPoints<cp||!c.stock.canPay(cost))continue;c.commandPoints-=cp;c.stock.pay(cost);var battle=battleFor(f.source.id,f.target.id,ctrl);if(battle!=null&&battle.defender!=f.target.controller){battle.status='stale';battle=null;}battle??=FrontBattle(id:'B${DateTime.now().millisecondsSinceEpoch}${rng.nextInt(999)}',source:f.source.id,target:f.target.id,attacker:ctrl,defender:f.target.controller,plan:plan,startedTurn:turn,attackerArmyIds:availableBattleArmies(f.source.id,ctrl).map((a)=>a.id).toList(),defenderArmyIds:availableBattleArmies(f.target.id,f.target.controller).map((a)=>a.id).toList());if(!battles.contains(battle))battles.add(battle);final result=_resolveLocalBattleRound(battle,c,f.source,f.target,plan);if(battle.progress>=100)_captureLocalBattle(battle,c,f.source,f.target);else _log('AI $root ضغط على جبهة ${f.target.name}: ${battle.progress.toStringAsFixed(0)}% (${result.delta>=0?'+':''}${result.delta.toStringAsFixed(0)}).');
    }
  }

  void _updateLocalOutcome(){
    final controllers=countries.values.map((c)=>c.controller).toSet();
    if(controllers.length==1&&controllers.first.startsWith('P:')){winnerController=controllers.first;victoryType='domination';return;}
    if(turn<hegemonyStartTurn||winnerController!=null)return;final mine=me.controller,territories=countries.values.where((c)=>c.controller==mine).length;if(territories<(countries.length*.55).ceil())return;final ranked=leaderboard;if(ranked.isNotEmpty&&ranked.first.key==mine){final second=ranked.length>1?ranked[1].value:1.0;if(ranked.first.value>=second*1.25){winnerController=mine;victoryType='hegemony';_log('حققت نصر الهيمنة: أكثر من 55% من العالم مع تفوق واضح في القوة الشاملة.');}}
  }

  void _log(String s){logs.insert(0,'الدور $turn — $s');if(logs.length>80)logs.removeLast();notifyListeners();}

  Map<String,dynamic> snapshot()=>{'turn':turn,'aiDifficulty':aiDifficulty,'battleMode':battleMode,'appLanguage':appLanguage,'gamePace':gamePace,'humanCountry':humanCountry,'selected':selected,'winner':winnerController,'victoryType':victoryType,'alliances':alliances.toList(),'sanctions':sanctions.toList(),'tradeDeals':tradeDeals,'diplomaticOffers':diplomaticOffers,'events':events,'countries':countries.map((k,v)=>MapEntry(k,v.toJson())),'logs':logs.take(40).toList(),'fieldArmies':fieldArmies.map((a)=>a.toJson()).toList(),'navalTaskForces':navalTaskForces.map((a)=>a.toJson()).toList(),'provinces':provinces.map((p)=>p.toJson()).toList(),'battles':battles.map((b)=>b.toJson()).toList(),'strategicSites':strategicSites.map((x)=>x.toJson()).toList()};
  void applySnapshot(Map<String,dynamic> j){turn=j['turn']??turn;aiDifficulty=j['aiDifficulty']?.toString()??aiDifficulty;battleMode=j['battleMode']?.toString()??battleMode;appLanguage=j['appLanguage']?.toString()??appLanguage;gamePace=j['gamePace']?.toString()??gamePace;winnerController=j['winner']?.toString();victoryType=j['victoryType']?.toString();final map=Map<String,dynamic>.from(j['countries']??{});for(final e in map.entries){if(countries.containsKey(e.key))countries[e.key]!.applyJson(Map<String,dynamic>.from(e.value));}alliances..clear()..addAll(List<String>.from(j['alliances']??[]));sanctions..clear()..addAll(List<String>.from(j['sanctions']??[]));tradeDeals..clear()..addAll(List<String>.from(j['tradeDeals']??[]));diplomaticOffers..clear();for(final raw in (j['diplomaticOffers']??[])){if(raw is Map)diplomaticOffers.add(Map<String,dynamic>.from(raw));}events..clear();for(final raw in (j['events']??[])){if(raw is Map)events.add(Map<String,dynamic>.from(raw));}logs..clear()..addAll(List<String>.from(j['logs']??[]));fieldArmies..clear();for(final raw in (j['fieldArmies']??[])){if(raw is Map)fieldArmies.add(FieldArmy.fromJson(Map<String,dynamic>.from(raw)));}navalTaskForces..clear();for(final raw in (j['navalTaskForces']??[])){if(raw is Map)navalTaskForces.add(NavalTaskForce.fromJson(Map<String,dynamic>.from(raw)));}provinces..clear();for(final raw in (j['provinces']??[])){if(raw is Map)provinces.add(Province.fromJson(Map<String,dynamic>.from(raw)));}battles..clear();for(final raw in (j['battles']??[])){if(raw is Map)battles.add(FrontBattle.fromJson(Map<String,dynamic>.from(raw)));}if(j.containsKey('strategicSites')){strategicSites..clear();for(final raw in (j['strategicSites']??[])){if(raw is Map)strategicSites.add(StrategicSite.fromJson(Map<String,dynamic>.from(raw)));}}notifyListeners();}
  Future<void> saveLocal() async {
    if(humanCountry==null||multiplayer?.isConnected==true)return;
    final prefs=await SharedPreferences.getInstance();await prefs.setString('world_dominion_local_v1',jsonEncode(snapshot()));_log('تم حفظ المباراة المحلية على الجهاز.');
  }
  Future<bool> loadLocal() async {
    final prefs=await SharedPreferences.getInstance();final raw=prefs.getString('world_dominion_local_v1')??prefs.getString('world_dominion_local_v07');if(raw==null)return false;
    try{final j=Map<String,dynamic>.from(jsonDecode(raw));final hc=j['humanCountry']?.toString();if(hc==null||!countries.containsKey(hc))return false;humanCountry=hc;selected=(j['selected']?.toString()!=null&&countries.containsKey(j['selected']?.toString()))?j['selected'].toString():hc;applySnapshot(j);logs.insert(0,'تم استعادة آخر مباراة محلية.');notifyListeners();return true;}catch(_){return false;}
  }

  void attachMultiplayer(MultiplayerClient client){
    multiplayer=client;
    client.onSnapshot=(j)=>applySnapshot(j);
    client.onLobby=(owners,players){
      onlineCountryOwners..clear()..addAll(owners);onlinePlayers..clear()..addAll(players);gamePace=client.roomPace;
      if(client.roomStatus=='lobby'){for(final c in countries.values)c.controller='AI:${c.id}';for(final id in owners.keys){if(countries.containsKey(id))countries[id]!.controller='P:$id';}}
      for(final p in players){if(p['id']?.toString()==client.playerId&&p['country']!=null){humanCountry=p['country'].toString();if(countries.containsKey(humanCountry))selected=humanCountry!;break;}}
      notifyListeners();
    };
    client.onConnectionChanged=notifyListeners;
  }
  void leaveOnlineSession(){
    multiplayer?.close();multiplayer=null;onlineCountryOwners.clear();onlinePlayers.clear();humanCountry=null;winnerController=null;victoryType=null;selected='FRA';events.clear();countries=_seedCountries();provinces.clear();_seedFallbackProvinces();strategicSites..clear()..addAll(_seedStrategicSites(countries));fieldArmies.clear();battles.clear();logs..clear()..add('اختر دولتك وابدأ بناء قوتك.');notifyListeners();
  }
  void _sync(){
    // In online games the server is authoritative; client snapshots are never uploaded.
  }
}

Map<String,Country> _seedCountries(){
  const coastal={'ARE','ARG','AUS','BGD','BRA','CAN','CHN','DZA','EGY','ESP','FRA','GBR','GEO','IDN','IND','IRN','ISR','ITA','JPN','KOR','LBN','MAR','MEX','MMR','MYS','OMN','PAK','PRK','SAU','SYR','THA','TUR','USA','YEM'};
  Country c(String id,String n,double x,double y,List<String> nb,{String capital='العاصمة',double pop=45,double food=10,double water=9,double fuel=5,double power=7,double steel=4,double money=8}){
    final int soldiers=(6+min(32,(sqrt(pop)*1.2).round())).toInt();
    final int tanks=max(1,min(5,((steel+money)/10).round())).toInt();
    final int aircraft=max(1,min(4,((power+money)/12).round())).toInt();
    final int navy=coastal.contains(id)?max(1,min(3,((fuel+money)/14).round())).toInt():0;
    return Country(id:id,name:n,capital:capital,pos:Offset(x,y),neighbors:nb,controller:'AI:$id',population:pop,stock:Resources(food:75+food*2,water:75+water*2,fuel:55+fuel*2,power:65+power*2,steel:45+steel*2,money:70+money*2),production:Resources(food:food,water:water,fuel:fuel,power:power,steel:steel,money:money),army:Army(soldiers:soldiers,tanks:tanks,artillery:max(1,tanks-1).toInt(),airDefense:max(1,(aircraft/2).ceil()).toInt(),aircraft:aircraft,helicopters:aircraft>=3?1:0,drones:1,recon:1,navy:navy));
  }
  final list=<Country>[
    c('USA','الولايات المتحدة',.15,.30,['CAN','MEX'],capital:'واشنطن',pop:335,fuel:12,power:15,steel:10,money:18),
    c('CAN','كندا',.15,.16,['USA'],pop:40,water:15,fuel:10),
    c('MEX','المكسيك',.16,.43,['USA','BRA'],pop:129,food:13),
    c('BRA','البرازيل',.28,.68,['MEX','ARG'],pop:216,food:18,water:13),
    c('ARG','الأرجنتين',.28,.84,['BRA'],pop:46,food:16),
    c('GBR','بريطانيا',.45,.23,['FRA','DEU'],pop:68,money:12),
    c('FRA','فرنسا',.46,.34,['GBR','ESP','DEU','ITA'],capital:'باريس',pop:68,food:12,power:10,money:12),
    c('ESP','إسبانيا',.42,.43,['FRA','MAR','ITA'],pop:48),
    c('DEU','ألمانيا',.52,.29,['FRA','GBR','POL','ITA'],pop:84,steel:10,money:14),
    c('ITA','إيطاليا',.53,.40,['FRA','ESP','DEU','GRC'],pop:59),
    c('POL','بولندا',.58,.27,['DEU','UKR'],pop:38,steel:7),
    c('UKR','أوكرانيا',.63,.31,['POL','RUS','TUR'],pop:37,food:16),
    c('RUS','روسيا',.72,.20,['UKR','TUR','KAZ','CHN'],pop:146,fuel:18,steel:12,power:11),
    c('MAR','المغرب',.43,.53,['ESP','DZA'],pop:38),
    c('DZA','الجزائر',.49,.56,['MAR','EGY'],pop:46,fuel:14),
    c('EGY','مصر',.58,.55,['DZA','ISR','SAU'],pop:112,food:9),
    c('GRC','اليونان',.58,.43,['ITA','TUR'],pop:10),
    c('TUR','تركيا',.63,.43,['GRC','UKR','RUS','GEO','SYR','IRQ'],capital:'أنقرة',pop:86,food:12,steel:7),
    c('GEO','جورجيا',.67,.38,['TUR','RUS'],pop:4),
    c('SYR','سوريا',.65,.49,['TUR','IRQ','LBN','JOR'],pop:23),
    c('LBN','لبنان',.64,.53,['SYR','ISR'],capital:'بيروت',pop:6,money:6),
    c('ISR','إسرائيل',.63,.57,['LBN','EGY','JOR'],pop:10,power:9,money:11),
    c('JOR','الأردن',.66,.58,['SYR','ISR','IRQ','SAU'],pop:11,water:4),
    c('IRQ','العراق',.70,.51,['TUR','SYR','JOR','SAU','IRN'],pop:46,fuel:15),
    c('SAU','السعودية',.69,.64,['EGY','JOR','IRQ','YEM','ARE'],pop:37,fuel:20,money:14),
    c('YEM','اليمن',.70,.74,['SAU','OMN'],pop:34),
    c('ARE','الإمارات',.75,.64,['SAU','OMN'],pop:10,fuel:14,money:16),
    c('OMN','عُمان',.77,.70,['ARE','YEM'],pop:5,fuel:11),
    c('IRN','إيران',.75,.49,['IRQ','TUR','AFG','PAK'],pop:89,fuel:16,steel:8),
    c('AFG','أفغانستان',.80,.45,['IRN','PAK','CHN'],pop:43),
    c('PAK','باكستان',.81,.55,['IRN','AFG','IND'],pop:241),
    c('IND','الهند',.86,.58,['PAK','CHN','BGD'],pop:1420,food:15,steel:9),
    c('BGD','بنغلادش',.90,.60,['IND','MMR'],pop:173),
    c('CHN','الصين',.88,.35,['RUS','KAZ','AFG','IND','MNG','PRK'],capital:'بكين',pop:1410,steel:16,power:15,money:14),
    c('KAZ','كازاخستان',.79,.31,['RUS','CHN'],pop:20,fuel:13),
    c('MNG','منغوليا',.89,.24,['CHN','RUS'],pop:3,steel:8),
    c('PRK','كوريا الشمالية',.95,.34,['CHN','KOR'],pop:26),
    c('KOR','كوريا الجنوبية',.96,.40,['PRK','JPN'],pop:52,power:12,money:15),
    c('JPN','اليابان',.98,.44,['KOR'],pop:124,power:12,money:16),
    c('MMR','ميانمار',.93,.64,['BGD','THA'],pop:55),
    c('THA','تايلاند',.95,.70,['MMR','MYS'],pop:72,food:13),
    c('MYS','ماليزيا',.96,.77,['THA','IDN'],pop:34,fuel:8),
    c('IDN','إندونيسيا',.94,.86,['MYS','AUS'],pop:279,food:12,fuel:9),
    c('AUS','أستراليا',.90,.91,['IDN'],pop:27,food:14,steel:12),
  ];
  return {for(final x in list)x.id:x};
}


List<StrategicSite> _seedStrategicSites(Map<String,Country> countries){
  final out=<StrategicSite>[];
  const coastal={'USA','CAN','MEX','BRA','ARG','GBR','FRA','ESP','ITA','MAR','DZA','EGY','TUR','GEO','SYR','LBN','ISR','SAU','YEM','ARE','OMN','IRN','PAK','IND','BGD','CHN','PRK','KOR','JPN','MMR','THA','MYS','IDN','AUS'};
  for(final c in countries.values){
    out.add(StrategicSite(id:'${c.id}_CAP',countryId:c.id,name:c.capital,kind:'capital',offset:Offset.zero));
    out.add(StrategicSite(id:'${c.id}_FAC',countryId:c.id,name:'المجمع الصناعي',kind:'factory',offset:const Offset(.010,.014)));
    out.add(StrategicSite(id:'${c.id}_PWR',countryId:c.id,name:'محطة الطاقة',kind:'power',offset:const Offset(-.012,.012)));
    out.add(StrategicSite(id:'${c.id}_SUP',countryId:c.id,name:'مركز الإمداد',kind:'supply',offset:const Offset(.012,-.014)));
    if(c.army.aircraft>0)out.add(StrategicSite(id:'${c.id}_AIR',countryId:c.id,name:'القاعدة الجوية',kind:'airport',offset:const Offset(-.013,-.014)));
    if(coastal.contains(c.id))out.add(StrategicSite(id:'${c.id}_PRT',countryId:c.id,name:'الميناء الرئيسي',kind:'port',offset:const Offset(.020,.002)));
  }
  return out;
}

class MultiplayerClient {
  WebSocket? _ws;
  Timer? _heartbeat;
  Completer<bool>? _claimCompleter;
  Completer<bool>? _attackCompleter;
  Completer<void>? _joinCompleter;
  final Map<String,Completer<bool>> _actionCompleters={};
  void Function(Map<String,dynamic>)? onSnapshot;
  void Function(Map<String,String>,List<Map<String,dynamic>>)? onLobby;
  void Function(String)? onStatus;
  VoidCallback? onConnectionChanged;
  String playerId='';
  String resumeToken='';
  String roomCode='';
  String serverUrl='';
  String hostPlayerId='';
  String roomStatus='';
  String serverVersion='';String serverRuleset='';
  String roomPace='campaign';
  String playerName='لاعب';
  final Set<String> blockedPlayerIds=<String>{};
  bool ready=false;
  bool turnReady=false;
  int? turnDeadline;
  int revision=0;
  bool serverHasSnapshot=false;
  SharedPreferences? _prefs;
  String _credentialKey='';
  String installationId='';
  bool get isHost=>playerId.isNotEmpty&&playerId==hostPlayerId;
  bool get isConnected=>_ws?.readyState==WebSocket.open;
  bool get inLobby=>isConnected&&roomStatus=='lobby';
  bool get isRunning=>isConnected&&roomStatus=='running';

  String _normalizeUrl(String raw){
    var v=raw.trim();if(v.startsWith('https://'))v='wss://${v.substring(8)}';if(v.startsWith('http://'))v='ws://${v.substring(7)}';return v;
  }
  bool _isLocalHost(String host)=>host=='localhost'||host=='127.0.0.1'||host=='10.0.2.2'||host=='::1';

  Future<void> connect(String url,String room,{String name='لاعب',String mode='join',String password=''}) async {
    playerName=name.trim().isEmpty?'لاعب':name.trim();serverUrl=_normalizeUrl(url);final cleanRoom=room.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9_-]'),'');roomCode=cleanRoom.substring(0,min(16,cleanRoom.length));
    if(roomCode.length<4)throw Exception('رمز الغرفة يجب أن يكون 4 أحرف على الأقل');
    final uri=Uri.tryParse(serverUrl);if(uri==null||!(uri.scheme=='ws'||uri.scheme=='wss')||uri.host.isEmpty)throw Exception('عنوان WebSocket غير صالح');
    if(uri.scheme=='ws'&&!kAllowInsecureWs&&!_isLocalHost(uri.host))throw Exception('في إصدار الإنتاج استخدم wss:// لاتصال مشفّر');
    _prefs=await SharedPreferences.getInstance();
    installationId=_prefs!.getString('wd_installation_id_v1')??'';
    if(installationId.isEmpty){final secure=Random.secure();installationId=base64UrlEncode(List<int>.generate(24,(_)=>secure.nextInt(256)));await _prefs!.setString('wd_installation_id_v1',installationId);}
    _credentialKey='wd_${serverUrl}_$roomCode';
    blockedPlayerIds..clear()..addAll(_prefs!.getStringList('${_credentialKey}_blocked')??const <String>[]);
    playerId=_prefs!.getString('${_credentialKey}_player')??'';
    resumeToken=_prefs!.getString('${_credentialKey}_token')??'';
    try{
      _joinCompleter=Completer<void>();
      _ws=await WebSocket.connect(serverUrl,compression:CompressionOptions.compressionDefault);
      _ws!.listen((raw) async {
        final m=jsonDecode(raw as String);final type=m['type']?.toString()??'';
        if(type=='joined'){
          playerId=m['playerId']?.toString()??playerId;resumeToken=m['resumeToken']?.toString()??resumeToken;
          await _prefs!.setString('${_credentialKey}_player',playerId);await _prefs!.setString('${_credentialKey}_token',resumeToken);
          revision=(m['revision']??0) as int;hostPlayerId=m['hostPlayerId']?.toString()??'';roomStatus=m['status']?.toString()??'';serverVersion=m['serverVersion']?.toString()??'';serverRuleset=m['ruleset']?.toString()??'';roomPace=m['pace']?.toString()??roomPace;turnDeadline=(m['turnDeadline'] as num?)?.toInt();serverHasSnapshot=m['snapshot']!=null;
          _applyLobby(m['countryOwners'],m['players']);if(m['snapshot']!=null)onSnapshot?.call(Map<String,dynamic>.from(m['snapshot']));if(_joinCompleter!=null&&!_joinCompleter!.isCompleted)_joinCompleter!.complete();onConnectionChanged?.call();
        }
        if(type=='lobby'){
          revision=(m['revision']??revision) as int;hostPlayerId=m['hostPlayerId']?.toString()??hostPlayerId;roomStatus=m['status']?.toString()??roomStatus;roomPace=m['pace']?.toString()??roomPace;turnDeadline=(m['turnDeadline'] as num?)?.toInt();_applyLobby(m['countryOwners'],m['players']);onConnectionChanged?.call();
        }
        if(type=='sync'&&m['snapshot']!=null){revision=(m['revision']??revision) as int;serverHasSnapshot=true;onSnapshot?.call(Map<String,dynamic>.from(m['snapshot']));}
        if(type=='actionResult'){
          final action=m['action']?.toString()??'';final ok=m['ok']==true;
          if(action=='attack'&&_attackCompleter!=null&&!_attackCompleter!.isCompleted)_attackCompleter!.complete(ok);
          final c=_actionCompleters.remove(action);if(c!=null&&!c.isCompleted)c.complete(ok);
          if(!ok)onStatus?.call(_friendlyReason(m['reason']?.toString()??action));
          if(action=='spy'&&m['success']==true&&m['intel']!=null)onStatus?.call('نجح التجسس: قوة ${m['intel']['power']} • وقود ${m['intel']['fuel']}');
        }
        if(type=='claimResult'){final ok=m['ok']==true;if(_claimCompleter!=null&&!_claimCompleter!.isCompleted)_claimCompleter!.complete(ok);if(!ok)onStatus?.call(_friendlyReason(m['reason']?.toString()??'claim'));}
        if(type=='dataDeleted'){await clearLocalIdentity();onStatus?.call('تم حذف هوية هذه الغرفة من السيرفر والجهاز.');}
        if(type=='error'){final reason=_friendlyReason(m['code']?.toString()??m['message']?.toString()??'server_error');onStatus?.call(reason);if(_joinCompleter!=null&&!_joinCompleter!.isCompleted){_joinCompleter!.completeError(Exception(reason));_ws?.close();}}
      },onDone:(){_heartbeat?.cancel();if(_joinCompleter!=null&&!_joinCompleter!.isCompleted)_joinCompleter!.completeError(Exception('انقطع الاتصال قبل اكتمال الانضمام'));onStatus?.call('انقطع الاتصال — أعد الاتصال بنفس الغرفة لاستعادة دولتك');onConnectionChanged?.call();},onError:(e){if(_joinCompleter!=null&&!_joinCompleter!.isCompleted)_joinCompleter!.completeError(e);onStatus?.call('خطأ اتصال: $e');onConnectionChanged?.call();});
      _ws!.add(jsonEncode({'type':'join','protocol':kProtocolVersion,'ruleset':kRulesetVersion,'clientVersion':kAppVersion,'mode':mode,'password':password,'room':roomCode,'playerId':playerId,'resumeToken':resumeToken,'name':playerName,'installId':installationId}));
      await _joinCompleter!.future.timeout(const Duration(seconds:10));
      _heartbeat?.cancel();_heartbeat=Timer.periodic(const Duration(seconds:25),(_){if(isConnected)_ws!.add(jsonEncode({'type':'heartbeat'}));});onStatus?.call('متصل بالغرفة.');onConnectionChanged?.call();
    }catch(e){onStatus?.call('فشل الاتصال: $e');onConnectionChanged?.call();rethrow;}
  }
  String _friendlyReason(String r){const map={'room_exists':'الغرفة موجودة بالفعل. اختر انضمام أو غيّر الرمز.','room_not_found':'الغرفة غير موجودة.','bad_password':'كلمة مرور الغرفة غير صحيحة.','game_started':'المباراة بدأت بالفعل ولا تقبل لاعبين جددًا.','players_not_ready':'ليس كل اللاعبين جاهزين.','not_enough_players':'عدد اللاعبين غير كافٍ.','host_only':'هذا الإجراء للمضيف فقط.','already_ready':'لقد أنهيت دورك بالفعل.','game_not_running':'المباراة لم تبدأ بعد.','protocol_mismatch':'نسخة التطبيق لا تتوافق مع السيرفر.','ruleset_mismatch':'قواعد اللعب في التطبيق لا تتطابق مع السيرفر. حدّث التطبيق والسيرفر معًا.','country_taken':'هذه الدولة محجوزة.','resources':'الموارد غير كافية.','command_points':'نقاط القيادة غير كافية لهذا الدور.','tech_max':'وصل البحث إلى المستوى الأقصى.','event_not_found':'هذا الحدث حُسم أو لم يعد متاحًا.','invalid_policy':'سياسة الاحتلال غير صالحة لهذا الإقليم.','invalid_tech':'مجال البحث غير صالح.','naval_required':'الغزو البرمائي يحتاج أسطولاً وميناءً صالحًا في إقليم الانطلاق.','battle_not_found':'المعركة لم تعد نشطة أو غير موجودة.','battle_not_owned':'هذه الجبهة لا تخص قواتك.','army_engaged':'الجيش مرتبط بمعركة نشطة.','army_wrong_front':'الجيش ليس موجودًا في موقع الجبهة.','invalid_retreat':'لا يوجد مسار انسحاب صالح.','kicked':'قام مضيف الغرفة بإزالتك.','server_capacity':'السيرفر وصل إلى الحد الأقصى للغرف حالياً.','banned':'تم حظر هذا التثبيت من الخدمة بسبب إساءة استخدام. تواصل مع الدعم إذا كان ذلك خطأ.','air_range':'الهدف خارج مدى الطيران من القواعد الحالية.','missile_range':'الهدف خارج مدى الصواريخ الحالية.','missiles':'لا توجد صواريخ جاهزة.','missile_program_required':'أنشئ برنامجًا صاروخيًا أولاً.','province_not_owned':'هذه المحافظة ليست تحت سيطرتك.','invalid_infrastructure':'نوع تطوير البنية غير صالح.','infrastructure_max':'هذا التطوير وصل إلى المستوى الأقصى.','invalid_sea_zone':'لا يمكن نشر الأسطول في هذه المنطقة من الميناء المختار.','invalid_fleet':'تشكيل القوة البحرية غير صالح.','fleet_not_owned':'هذه القوة البحرية لا تتبع لك.','sea_zone_not_adjacent':'المنطقة البحرية ليست مجاورة لمسار الأسطول.','invalid_mission':'المهمة البحرية غير صالحة.','training_capacity':'وصلت قدرة التدريب لهذا الدور إلى الحد الأقصى.'};return map[r]??'رفض السيرفر الإجراء: $r';}
  void _applyLobby(dynamic raw,dynamic playersRaw){
    final owners=<String,String>{};if(raw is Map){for(final e in raw.entries)owners[e.key.toString()]=e.value.toString();}
    final players=<Map<String,dynamic>>[];if(playersRaw is List){for(final p in playersRaw){if(p is Map)players.add(Map<String,dynamic>.from(p));}}
    Map<String,dynamic>? self;for(final p in players){if(p['id']?.toString()==playerId){self=p;break;}}if(self!=null){ready=self['ready']==true;turnReady=self['turnReady']==true;}
    onLobby?.call(owners,players);
  }
  Future<bool> claimCountry(String country) async {if(!isConnected)return true;_claimCompleter=Completer<bool>();_ws!.add(jsonEncode({'type':'claimCountry','country':country}));try{return await _claimCompleter!.future.timeout(const Duration(seconds:8));}catch(_){return false;}}
  Future<bool> _simple(String type,{Map<String,dynamic> extra=const {}})async{if(!isConnected)return false;final c=Completer<bool>();_actionCompleters[type]=c;_ws!.add(jsonEncode({'type':type,...extra}));try{return await c.future.timeout(const Duration(seconds:10));}catch(_){_actionCompleters.remove(type);return false;}}
  Future<bool> setReady(bool value)=>_simple('ready',extra:{'ready':value});
  Future<bool> startGame()=>_simple('startGame');
  Future<bool> setRoomPace(String pace)=>_simple('setPace',extra:{'pace':pace});
  Future<bool> surrender()=>_simple('surrender');
  Future<bool> deleteMyData()=>_simple('deleteMyData');
  Future<bool> reportPlayer(String targetPlayerId,String reason)=>_simple('reportPlayer',extra:{'targetPlayerId':targetPlayerId,'reason':reason});
  Future<bool> kickPlayer(String targetPlayerId)=>_simple('kickPlayer',extra:{'targetPlayerId':targetPlayerId});
  bool isPlayerBlocked(String id)=>blockedPlayerIds.contains(id);
  String visiblePlayerName(Map<String,dynamic> p)=>isPlayerBlocked(p['id']?.toString()??'')?'لاعب محظور':(p['name']?.toString()??'لاعب');
  Future<void> toggleBlockPlayer(String id)async{if(blockedPlayerIds.contains(id)){blockedPlayerIds.remove(id);}else{blockedPlayerIds.add(id);}if(_prefs!=null&&_credentialKey.isNotEmpty)await _prefs!.setStringList('${_credentialKey}_blocked',blockedPlayerIds.toList());onConnectionChanged?.call();}
  Future<bool> sendAttack(String source,String target,{String plan='balanced',List<String>? armyIds,String mode='manual',String? targetProvinceId}) async {if(!isConnected)return false;_attackCompleter=Completer<bool>();final payload=<String,dynamic>{'type':'attack','source':source,'target':target,'plan':plan,'mode':mode};if(targetProvinceId!=null)payload['targetProvinceId']=targetProvinceId;if(armyIds!=null)payload['armyIds']=armyIds;_ws!.add(jsonEncode(payload));try{return await _attackCompleter!.future.timeout(const Duration(seconds:10));}catch(_){return false;}}
  Future<bool> sendGameAction(String action,{String? value,String? target}) async {if(!isConnected)return false;final c=Completer<bool>();_actionCompleters[action]=c;_ws!.add(jsonEncode({'type':'gameAction','action':action,'value':value,'target':target}));try{return await c.future.timeout(const Duration(seconds:10));}catch(_){_actionCompleters.remove(action);return false;}}
  Future<bool> sendNextTurn()=>_simple('nextTurn');
  void ensureInitialized(Map<String,dynamic> snapshot){}
  void requestSnapshot(){if(isConnected)_ws!.add(jsonEncode({'type':'requestSnapshot'}));}
  Future<void> clearLocalIdentity()async{if(_prefs!=null&&_credentialKey.isNotEmpty){await _prefs!.remove('${_credentialKey}_player');await _prefs!.remove('${_credentialKey}_token');}playerId='';resumeToken='';}
  void close(){_heartbeat?.cancel();_ws?.close();}
}

class HomeScreen extends StatefulWidget {const HomeScreen({super.key});@override State<HomeScreen> createState()=>_HomeScreenState();}
class _HomeScreenState extends State<HomeScreen>{
  final game=GameState();
  @override void initState(){super.initState();scheduleMicrotask(game.initializeWorldData);}
  @override void dispose(){game.multiplayer?.close();game.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>AnimatedBuilder(animation:game,builder:(context,_){
    final m=game.multiplayer;
    if(m!=null&&m.roomCode.isNotEmpty&&!m.isConnected)return OnlineDisconnectedScreen(game:game);
    if(m?.inLobby==true)return OnlineLobbyScreen(game:game);
    if(m?.isRunning==true&&game.humanCountry!=null)return GameScreen(game:game);
    return game.humanCountry==null?StartScreen(game:game):GameScreen(game:game);
  });
}

class StartScreen extends StatelessWidget {
  final GameState game; const StartScreen({super.key,required this.game});
  @override Widget build(BuildContext context){
    return Scaffold(body:SafeArea(child:Padding(padding:const EdgeInsets.all(20),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      const Text('WORLD DOMINION',style:TextStyle(fontSize:30,fontWeight:FontWeight.w900,letterSpacing:2)),
      const SizedBox(height:6),const Text('حرب • اقتصاد • حكومة • موارد • تحالفات',style:TextStyle(color:Colors.white70)),const SizedBox(height:6),
      Text(game.tr('v1.8 • بناء نظيف + تطابق أوفلاين/أونلاين','v1.8 • Clean build + offline/online parity'),style:const TextStyle(fontSize:12,color:Colors.white54)),
      const SizedBox(height:16),FilledButton.icon(onPressed:()=>_onlineDialog(context,game),icon:const Icon(Icons.public),label:const Padding(padding:EdgeInsets.symmetric(vertical:12),child:Text('مباراة أونلاين'))),
      const SizedBox(height:8),Row(children:[Expanded(child:OutlinedButton.icon(onPressed:()async{final ok=await game.loadLocal();if(!ok&&context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('لا يوجد حفظ محلي صالح بعد.')));},icon:const Icon(Icons.restore),label:const Text('استعادة محلي'))),const SizedBox(width:8),Expanded(child:OutlinedButton.icon(onPressed:()=>_showPrivacy(context,game),icon:const Icon(Icons.privacy_tip_outlined),label:const Text('الخصوصية')))]),
      const SizedBox(height:10),Row(children:[Expanded(child:SegmentedButton<String>(showSelectedIcon:false,segments:const [ButtonSegment(value:'ar',label:Text('العربية')),ButtonSegment(value:'en',label:Text('English'))],selected:{game.appLanguage},onSelectionChanged:(v)=>game.setLanguage(v.first))),const SizedBox(width:8),Text(game.worldDataLoaded?'${game.countries.length} دولة':'...')]),const SizedBox(height:14),Text(game.tr('لعب محلي — اختر الدولة','Offline — choose a country'),style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),const SizedBox(height:8),
      Row(children:[Text(game.tr('صعوبة الذكاء الاصطناعي:','AI difficulty:')),const SizedBox(width:8),Expanded(child:SegmentedButton<String>(showSelectedIcon:false,segments:[ButtonSegment(value:'easy',label:Text(game.tr('سهل','Easy'))),ButtonSegment(value:'normal',label:Text(game.tr('متوازن','Balanced'))),ButtonSegment(value:'hard',label:Text(game.tr('صعب','Hard')))],selected:{game.aiDifficulty},onSelectionChanged:(v)=>game.setAiDifficulty(v.first)))]),const SizedBox(height:8),
      Text(game.tr('مدة/إيقاع المباراة','Match pace'),style:const TextStyle(fontWeight:FontWeight.bold)),const SizedBox(height:6),SegmentedButton<String>(showSelectedIcon:false,segments:[ButtonSegment(value:'rapid',label:Text(game.tr('سريعة','Rapid'))),ButtonSegment(value:'campaign',label:Text(game.tr('حملة','Campaign'))),ButtonSegment(value:'grand',label:Text(game.tr('طويلة','Grand')))],selected:{game.gamePace},onSelectionChanged:(v)=>game.setGamePace(v.first)),Text(game.tr('الإعداد يؤثر في سقف القيادة وموعد نصر الهيمنة؛ الأونلاين يضبط أيضًا مهلة كل دور.','This affects command pacing and hegemony timing; online it also sets each turn deadline.'),style:const TextStyle(fontSize:11,color:Colors.white54)),const SizedBox(height:8),
      Expanded(child:Container(decoration:BoxDecoration(color:Colors.white.withValues(alpha: .04),borderRadius:BorderRadius.circular(20)),child:ListView(padding:const EdgeInsets.all(10),children:game.countries.values.map((c)=>Card(child:ListTile(dense:true,title:Text(c.name),subtitle:Text('السكان ${c.population.toStringAsFixed(0)}م • القوة ${c.army.power.toStringAsFixed(0)}'),trailing:const Icon(Icons.chevron_right),onTap:()=>game.choose(c.id)))).toList()))),
    ]))));
  }
  void _onlineDialog(BuildContext context,GameState game){
    final url=TextEditingController(text:kDefaultServerUrl.isEmpty?'wss://YOUR-SERVER.onrender.com':kDefaultServerUrl);final room=TextEditingController(text:'WAR2026');final name=TextEditingController(text:'لاعب');final password=TextEditingController();String status='';String mode='create';bool busy=false;bool accepted=false;
    showDialog(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setS)=>AlertDialog(title:const Text('مباراة أونلاين'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
      SegmentedButton<String>(segments:const [ButtonSegment(value:'create',label:Text('إنشاء غرفة'),icon:Icon(Icons.add_circle_outline)),ButtonSegment(value:'join',label:Text('انضمام'),icon:Icon(Icons.login))],selected:{mode},onSelectionChanged:busy?null:(v)=>setS(()=>mode=v.first)),
      const SizedBox(height:12),TextField(controller:url,keyboardType:TextInputType.url,decoration:const InputDecoration(labelText:'عنوان السيرفر wss://',helperText:'يمكن لصق https:// وسيتم تحويله تلقائياً')),TextField(controller:room,textCapitalization:TextCapitalization.characters,maxLength:16,decoration:const InputDecoration(labelText:'رمز الغرفة (4–16)')),TextField(controller:name,maxLength:24,decoration:const InputDecoration(labelText:'اسم اللاعب')),TextField(controller:password,obscureText:true,maxLength:40,decoration:const InputDecoration(labelText:'كلمة مرور الغرفة (اختيارية)')),const SizedBox(height:4),CheckboxListTile(contentPadding:EdgeInsets.zero,value:accepted,onChanged:busy?null:(v)=>setS(()=>accepted=v==true),title:const Text('أوافق على شروط الاستخدام وقواعد السلوك'),subtitle:TextButton(style:TextButton.styleFrom(alignment:Alignment.centerLeft,padding:EdgeInsets.zero),onPressed:()=>_showTerms(ctx),child:const Text('قراءة الشروط')),controlAffinity:ListTileControlAffinity.leading),Text(status,style:const TextStyle(fontSize:12))
    ])),actions:[TextButton(onPressed:busy?null:()=>Navigator.pop(ctx),child:const Text('إلغاء')),FilledButton(onPressed:busy||!accepted?null:()async{
      setS(()=>busy=true);final client=MultiplayerClient();client.onStatus=(v){if(ctx.mounted)setS(()=>status=v);};game.attachMultiplayer(client);
      try{await client.connect(url.text,room.text,name:name.text,mode:mode,password:password.text);client.onStatus=(v){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(v)));};if(ctx.mounted)Navigator.pop(ctx);}catch(e){game.leaveOnlineSession();if(ctx.mounted)setS((){busy=false;status='$e';});}
    },child:Text(busy?'اتصال...':(mode=='create'?'إنشاء':'انضمام')))])));
  }
}

class OnlineLobbyScreen extends StatelessWidget {
  final GameState game;
  const OnlineLobbyScreen({super.key,required this.game});
  @override Widget build(BuildContext context){
    final m=game.multiplayer!;
    final chosen=game.humanCountry;
    final active=game.onlinePlayers.where((p)=>p['country']!=null&&p['surrendered']!=true).toList();
    final allReady=active.isNotEmpty&&active.every((p)=>p['ready']==true);
    final lobbyServerVersion=m.serverVersion.isEmpty?'…':m.serverVersion;
    final encryptedLabel=m.serverUrl.startsWith('wss://')?'نعم':'محلي/تجريبي';
    return Scaffold(
      appBar:AppBar(
        title:Text('غرفة ${m.roomCode}'),
        actions:[
          IconButton(tooltip:'نسخ الرمز',onPressed:(){Clipboard.setData(ClipboardData(text:m.roomCode));ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تم نسخ رمز الغرفة')));},icon:const Icon(Icons.copy)),
          IconButton(onPressed:()=>_showPrivacy(context,game),icon:const Icon(Icons.privacy_tip_outlined)),
        ],
      ),
      body:ListView(
        padding:const EdgeInsets.all(16),
        children:[
          Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text('Lobby • ${m.serverUrl}',style:const TextStyle(fontWeight:FontWeight.bold)),
            Text('السيرفر $lobbyServerVersion • Ruleset ${m.serverRuleset.isEmpty?kRulesetVersion:m.serverRuleset} • الاتصال مشفّر: $encryptedLabel'),
            const SizedBox(height:8),
            const Text('اختر دولة، ثم اضغط جاهز. المضيف يبدأ المباراة عندما يصبح الجميع جاهزين.'),
          ]))),
          const SizedBox(height:10),
          _title('اللاعبون'),
          ...game.onlinePlayers.map((p)=>_onlinePlayerCard(context,game,p,showReady:true)),
          const SizedBox(height:10),
          _title(game.tr('إيقاع المباراة','Match pace')),
          if(m.isHost)SegmentedButton<String>(showSelectedIcon:false,segments:[ButtonSegment(value:'rapid',label:Text(game.tr('سريعة • 5د','Rapid • 5m'))),ButtonSegment(value:'campaign',label:Text(game.tr('حملة • 1س','Campaign • 1h'))),ButtonSegment(value:'grand',label:Text(game.tr('طويلة • 12س','Grand • 12h')))],selected:{m.roomPace},onSelectionChanged:(v)async{final ok=await m.setRoomPace(v.first);if(!ok&&context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(game.tr('تعذر تغيير مدة المباراة.','Could not change match pace.'))));}) else Text('${game.tr('الإعداد','Setting')}: ${m.roomPace}'),
          Text(game.tr('إذا أنهى الجميع أدوارهم يتقدم الدور فورًا؛ المهلة فقط تمنع تجمد المباراة عند غياب لاعب.','If everyone ends their turn, the game advances immediately; the deadline only prevents stalled matches.'),style:const TextStyle(fontSize:11,color:Colors.white54)),
          const SizedBox(height:10),
          _title(game.tr('اختر دولتك','Choose your country')),
          DropdownButtonFormField<String>(
            value:chosen,
            decoration:const InputDecoration(border:OutlineInputBorder()),
            items:game.countries.values.map((c)=>DropdownMenuItem<String>(value:c.id,enabled:!game.isCountryTaken(c.id),child:Text('${game.countryDisplayName(c)}${game.isCountryTaken(c.id)?game.tr(' — محجوزة',' — taken'):''}'))).toList(),
            onChanged:m.ready?null:(id){if(id!=null)game.choose(id);},
          ),
          const SizedBox(height:12),
          FilledButton.icon(
            onPressed:chosen==null?null:()async{final ok=await m.setReady(!m.ready);if(!ok&&context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تعذر تغيير حالة الجاهزية.')));},
            icon:Icon(m.ready?Icons.undo:Icons.check),
            label:Text(m.ready?'إلغاء الجاهزية':'أنا جاهز'),
          ),
          if(m.isHost)...[
            const SizedBox(height:8),
            FilledButton.tonalIcon(
              onPressed:allReady?()async{final ok=await m.startGame();if(!ok&&context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تعذر بدء المباراة. تحقق أن الجميع جاهز.')));}:null,
              icon:const Icon(Icons.rocket_launch),
              label:const Text('بدء الحرب'),
            ),
          ],
          const SizedBox(height:12),
          OutlinedButton.icon(onPressed:game.leaveOnlineSession,icon:const Icon(Icons.exit_to_app),label:const Text('مغادرة هذه الجلسة')),
        ],
      ),
    );
  }
}

class OnlineDisconnectedScreen extends StatelessWidget{
  final GameState game;
  const OnlineDisconnectedScreen({super.key,required this.game});
  @override Widget build(BuildContext context){
    final m=game.multiplayer!;
    return Scaffold(body:Center(child:Padding(padding:const EdgeInsets.all(24),child:ConstrainedBox(
      constraints:const BoxConstraints(maxWidth:480),
      child:Card(child:Padding(padding:const EdgeInsets.all(20),child:Column(mainAxisSize:MainAxisSize.min,children:[
        const Icon(Icons.cloud_off,size:54),
        const SizedBox(height:12),
        const Text('انقطع الاتصال بالسيرفر',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)),
        const SizedBox(height:8),
        Text('الغرفة ${m.roomCode}\nلن تتحول المباراة إلى وضع محلي حتى لا يحدث اختلاف أو غش.'),
        const SizedBox(height:16),
        FilledButton.icon(
          onPressed:()async{try{await m.connect(m.serverUrl,m.roomCode,name:m.playerName,mode:'join');}catch(e){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e')));}},
          icon:const Icon(Icons.refresh),
          label:const Text('إعادة الاتصال واستعادة دولتي'),
        ),
        const SizedBox(height:8),
        TextButton(onPressed:game.leaveOnlineSession,child:const Text('العودة للقائمة الرئيسية')),
      ]))),
    ))));
  }
}


Widget _onlinePlayerCard(BuildContext context,GameState game,Map<String,dynamic> p,{required bool showReady}){
  final m=game.multiplayer!;final id=p['id']?.toString()??'';final isMe=id==m.playerId;final blocked=m.isPlayerBlocked(id);
  final country=p['country']==null?'لم يختر دولة':(game.countries[p['country']]?.name??p['country'].toString());
  return Card(child:ListTile(
    leading:Icon(p['online']==true?Icons.circle:Icons.circle_outlined,size:14,color:p['online']==true?Colors.greenAccent:Colors.white38),
    title:Text('${m.visiblePlayerName(p)}${isMe?' (أنت)':''}'),
    subtitle:Text('$country${p['online']==false?' • غير متصل':''}${blocked?' • محظور محلياً':''}'),
    trailing:Row(mainAxisSize:MainAxisSize.min,children:[
      if(showReady)Icon(p['ready']==true?Icons.check_circle:Icons.hourglass_empty),
      if(!isMe)PopupMenuButton<String>(tooltip:'سلامة اللاعب',onSelected:(v)async{
        if(v=='block'){await m.toggleBlockPlayer(id);return;}
        if(v=='kick'){final ok=await m.kickPlayer(id);if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(ok?'تمت إزالة اللاعب من الـLobby.':'تعذر إزالة اللاعب.')));return;}
        if(v=='report'){final reason=await _askReportReason(context);if(reason==null)return;final ok=await m.reportPlayer(id,reason);if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(ok?'تم إرسال البلاغ للمراجعة.':'تعذر إرسال البلاغ.')));}
      },itemBuilder:(_)=>[PopupMenuItem(value:'block',child:Text(blocked?'إلغاء حظر اللاعب':'حظر اللاعب')),const PopupMenuItem(value:'report',child:Text('الإبلاغ عن اللاعب')),if(m.isHost&&m.inLobby)const PopupMenuItem(value:'kick',child:Text('إزالة من الغرفة'))])
    ]),
  ));
}

Future<String?> _askReportReason(BuildContext context)=>showDialog<String>(context:context,builder:(ctx)=>SimpleDialog(title:const Text('سبب البلاغ'),children:[
  SimpleDialogOption(onPressed:()=>Navigator.pop(ctx,'offensive_name'),child:const Text('اسم مسيء أو غير لائق')),
  SimpleDialogOption(onPressed:()=>Navigator.pop(ctx,'harassment'),child:const Text('سلوك مسيء / مضايقة')),
  SimpleDialogOption(onPressed:()=>Navigator.pop(ctx,'cheating'),child:const Text('اشتباه بالغش أو إساءة الاستخدام')),
  SimpleDialogOption(onPressed:()=>Navigator.pop(ctx,'other'),child:const Text('سبب آخر')),
]));

Future<void> _showTerms(BuildContext context)async{
  await showModalBottomSheet(context:context,isScrollControlled:true,builder:(ctx)=>SafeArea(child:Padding(padding:const EdgeInsets.all(20),child:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,mainAxisSize:MainAxisSize.min,children:[
    const Text('شروط الاستخدام وقواعد السلوك',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)),const SizedBox(height:10),
    const Text('اللعبة محاكاة استراتيجية خيالية لأغراض الترفيه. عند اللعب أونلاين يجب عدم استخدام أسماء مسيئة أو تهديدات أو مضايقة لاعبين آخرين أو محاولة الغش أو تعطيل الخدمة. يمكن الإبلاغ عن اللاعبين وحظر أسمائهم محليًا من قائمة اللاعبين. قد تُراجع البلاغات ويجوز إزالة الوصول إلى الخدمة عند إساءة الاستخدام.'),
    const SizedBox(height:10),const Text('لا تمنحك اللعبة أي حق في استخدام الخدمة لإساءة معاملة الآخرين أو لانتهاك القوانين. نتائج اللعبة والدول والحروب داخلها محاكاة وليست ادعاءات سياسية أو جغرافية.'),
    const SizedBox(height:12),if(kEffectiveTermsUrl.isNotEmpty)OutlinedButton.icon(onPressed:()=>launchUrl(Uri.parse(kEffectiveTermsUrl),mode:LaunchMode.externalApplication),icon:const Icon(Icons.open_in_new),label:const Text('فتح الشروط الكاملة')),FilledButton(onPressed:()=>Navigator.pop(ctx),child:const Text('إغلاق'))
  ])))));
}

Future<void> _showPrivacy(BuildContext context,GameState game)async{
  await showModalBottomSheet(context:context,isScrollControlled:true,builder:(ctx)=>SafeArea(child:Padding(padding:const EdgeInsets.all(20),child:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,mainAxisSize:MainAxisSize.min,children:[
    const Text('الخصوصية وبيانات اللعبة',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)),const SizedBox(height:10),const Text('World Dominion لا يحتاج حساب بريد إلكتروني في هذه النسخة. عند اللعب أونلاين يعالج السيرفر معرف ضيف عشوائيًا وHash لمعرف تثبيت مستعار لأغراض الاستعادة ومنع الإساءة، إضافة إلى اسم العرض والدولة المختارة وحالة المباراة. لا توجد مكتبة إعلانات أو تحليلات مضافة في هذا الإصدار.'),const SizedBox(height:10),Text('الإصدار: $kAppVersion • بروتوكول: $kProtocolVersion'),const SizedBox(height:10),Text(game.tr('بيانات جغرافية: Natural Earth (Public Domain) • Copernicus DEM GLO-90 • © ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium • © OpenStreetMap contributors • Overture Maps Foundation (Transportation/ODbL).','Geodata: Natural Earth (Public Domain) • Copernicus DEM GLO-90 • © ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium • © OpenStreetMap contributors • Overture Maps Foundation (Transportation/ODbL).'),style:const TextStyle(fontSize:12,color:Colors.white70)),if(kSupportEmail.isNotEmpty)Text('الدعم: $kSupportEmail'),const SizedBox(height:12),if(kEffectivePrivacyPolicyUrl.isNotEmpty)OutlinedButton.icon(onPressed:()=>launchUrl(Uri.parse(kEffectivePrivacyPolicyUrl),mode:LaunchMode.externalApplication),icon:const Icon(Icons.open_in_new),label:const Text('فتح سياسة الخصوصية الكاملة')),OutlinedButton.icon(onPressed:()=>showLicensePage(context:context,applicationName:'World Dominion',applicationVersion:kAppVersion),icon:const Icon(Icons.description_outlined),label:const Text('تراخيص البرمجيات المفتوحة')),
    if(game.multiplayer?.isConnected==true)...[const Divider(height:28),const Text('إدارة بيانات الجلسة',style:TextStyle(fontWeight:FontWeight.bold)),const Text('يمكنك حذف هوية الضيف الخاصة بهذه الغرفة. إذا كانت المباراة جارية تتحول أراضيك إلى الكمبيوتر.'),TextButton.icon(onPressed:()async{final ok=await game.multiplayer!.deleteMyData();if(ok&&ctx.mounted){Navigator.pop(ctx);game.leaveOnlineSession();}},icon:const Icon(Icons.delete_forever),label:const Text('حذف بياناتي من هذه الغرفة'))]
  ])))));
}

class GameScreen extends StatefulWidget {final GameState game;const GameScreen({super.key,required this.game});@override State<GameScreen> createState()=>_GameScreenState();}
class _GameScreenState extends State<GameScreen>{
  int tab=0;
  @override Widget build(BuildContext context){final g=widget.game;final m=g.multiplayer;final online=m?.isRunning==true;
    return Scaffold(appBar:AppBar(title:Text('${g.me.name} • ${g.tr('الدور','Turn')} ${g.turn} • ${g.gamePaceLabel}'),actions:[
      if(online)Padding(padding:const EdgeInsets.symmetric(horizontal:6),child:Center(child:Tooltip(message:'الغرفة ${m!.roomCode}',child:Icon(Icons.cloud_done,color:m.turnReady?Colors.amberAccent:Colors.greenAccent,size:20)))),
      IconButton(tooltip:'دليل سريع',onPressed:()=>showDialog(context:context,builder:(ctx)=>AlertDialog(title:const Text('دليل World Dominion'),content:const SingleChildScrollView(child:Text('الهدف: وسّع نفوذك دون أن تدمر اقتصادك.\n\n• كل دور ينتج موارد ويستهلك السكان والجيش أساسيات الحياة.\n• لديك نقاط قيادة محدودة: الهجوم والتحريك والبحث والتجسس تتنافس عليها.\n• الهجوم يحتاج جبهة مجاورة وموارد وإمدادًا ومعنويات.\n• اختر سياسة الاحتلال: أمنية أو متوازنة أو حكم ذاتي أو استخراج؛ لكل خيار ثمن.\n• الأراضي المحتلة قد تتمرد إذا ارتفعت المقاومة.\n• البحث والتطوير يحسن الزراعة والصناعة واللوجستيات والمدرعات والطيران والاستخبارات.\n• الحروب الطويلة ترفع إرهاق الحرب وتضغط على الشعب والجيش.\n• المصانع والطاقة والإمداد منشآت يمكن ضربها وإصلاحها.\n• الجيوش المعزولة عن مركز القيادة تضعف.\n• تحالفات اللاعبين تحتاج قبول الطرف الآخر.\n• في الأونلاين كل إجراء عسكري واقتصادي حساس يقرره السيرفر.')),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('فهمت'))])),icon:const Icon(Icons.help_outline)),
      if(!online)IconButton(tooltip:'حفظ محلي',onPressed:g.saveLocal,icon:const Icon(Icons.save)),
      IconButton(tooltip:online?(m!.turnReady?'تم إنهاء دورك':'إنهاء دوري'):'إنهاء الدور',onPressed:(g.eliminated||g.winnerController!=null||(online&&m!.turnReady))?null:()=>_reviewAndEndTurn(context,g),icon:Icon(online&&m!.turnReady?Icons.hourglass_top:Icons.skip_next)),
      IconButton(tooltip:'الإعدادات والخصوصية',onPressed:()=>_showGameMenu(context,g),icon:const Icon(Icons.settings_outlined)),
    ]),body:Column(children:[
      if(g.winnerController!=null)Container(width:double.infinity,padding:const EdgeInsets.all(10),color:Colors.amber.withValues(alpha: .16),child:Text('🏆 انتهت الحرب — الفائز: ${g.winnerName} • ${g.victoryType=='hegemony'?'نصر الهيمنة':'السيطرة الكاملة'}',textAlign:TextAlign.center,style:const TextStyle(fontWeight:FontWeight.bold))),
      if(g.eliminated&&g.winnerController==null)Container(width:double.infinity,padding:const EdgeInsets.all(10),color:Colors.redAccent.withValues(alpha: .14),child:const Text('خسرت آخر إقليم. يمكنك متابعة الحرب كمتفرج.',textAlign:TextAlign.center,style:TextStyle(fontWeight:FontWeight.bold))),
      if(!g.eliminated)_CommandStrip(game:g),
      Expanded(child:IndexedStack(index:tab,children:[PoliticalMapTab(game:g),StateTab(game:g),MilitaryTab(game:g),EconomyTab(game:g),DiplomacyTab(game:g),StrategyTab(game:g),NavalTab(game:g),InfrastructureTab(game:g),LogTab(game:g)]))
    ]),bottomNavigationBar:NavigationBar(labelBehavior:NavigationDestinationLabelBehavior.onlyShowSelected,selectedIndex:tab,onDestinationSelected:(i)=>setState(()=>tab=i),destinations:[NavigationDestination(icon:const Icon(Icons.public),label:g.tr('الخريطة','Map')),NavigationDestination(icon:const Icon(Icons.account_balance),label:g.tr('الدولة','State')),NavigationDestination(icon:const Icon(Icons.shield),label:g.tr('الجيش','Military')),NavigationDestination(icon:const Icon(Icons.factory),label:g.tr('الاقتصاد','Economy')),NavigationDestination(icon:const Icon(Icons.handshake),label:g.tr('الدبلوماسية','Diplomacy')),NavigationDestination(icon:const Icon(Icons.radar),label:g.tr('استراتيجية','Strategy')),NavigationDestination(icon:const Icon(Icons.sailing),label:g.tr('البحر','Naval')),NavigationDestination(icon:const Icon(Icons.location_city),label:g.tr('المدن','Cities')),NavigationDestination(icon:const Icon(Icons.history),label:g.tr('السجل','Log'))]));
  }
}


Future<void> _reviewAndEndTurn(BuildContext context,GameState game)async{
  final warnings=game.strategicWarnings;
  final proceed=await showModalBottomSheet<bool>(context:context,builder:(ctx)=>SafeArea(child:Padding(padding:const EdgeInsets.all(18),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    const Text('مراجعة نهاية الدور',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const SizedBox(height:8),
    if(warnings.isEmpty)const ListTile(contentPadding:EdgeInsets.zero,leading:Icon(Icons.check_circle,color:Colors.greenAccent),title:Text('لا توجد تحذيرات استراتيجية كبيرة.')),
    if(warnings.isNotEmpty)...warnings.map((w)=>ListTile(dense:true,contentPadding:EdgeInsets.zero,leading:const Icon(Icons.warning_amber,color:Colors.amberAccent),title:Text(w))),
    const SizedBox(height:8),Row(children:[Expanded(child:OutlinedButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('العودة للتخطيط'))),const SizedBox(width:8),Expanded(child:FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:Text(game.multiplayer?.isRunning==true?'إنهاء دوري':'تقدم للدور التالي')))])
  ]))));
  if(proceed==true)game.nextTurn();
}


class _CommandStrip extends StatelessWidget{
  final GameState game;const _CommandStrip({required this.game});
  @override Widget build(BuildContext context){final c=game.me,territories=game.countries.values.where((x)=>x.controller==c.controller).length;return Container(height:52,decoration:BoxDecoration(color:Colors.white.withValues(alpha: .035),border:Border(bottom:BorderSide(color:Colors.white.withValues(alpha: .07)))),child:ListView(scrollDirection:Axis.horizontal,padding:const EdgeInsets.symmetric(horizontal:8,vertical:7),children:[
    _miniStatus(Icons.bolt,'قيادة ${c.commandPoints}/${game.commandCap}'),
    _miniStatus(Icons.local_fire_department,'إرهاق ${c.warExhaustion.toStringAsFixed(0)}%'),
    _miniStatus(Icons.flag,'أقاليم $territories'),
    _miniStatus(Icons.emoji_events_outlined,'قوة ${game.controllerScore(c.controller).toStringAsFixed(0)}'),
    if(game.pendingEvents.isNotEmpty)_miniStatus(Icons.notification_important,'أحداث ${game.pendingEvents.length}'),
    if(c.stock.food<12||c.stock.water<12||c.stock.fuel<8||c.stock.power<8)_miniStatus(Icons.warning_amber,'نقص موارد'),
  ]));}
}
Widget _miniStatus(IconData icon,String text)=>Container(margin:const EdgeInsets.only(right:7),padding:const EdgeInsets.symmetric(horizontal:10),decoration:BoxDecoration(color:Colors.white.withValues(alpha: .055),borderRadius:BorderRadius.circular(20)),child:Row(children:[Icon(icon,size:16),const SizedBox(width:5),Text(text,style:const TextStyle(fontSize:12,fontWeight:FontWeight.w600))]));

Future<void> _showGameMenu(BuildContext context,GameState game)async{
  final m=game.multiplayer;
  await showModalBottomSheet(context:context,builder:(ctx)=>SafeArea(child:Padding(padding:const EdgeInsets.all(14),child:Column(mainAxisSize:MainAxisSize.min,children:[
    ListTile(leading:const Icon(Icons.privacy_tip_outlined),title:const Text('الخصوصية والتراخيص'),onTap:(){Navigator.pop(ctx);_showPrivacy(context,game);}),
    if(m?.isRunning==true)ListTile(leading:const Icon(Icons.flag_outlined,color:Colors.orangeAccent),title:const Text('الاستسلام وتحويل أراضيك إلى AI'),onTap:()async{final yes=await showDialog<bool>(context:context,builder:(d)=>AlertDialog(title:const Text('تأكيد الاستسلام'),content:const Text('لن تتمكن من متابعة الحرب بهذه الدولة في هذه الغرفة. ستنتقل أراضيك إلى الكمبيوتر.'),actions:[TextButton(onPressed:()=>Navigator.pop(d,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(d,true),child:const Text('استسلام'))]))??false;if(yes){await m!.surrender();if(ctx.mounted)Navigator.pop(ctx);}}),
    ListTile(leading:const Icon(Icons.info_outline),title:const Text('عن World Dominion'),subtitle:Text('الإصدار $kAppVersion • ${m?.isConnected==true?'Online':'Local'}'),onTap:()=>showAboutDialog(context:context,applicationName:'World Dominion',applicationVersion:kAppVersion,applicationLegalese:'Strategy game release candidate.')),
  ]))));
}

Color _controllerColor(GameState game,Country c){
  if(game.isMine(c.id))return Colors.tealAccent.shade400;
  if(c.controller.startsWith('P:')){final h=c.controller.codeUnits.fold<int>(0,(a,b)=>a+b);return Colors.primaries[h%Colors.primaries.length].shade400;}
  if(game.isOccupied(c)){final h=c.controller.codeUnits.fold<int>(0,(a,b)=>a+b);return Colors.primaries[h%Colors.primaries.length].shade300.withValues(alpha: .82);}
  return Colors.orangeAccent.withValues(alpha: .72);
}
Map<String,Color> _worldColors(GameState game){final out=<String,Color>{};for(final c in game.countries.values){final iso=game.alpha3To2[c.id];if(iso!=null)out[_worldMapKey(iso)]=c.id==game.selected?Colors.white:_controllerColor(game,c);}return out;}

class PoliticalMapTab extends StatelessWidget{
  final GameState game;const PoliticalMapTab({super.key,required this.game});
  @override Widget build(BuildContext context){final s=game.selectedCountry;final source=game.attackSourceFor(s.id);return Column(children:[
    Expanded(child:Container(color:const Color(0xFF06151D),child:InteractiveViewer(minScale:.8,maxScale:8,boundaryMargin:const EdgeInsets.all(120),child:Padding(padding:const EdgeInsets.all(8),child:SimpleMap(instructions:SMapWorld.instructions,defaultColor:const Color(0xFF283944),colors:_worldColors(game),fit:BoxFit.contain,callback:(id,name,details){final alpha2=id.toUpperCase();final alpha3=game.alpha2To3[alpha2];if(alpha3!=null&&game.countries.containsKey(alpha3)){game.select(alpha3);}else{ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(game.tr('$name غير متاحة كدولة قابلة للعب.','$name is not available as a playable country.'))));}}))))),
    Container(padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:Colors.white.withValues(alpha: .05)),child:Column(children:[Row(children:[Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(game.countryDisplayName(s),style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),Text('${s.capital} • ${game.tr('السيطرة','Control')}: ${game.isMine(s.id)?game.tr('أنت','You'):(s.controller.startsWith('P:')?game.tr('لاعب آخر','Other player'):game.tr('كمبيوتر','AI'))} • ${game.tr('السكان','Pop.')} ${s.population.toStringAsFixed(0)}m • ${game.tr('القوة','Power')} ${game.enemyPowerLabel(s)}')])) ,if(!game.isMine(s.id))FilledButton.icon(onPressed:source==null?null:()=>game.attack(s.id),icon:const Icon(Icons.gps_fixed),label:const Text('هجوم'))]),
      const SizedBox(height:6),Row(children:[Icon(game.isSupplyConnected(s.id)&&game.isMine(s.id)?Icons.link:Icons.route,size:16),const SizedBox(width:5),Expanded(child:Text(source!=null?game.tr('جبهة ممكنة من ${source.name}${game.isNavalAttack(source,s)?' • ممر بحري':''} • الإمداد ${game.isSupplyConnected(source.id)?'متصل':'مقطوع'}','Possible front from ${source.name}${game.isNavalAttack(source,s)?' • sea lane':''} • supply ${game.isSupplyConnected(source.id)?'connected':'cut'}'):game.tr('لا توجد جبهة برية/استراتيجية مباشرة للهجوم على هذه الدولة','No direct land/strategic front is available against this country'),style:const TextStyle(fontSize:12,color:Colors.white70)))]),const SizedBox(height:6),Align(alignment:Alignment.centerLeft,child:OutlinedButton.icon(onPressed:()=>_showProvinceMap(context,game,s.id),icon:const Icon(Icons.map_outlined),label:Text(game.tr('خريطة المحافظات','Province map'))))
    ]))
  ]);}
}


Future<void> _showProvinceMap(BuildContext context,GameState game,String countryId)async{
  game.selected=countryId;final ps=game.provincesFor(countryId),current=game.provinceById(game.selectedProvinceId);if(ps.isNotEmpty&&(current==null||current.countryId!=countryId))game.selectedProvinceId=ps.first.id;
  await showModalBottomSheet(context:context,isScrollControlled:true,useSafeArea:true,builder:(ctx)=>FractionallySizedBox(heightFactor:.92,child:AnimatedBuilder(animation:game,builder:(_,__)=>_ProvinceMapSheet(game:game,countryId:countryId))));
}

class _ProvinceMapSheet extends StatelessWidget{
  final GameState game;final String countryId;const _ProvinceMapSheet({required this.game,required this.countryId});
  @override Widget build(BuildContext context){final country=game.countries[countryId]!,selected=game.provinceById(game.selectedProvinceId),shapes=game.provinceShapesByCountry[countryId]??const <ProvinceShape>[];return Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    Row(children:[Expanded(child:Text('${game.tr('خريطة المحافظات','Province map')} — ${game.countryDisplayName(country)}',style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold))),IconButton(onPressed:()=>Navigator.pop(context),icon:const Icon(Icons.close))]),
    Text(shapes.isEmpty?game.tr('لا توجد هندسة GIS محلية في ملف التطوير الحالي؛ GitHub Actions يبنيها تلقائيًا من Natural Earth.','No local GIS geometry in this development bundle; GitHub Actions builds it automatically from the pinned physical-world sources.'):game.tr('${shapes.length} تقسيم إداري • ${game.transportLinesByCountry[countryId]?.length??0} مقطع طرق/سكك استراتيجية مبسطة.','${shapes.length} administrative polygons • ${game.transportLinesByCountry[countryId]?.length??0} simplified strategic road/rail segments.'),style:const TextStyle(fontSize:12,color:Colors.white60)),const SizedBox(height:8),
    Expanded(flex:5,child:Card(clipBehavior:Clip.antiAlias,child:shapes.isEmpty?_ProvinceFallbackGrid(game:game,countryId:countryId):_ProvinceShapeMap(game:game,countryId:countryId))),
    const SizedBox(height:8),if(selected!=null&&selected.countryId==countryId)Expanded(flex:3,child:SingleChildScrollView(child:Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Text(game.appLanguage=='en'?selected.nameEn:selected.name,style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),Text('${game.tr('السيطرة','Control')}: ${selected.controller==game.me.controller?game.tr('أنت','You'):(selected.controller.startsWith('P:')?game.tr('لاعب','Player'):game.tr('ذكاء اصطناعي','AI'))} • ${game.tr('السكان التقديري','Estimated pop.')} ${selected.population.toStringAsFixed(2)}m'),
      const SizedBox(height:6),LinearProgressIndicator(value:(selected.supply/100).clamp(0.0,1.0)),Text('${game.tr('الإمداد','Supply')} ${selected.supply.toStringAsFixed(0)}% • ${game.tr('البنية التحتية','Infrastructure')} ${selected.infrastructure.toStringAsFixed(0)} • ${game.tr('المقاومة','Resistance')} ${selected.resistance.toStringAsFixed(0)}%'),
      Text('${game.tr('الحامية','Garrison')} ${selected.garrison} • ${game.tr('التحصين','Fortification')} ${selected.fortLevel} • ${game.tr('قوة الدفاع','Defense power')} ${selected.defensePower.toStringAsFixed(1)}'),
      Text('${game.tr('التضاريس','Terrain')}: ${game.terrainLabel(selected.terrain)} • ${game.tr('الطقس','Weather')}: ${game.weatherLabel(selected.weather)} • ${game.tr('قدرة اللوجستيات','Logistics cap.')} ${(selected.logisticsCapacity*100).toStringAsFixed(0)}%',style:const TextStyle(fontSize:12,color:Colors.cyanAccent)),
      Text('${game.tr('الارتفاع','Elevation')} ${selected.elevationM.toStringAsFixed(0)} m${selected.elevationSamples>1?' (${selected.elevationMinM.toStringAsFixed(0)}–${selected.elevationMaxM.toStringAsFixed(0)} m)':''} • ${game.tr('التضرس','Relief')} ${selected.reliefM.toStringAsFixed(0)} m • ${game.tr('الغطاء الأرضي','Land cover')}: ${game.landCoverLabel(selected.landCover)}',style:const TextStyle(fontSize:12,color:Colors.lightGreenAccent)),
      Text('${game.tr('الشبكة الاستراتيجية الفعلية','Real strategic network')} • ${game.tr('طرق','roads')} ${selected.actualRoadKm.toStringAsFixed(0)} km • ${game.tr('سكك','rail')} ${selected.actualRailKm.toStringAsFixed(0)} km • ${game.tr('كثافة الطرق','road density')} ${selected.roadDensity.toStringAsFixed(1)} km/1000km²',style:const TextStyle(fontSize:12,color:Colors.white70)),
      if(selected.roadClassKm.isNotEmpty)Text(['motorway','trunk','primary','secondary'].where((k)=>(selected.roadClassKm[k]??0)>0).map((k)=>'$k ${(selected.roadClassKm[k]??0).toStringAsFixed(0)} km').join(' • '),style:const TextStyle(fontSize:11,color:Colors.white54)),
      Text('${selected.hasRealPhysicalData?game.tr('عينات Raster فعلية','real raster samples'):game.tr('بيانات فيزيائية احتياطية','physical fallback')} • ${selected.hasRealRoadData?game.tr('نقل Overture فعلي مبسط','real generalized Overture transport'):game.tr('نقل احتياطي','transport fallback')}',style:const TextStyle(fontSize:11,color:Colors.white54)),
      Text('${game.tr('استثمار الطرق','Road investment')} ${selected.roads}/5 • ${game.tr('استثمار السكك','Rail investment')} ${selected.rail}/5 • ${game.tr('مركز لوجستي','Logistics')} ${selected.logisticsLevel}/5',style:const TextStyle(fontSize:12,color:Colors.white70)),const SizedBox(height:10),
      if(selected.controller==game.me.controller)Wrap(spacing:8,runSpacing:8,children:[FilledButton.tonalIcon(onPressed:()=>game.buildProvinceDefense(selected.id),icon:const Icon(Icons.fort),label:Text(game.tr('تقوية الدفاع','Fortify'))),OutlinedButton.icon(onPressed:()=>game.reinforceProvince(selected.id),icon:const Icon(Icons.group_add),label:Text(game.tr('إرسال 2 مشاة','Send 2 infantry'))),ActionChip(label:Text(game.tr('طريق +1','Road +1')),onPressed:()=>game.upgradeProvinceInfrastructure(selected.id,'roads')),ActionChip(label:Text(game.tr('سكك +1','Rail +1')),onPressed:()=>game.upgradeProvinceInfrastructure(selected.id,'rail')),ActionChip(label:Text(game.tr('لوجستيات +1','Logistics +1')),onPressed:()=>game.upgradeProvinceInfrastructure(selected.id,'logistics'))])
      else FilledButton.icon(onPressed:game.attackSourceFor(countryId)==null?null:()=>_showAttackPlanner(context,game,countryId,preferredProvinceId:selected.id),icon:const Icon(Icons.gps_fixed),label:Text(game.tr('التخطيط للهجوم على هذه المحافظة','Plan attack on this province'))),
    ]))))) else Text(game.tr('اختر محافظة من الخريطة.','Select a province on the map.'))
  ]));}
}

class _ProvinceFallbackGrid extends StatelessWidget{final GameState game;final String countryId;const _ProvinceFallbackGrid({required this.game,required this.countryId});@override Widget build(BuildContext context)=>GridView.builder(padding:const EdgeInsets.all(8),gridDelegate:const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent:180,childAspectRatio:1.6,crossAxisSpacing:6,mainAxisSpacing:6),itemCount:game.provincesFor(countryId).length,itemBuilder:(_,i){final p=game.provincesFor(countryId)[i],sel=game.selectedProvinceId==p.id;return InkWell(onTap:()=>game.selectProvince(p.id),child:Container(padding:const EdgeInsets.all(8),decoration:BoxDecoration(borderRadius:BorderRadius.circular(10),border:Border.all(color:sel?Colors.white:Colors.white24,width:sel?2:1),color:p.controller==game.me.controller?Colors.teal.withValues(alpha: .25):Colors.red.withValues(alpha: .18)),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Text(game.appLanguage=='en'?p.nameEn:p.name,textAlign:TextAlign.center,maxLines:2,overflow:TextOverflow.ellipsis),Text('${game.tr('دفاع','Def')} ${p.defensePower.toStringAsFixed(0)}',style:const TextStyle(fontSize:11,color:Colors.white60))])));});}

class _ProvinceShapeMap extends StatelessWidget{
  final GameState game;final String countryId;const _ProvinceShapeMap({required this.game,required this.countryId});
  @override Widget build(BuildContext context){final shapes=game.provinceShapesByCountry[countryId]??const <ProvinceShape>[];final box=_provinceBounds(shapes);return LayoutBuilder(builder:(ctx,c)=>GestureDetector(onTapUp:(d){final geo=_screenToGeo(d.localPosition,Size(c.maxWidth,c.maxHeight),box);ProvinceShape? hit;for(final shape in shapes.reversed){if(_pointInShape(geo,shape)){hit=shape;break;}}if(hit!=null){final p=game.provinceForShape(hit);if(p!=null)game.selectProvince(p.id);}},child:CustomPaint(size:Size(c.maxWidth,c.maxHeight),painter:_ProvincePainter(game:game,countryId:countryId,bounds:box))));}
}

class _GeoBounds {final double minLng,maxLng,minLat,maxLat;const _GeoBounds(this.minLng,this.maxLng,this.minLat,this.maxLat);}
_GeoBounds _provinceBounds(List<ProvinceShape> shapes){var minX=180.0,maxX=-180.0,minY=90.0,maxY=-90.0;for(final s in shapes){for(final ring in s.rings){for(final p in ring){minX=min(minX,p.dx);maxX=max(maxX,p.dx);minY=min(minY,p.dy);maxY=max(maxY,p.dy);}}}if(minX>maxX)return const _GeoBounds(-1,1,-1,1);final padx=max(.25,(maxX-minX)*.05),pady=max(.25,(maxY-minY)*.05);return _GeoBounds(minX-padx,maxX+padx,minY-pady,maxY+pady);}
Offset _geoToScreen(Offset geo,Size size,_GeoBounds b)=>Offset((geo.dx-b.minLng)/max(.0001,b.maxLng-b.minLng)*size.width,(b.maxLat-geo.dy)/max(.0001,b.maxLat-b.minLat)*size.height);
Offset _screenToGeo(Offset p,Size size,_GeoBounds b)=>Offset(b.minLng+p.dx/max(1,size.width)*(b.maxLng-b.minLng),b.maxLat-p.dy/max(1,size.height)*(b.maxLat-b.minLat));
bool _pointInRing(Offset p,List<Offset> ring){var inside=false;for(var i=0,j=ring.length-1;i<ring.length;j=i++){final a=ring[i],b=ring[j];final cross=((a.dy>p.dy)!=(b.dy>p.dy))&&(p.dx<(b.dx-a.dx)*(p.dy-a.dy)/((b.dy-a.dy).abs()<1e-12?1e-12:b.dy-a.dy)+a.dx);if(cross)inside=!inside;}return inside;}
bool _pointInShape(Offset p,ProvinceShape s)=>s.rings.any((r)=>_pointInRing(p,r));

class _ProvincePainter extends CustomPainter{
  final GameState game;final String countryId;final _GeoBounds bounds;_ProvincePainter({required this.game,required this.countryId,required this.bounds});
  @override void paint(Canvas canvas,Size size){
    canvas.drawRect(Offset.zero&size,Paint()..color=const Color(0xFF071923));
    final shapes=game.provinceShapesByCountry[countryId]??const <ProvinceShape>[];
    for(final shape in shapes){final province=game.provinceForShape(shape),selected=province?.id==game.selectedProvinceId,mine=province?.controller==game.me.controller;final fill=Paint()..color=(mine?Colors.tealAccent:Colors.orangeAccent).withValues(alpha: selected ? .34 : .13),stroke=Paint()..style=PaintingStyle.stroke..strokeWidth=(selected?2.4:1)..color=(selected?Colors.white:Colors.white38);for(final ring in shape.rings){if(ring.length<3)continue;final path=Path();for(var i=0;i<ring.length;i++){final p=_geoToScreen(ring[i],size,bounds);if(i==0)path.moveTo(p.dx,p.dy);else path.lineTo(p.dx,p.dy);}path.close();canvas.drawPath(path,fill);canvas.drawPath(path,stroke);}}
    // Real, generalized strategic road/rail geometry produced at build time from Overture (fallback may be Natural Earth).
    for(final line in game.transportLinesByCountry[countryId]??const <TransportLine>[]){if(line.points.length<2)continue;final path=Path();for(var i=0;i<line.points.length;i++){final p=_geoToScreen(line.points[i],size,bounds);if(i==0)path.moveTo(p.dx,p.dy);else path.lineTo(p.dx,p.dy);}final width=line.kind=='rail'?1.15:(line.roadClass=='motorway'?2.0:line.roadClass=='trunk'?1.7:line.roadClass=='primary'?1.4:1.05),paint=Paint()..style=PaintingStyle.stroke..strokeWidth=width..color=(line.kind=='rail'?Colors.blueGrey.shade100:line.roadClass=='motorway'?Colors.orangeAccent:Colors.amber.shade300).withValues(alpha: .76);canvas.drawPath(path,paint);}
    for(final shape in shapes){final province=game.provinceForShape(shape);if(province?.id==game.selectedProvinceId){final cp=_geoToScreen(Offset(shape.lng,shape.lat),size,bounds);canvas.drawCircle(cp,4,Paint()..color=Colors.white);}}
  }
  @override bool shouldRepaint(covariant _ProvincePainter oldDelegate)=>true;
}

class WorldPainter extends CustomPainter {final GameState game;WorldPainter(this.game);@override void paint(Canvas canvas,Size size){
  final bg=Paint()..color=const Color(0xFF071923);canvas.drawRect(Offset.zero&size,bg);
  final land=Paint()..color=const Color(0xFF123441);final land2=Paint()..color=const Color(0xFF173B45);
  canvas.drawOval(Rect.fromLTWH(size.width*.05,size.height*.08,size.width*.30,size.height*.78),land);
  canvas.drawOval(Rect.fromLTWH(size.width*.39,size.height*.10,size.width*.58,size.height*.70),land2);
  canvas.drawOval(Rect.fromLTWH(size.width*.79,size.height*.77,size.width*.20,size.height*.20),land);
  final grid=Paint()..color=Colors.white.withValues(alpha: .025)..strokeWidth=1;for(int i=1;i<10;i++){canvas.drawLine(Offset(size.width*i/10,0),Offset(size.width*i/10,size.height),grid);}for(int i=1;i<8;i++){canvas.drawLine(Offset(0,size.height*i/8),Offset(size.width,size.height*i/8),grid);}
  // Political-style strategic territory cells. These are gameplay regions, not literal GIS borders.
  for(final c in game.countries.values){
    final center=Offset(c.pos.dx*size.width,c.pos.dy*size.height);double nearest=60;
    for(final o in game.countries.values){if(o.id==c.id)continue;final d=(center-Offset(o.pos.dx*size.width,o.pos.dy*size.height)).distance;if(d<nearest)nearest=d;}
    final radius=(nearest*.38).clamp(7.0,22.0).toDouble();final path=Path();
    final seed=c.id.codeUnits.fold<int>(0,(a,b)=>a+b);
    for(int i=0;i<7;i++){final angle=-pi/2+i*pi*2/7;final wobble=.82+((seed+i*17)%23)/100;final point=center+Offset(cos(angle),sin(angle))*radius*wobble;if(i==0)path.moveTo(point.dx,point.dy);else path.lineTo(point.dx,point.dy);}path.close();
    final mine=game.isMine(c.id),humanOther=c.controller.startsWith('P:')&&!mine;final col=mine?Colors.tealAccent:(humanOther?Colors.purpleAccent:Colors.orangeAccent);
    canvas.drawPath(path,Paint()..color=col.withValues(alpha: c.id==game.selected ? .22 : .09));canvas.drawPath(path,Paint()..color=col.withValues(alpha: .42)..style=PaintingStyle.stroke..strokeWidth=(c.id==game.selected?2:1));
  }
  for(final c in game.countries.values){for(final n in c.neighbors){final o=game.countries[n];if(o==null||c.id.compareTo(o.id)>0)continue;final hostile=c.controller!=o.controller;final mineFront=hostile&&(game.isMine(c.id)||game.isMine(o.id));final link=Paint()..color=(mineFront?Colors.redAccent:Colors.white.withValues(alpha: .10))..strokeWidth=(mineFront?3:1);canvas.drawLine(Offset(c.pos.dx*size.width,c.pos.dy*size.height),Offset(o.pos.dx*size.width,o.pos.dy*size.height),link);}}
  for(final c in game.countries.values){final p=Offset(c.pos.dx*size.width,c.pos.dy*size.height);final mine=game.isMine(c.id);final selected=c.id==game.selected;final online=c.controller.startsWith('P:')&&!mine;final paint=Paint()..color=mine?Colors.tealAccent:(online?Colors.purpleAccent:Colors.orangeAccent.withValues(alpha: .92));canvas.drawCircle(p,selected?10:7,paint);canvas.drawCircle(p,selected?15:11,Paint()..color=Colors.black.withValues(alpha: .2)..style=PaintingStyle.stroke..strokeWidth=1);if(selected){canvas.drawCircle(p,16,Paint()..color=Colors.white..style=PaintingStyle.stroke..strokeWidth=2);}if(mine&&!game.isSupplyConnected(c.id)){canvas.drawCircle(p,13,Paint()..color=Colors.redAccent..style=PaintingStyle.stroke..strokeWidth=2);}final tp=TextPainter(text:TextSpan(text:c.id,style:TextStyle(fontSize:9,color:Colors.white.withValues(alpha: .9),fontWeight:FontWeight.bold)),textDirection:TextDirection.ltr)..layout();tp.paint(canvas,p+const Offset(9,-5));
    for(final city in majorCities[c.id]??const <MajorCity>[]){final cp=Offset((c.pos.dx+city.offset.dx)*size.width,(c.pos.dy+city.offset.dy)*size.height);canvas.drawRect(Rect.fromCenter(center:cp,width:city.capital?5:3,height:city.capital?5:3),Paint()..color=city.capital?Colors.yellowAccent:Colors.white70);}
  }
  for(final site in game.strategicSites){final c=game.countries[site.countryId];if(c==null)continue;final p=Offset((c.pos.dx+site.offset.dx)*size.width,(c.pos.dy+site.offset.dy)*size.height);final selected=game.selectedSiteId==site.id;final col=site.health<25?Colors.redAccent:(site.kind=='capital'?Colors.yellowAccent:Colors.cyanAccent);canvas.drawCircle(p,selected?5:3,Paint()..color=col.withValues(alpha: (.35+site.health/160).clamp(.35,.95).toDouble()));if(selected)canvas.drawCircle(p,8,Paint()..color=Colors.white..style=PaintingStyle.stroke..strokeWidth=1.5);}
  for(final a in game.fieldArmies){final c=game.countries[a.location];if(c==null)continue;final p=Offset(c.pos.dx*size.width,c.pos.dy*size.height)+const Offset(0,-18);final mine=a.owner==game.me.controller;canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center:p,width:18,height:11),const Radius.circular(3)),Paint()..color=mine?Colors.lightBlueAccent:Colors.redAccent);final tp=TextPainter(text:TextSpan(text:'${a.power.toStringAsFixed(0)}',style:const TextStyle(fontSize:7,color:Colors.black,fontWeight:FontWeight.bold)),textDirection:TextDirection.ltr)..layout();tp.paint(canvas,p-Offset(tp.width/2,tp.height/2));}
}@override bool shouldRepaint(covariant WorldPainter oldDelegate)=>true;}

class StateTab extends StatelessWidget{
  final GameState game;const StateTab({super.key,required this.game});
  @override Widget build(BuildContext context){final c=game.me;return ListView(padding:const EdgeInsets.all(16),children:[
    _title('مركز القيادة'),
    Row(children:[Expanded(child:_metricCard('نقاط القيادة','${c.commandPoints}/${game.commandCap}',Icons.bolt)),const SizedBox(width:8),Expanded(child:_metricCard('إرهاق الحرب','${c.warExhaustion.toStringAsFixed(0)}%',Icons.local_fire_department))]),
    const SizedBox(height:8),LinearProgressIndicator(value:(c.commandPoints/game.commandCap).clamp(0.0,1.0)),const SizedBox(height:6),LinearProgressIndicator(value:(c.warExhaustion/100).clamp(0.0,1.0)),
    const Divider(height:28),_title('الحكومة'),_kv('رئيس الدولة',game.president),_kv('وزير الدفاع',game.defenseMinister),_kv('وزير الاقتصاد',game.economyMinister),_kv('وزير الخارجية',game.foreignMinister),
    const SizedBox(height:14),_title('الوضع الداخلي'),LinearProgressIndicator(value:(c.approval/100).clamp(0.0,1.0)),Text('التأييد الشعبي ${c.approval.toStringAsFixed(0)}%'),const SizedBox(height:8),LinearProgressIndicator(value:(c.stability/100).clamp(0.0,1.0)),Text('الاستقرار ${c.stability.toStringAsFixed(0)}%'),const SizedBox(height:12),
    _kv('الأقاليم تحت سيطرتك','${game.countries.values.where((x)=>game.isMine(x.id)).length}'),_kv('أقاليم مقاومة عالية','${game.countries.values.where((x)=>game.isMine(x.id)&&x.resistance>=60).length}'),
    if(game.pendingEvents.isNotEmpty)...[const Divider(height:28),_title('قرارات عاجلة'),...game.pendingEvents.map((e)=>_DomesticEventCard(game:game,event:e))],
    const Divider(height:28),_title('قرارات الدولة'),Wrap(spacing:8,runSpacing:8,children:[ActionChip(label:const Text('تقنين الموارد'),onPressed:()=>game.decision('ration')),ActionChip(label:const Text('دعم السلع'),onPressed:()=>game.decision('subsidy')),ActionChip(label:const Text('تعبئة عامة'),onPressed:()=>game.decision('mobilize')),ActionChip(label:const Text('تهدئة وسلام'),onPressed:()=>game.decision('peace'))]),
    const SizedBox(height:14),Text(c.warExhaustion>70?'إرهاق الحرب مرتفع جدًا: حتى لو كان الجيش قويًا ستتراجع المعنويات والتأييد كل دور. استخدم التهدئة أو خفف العمليات.':'إرهاق الحرب يرتفع مع الهجمات والاحتلال وينخفض تدريجيًا أثناء الهدوء.',style:TextStyle(color:c.warExhaustion>70?Colors.orangeAccent:Colors.white70)),
  ]);}
}

class _DomesticEventCard extends StatelessWidget{
  final GameState game;final Map<String,dynamic> event;const _DomesticEventCard({required this.game,required this.event});
  @override Widget build(BuildContext context){final kind=event['kind']?.toString()??'';late String a,b,ak,bk;if(kind=='drought'){a='استيراد عاجل (-14 مال)';ak='import';b='تقنين (-5 تأييد)';bk='ration';}else if(kind=='protests'){a='إصلاحات (-12 مال)';ak='reform';b='إجراء أمني';bk='security';}else if(kind=='industrial'){a='إصلاح سريع';ak='repair';b='تأجيل الإصلاح';bk='delay';}else{a='استقبال النازحين';ak='accept';b='تشديد الحدود';bk='restrict';}return Card(color:Colors.amber.withValues(alpha: .08),child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[Row(children:[const Icon(Icons.notification_important,color:Colors.amberAccent),const SizedBox(width:8),Expanded(child:Text(event['title']?.toString()??'حدث داخلي',style:const TextStyle(fontWeight:FontWeight.bold,fontSize:16)))]),const SizedBox(height:6),Text(event['description']?.toString()??''),const SizedBox(height:10),Wrap(spacing:8,runSpacing:6,children:[FilledButton.tonal(onPressed:()=>game.resolveEvent(event['id'].toString(),ak),child:Text(a)),OutlinedButton(onPressed:()=>game.resolveEvent(event['id'].toString(),bk),child:Text(b))])])));
  }
}

Widget _metricCard(String label,String value,IconData icon)=>Card(child:Padding(padding:const EdgeInsets.all(12),child:Row(children:[Icon(icon),const SizedBox(width:10),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(label,style:const TextStyle(fontSize:12,color:Colors.white70)),Text(value,style:const TextStyle(fontSize:19,fontWeight:FontWeight.bold))]))])));

class MilitaryTab extends StatelessWidget{
  final GameState game;const MilitaryTab({super.key,required this.game});
  @override Widget build(BuildContext context){final a=game.me.army,s=game.selectedCountry,source=game.attackSourceFor(s.id),myBattles=game.activeBattles.where((b)=>b.attacker==game.me.controller||b.defender==game.me.controller).toList();return ListView(padding:const EdgeInsets.all(16),children:[
    _title('القوات المسلحة'),
    Row(children:[Expanded(child:_metricCard('القوة القتالية',game.combatPower(game.me).toStringAsFixed(1),Icons.shield)),const SizedBox(width:8),Expanded(child:_metricCard('المعنويات','${game.me.morale.toStringAsFixed(0)}%',Icons.favorite))]),
    _unit('جنود',a.soldiers,Icons.groups),_unit('دبابات',a.tanks,Icons.local_shipping),_unit('مدفعية',a.artillery,Icons.adjust),_unit('دفاع جوي',a.airDefense,Icons.security),_unit('طائرات',a.aircraft,Icons.flight),_unit('مروحيات',a.helicopters,Icons.air),_unit('مسيّرات',a.drones,Icons.radar),_unit('استطلاع',a.recon,Icons.visibility),_unit('قوات بحرية',a.navy,Icons.directions_boat),
    const Divider(height:30),_title('التجنيد والتدريب والدفاع'),Text('ذهب ${game.me.stock.gold.toStringAsFixed(0)} • سعة تدريب ${game.recruitRemaining}/${game.recruitCapacity} • معسكرات ${game.me.trainingCamps} • دفاع حدود ${game.me.borderDefense}',style:const TextStyle(color:Colors.white70)),const SizedBox(height:8),Wrap(spacing:8,runSpacing:8,children:[ActionChip(label:const Text('بناء معسكر تدريب'),onPressed:game.buildTrainingCamp),ActionChip(label:const Text('تعزيز دفاع الحدود'),onPressed:game.buildBorderDefense)]),const SizedBox(height:8),_title('تجنيد وتصنيع'),Wrap(spacing:8,runSpacing:8,children:[ActionChip(label:const Text('+3 جنود'),onPressed:()=>game.recruit('soldiers')),ActionChip(label:const Text('+ دبابة'),onPressed:()=>game.recruit('tank')),ActionChip(label:const Text('+ مدفعية'),onPressed:()=>game.recruit('artillery')),ActionChip(label:const Text('+ دفاع جوي'),onPressed:()=>game.recruit('airDefense')),ActionChip(label:const Text('+ طائرة'),onPressed:()=>game.recruit('air')),ActionChip(label:const Text('+ مروحية'),onPressed:()=>game.recruit('heli')),ActionChip(label:const Text('+ مسيّرة'),onPressed:()=>game.recruit('drone')),ActionChip(label:const Text('+ استطلاع'),onPressed:()=>game.recruit('recon')),ActionChip(label:const Text('+ بحرية'),onPressed:()=>game.recruit('navy'))]),
    if(myBattles.isNotEmpty)...[const Divider(height:30),_title('الجبهات النشطة'),...myBattles.map((b)=>_battleCard(context,game,b))],
    const Divider(height:30),_title('مركز العمليات'),
    Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[Text('${source?.name??'لا توجد جبهة'} → ${s.name}',style:const TextStyle(fontSize:17,fontWeight:FontWeight.bold)),const SizedBox(height:6),Text(source==null?'يجب أن يكون لديك إقليم مجاور للهدف.':game.tr('الإمداد: ${game.isSupplyConnected(source.id)?'متصل':'مقطوع'} • تقدير قوة الخصم ${game.enemyPowerLabel(s)}','Supply: ${game.isSupplyConnected(source.id)?'connected':'cut'} • enemy power ${game.enemyPowerLabel(s)}')),const SizedBox(height:10),FilledButton.icon(onPressed:game.isMine(s.id)||source==null?null:()=>_showAttackPlanner(context,game,s.id),icon:const Icon(Icons.gps_fixed),label:Text(game.battleFor(source?.id??'',s.id,source?.controller??'')?.active==true?'متابعة الجبهة':'فتح مخطط الهجوم'))]))),
    const SizedBox(height:8),Wrap(spacing:8,runSpacing:8,children:[OutlinedButton.icon(onPressed:game.isMine(s.id)?null:()=>game.strategicStrike(s.id,'air'),icon:const Icon(Icons.flight_takeoff),label:const Text('غارة جوية • 2 قيادة')),OutlinedButton.icon(onPressed:game.isMine(s.id)?null:()=>game.strategicStrike(s.id,'blockade'),icon:const Icon(Icons.directions_boat),label:const Text('حصار بحري • 2 قيادة'))]),
    const SizedBox(height:12),const Text('الهجوم أصبح عملية على جبهة: كل جولة تغيّر نسبة السيطرة، ويمكن إشراك جيوش ميدانية محددة ثم إدخال الاحتياط أو الانسحاب. الحذر يحفظ القوات، والمتوازن مناسب لمعظم الجبهات، والاختراق يرفع القوة والتكلفة وإرهاق الحرب.',style:TextStyle(color:Colors.white70)),
  ]);}
}

Widget _battleCard(BuildContext context,GameState game,FrontBattle battle){
  final attacking=game.me.controller==battle.attacker,source=game.countries[battle.source],target=game.countries[battle.target],required=attacking?battle.source:battle.target,reserves=game.availableBattleArmies(required,game.me.controller),air=battle.airControl>0.15?'تفوق المهاجم':battle.airControl<-.15?'تفوق المدافع':'متقارب';
  return Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    Row(children:[Icon(battle.naval?Icons.directions_boat:Icons.alt_route),const SizedBox(width:8),Expanded(child:Text('${source?.name??battle.source} → ${target?.name??battle.target}',style:const TextStyle(fontWeight:FontWeight.bold,fontSize:16))),Text('جولة ${battle.round}')]),const SizedBox(height:8),
    LinearProgressIndicator(value:(battle.progress/100).clamp(0.0,1.0)),const SizedBox(height:5),Text(attacking?'تقدم قواتك: ${battle.progress.toStringAsFixed(0)}%':'اختراق العدو: ${battle.progress.toStringAsFixed(0)}%'),
    Text('${battle.encircled?'تطويق قائم • ':''}الجو: $air • مهاجم ${battle.attackerArmyIds.length} جيش • مدافع ${battle.defenderArmyIds.length} جيش',style:const TextStyle(fontSize:12,color:Colors.white70)),const SizedBox(height:9),
    Wrap(spacing:8,runSpacing:8,children:[if(attacking)FilledButton.tonalIcon(onPressed:()=>_showAttackPlanner(context,game,battle.target,sourceId:battle.source),icon:const Icon(Icons.play_arrow),label:const Text('متابعة الهجوم')),OutlinedButton.icon(onPressed:reserves.isEmpty?null:()=>_showBattleReinforce(context,game,battle,reserves),icon:const Icon(Icons.add_circle_outline),label:Text('تعزيز${reserves.isEmpty?' (لا احتياط)':''}')),OutlinedButton.icon(onPressed:()=>game.retreatBattle(battle.id),icon:const Icon(Icons.keyboard_return),label:Text(attacking?'انسحاب':'انسحاب دفاعي'))])
  ])));
}

Future<void> _showBattleReinforce(BuildContext context,GameState game,FrontBattle battle,List<FieldArmy> reserves)async{
  await showModalBottomSheet(context:context,builder:(ctx)=>SafeArea(child:ListView(shrinkWrap:true,padding:const EdgeInsets.all(12),children:[const Text('إرسال احتياط إلى الجبهة • 1 قيادة',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),const SizedBox(height:8),...reserves.map((a)=>ListTile(leading:const Icon(Icons.groups_2),title:Text(a.name),subtitle:Text('قوة ${a.power.toStringAsFixed(1)} • إمداد ${a.supply.toStringAsFixed(0)}% • معنويات ${a.morale.toStringAsFixed(0)}%'),trailing:const Icon(Icons.chevron_right),onTap:(){Navigator.pop(ctx);game.reinforceBattle(battle.id,a.id);})),])));
}

Future<void> _showAttackPlanner(BuildContext context,GameState game,String targetId,{String? sourceId,String? preferredProvinceId})async{
  final source=sourceId!=null?game.countries[sourceId]:game.attackSourceFor(targetId),target=game.countries[targetId];if(source==null||target==null)return;final active=game.battleFor(source.id,targetId,source.controller),available=active==null?game.availableBattleArmies(source.id,source.controller):<FieldArmy>[];final selected=<String>{...(active?.attackerArmyIds??available.map((a)=>a.id))};final enemyProvinces=game.enemyProvinces(targetId);String? targetProvinceId=active?.targetProvinceId??preferredProvinceId??(enemyProvinces.isNotEmpty?enemyProvinces.first.id:null);
  const plans=[
    {'id':'cautious','title':'حذر','desc':'تقدم أبطأ • موارد أقل • خسائر أقل'},
    {'id':'balanced','title':'متوازن','desc':'توازن بين التقدم والخسائر والتكلفة'},
    {'id':'breakthrough','title':'اختراق','desc':'تقدم أقوى • 3 قيادة • خسائر وإرهاق أكبر'},
  ];
  await showModalBottomSheet(context:context,isScrollControlled:true,builder:(outer)=>StatefulBuilder(builder:(ctx,setModalState)=>SafeArea(child:Padding(padding:EdgeInsets.fromLTRB(16,16,16,16+MediaQuery.of(ctx).viewInsets.bottom),child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    SegmentedButton<String>(showSelectedIcon:false,segments:const [ButtonSegment(value:'manual',label:Text('تخطيط يدوي')),ButtonSegment(value:'auto',label:Text('حسم آلي'))],selected:{game.battleMode},onSelectionChanged:(v)=>game.setBattleMode(v.first)),const SizedBox(height:10),Text(active==null?'فتح جبهة: ${source.name} → ${target.name}':'متابعة الجبهة: ${source.name} → ${target.name}',style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const SizedBox(height:6),Text('نقاط القيادة: ${game.me.commandPoints}/${game.commandCap}${game.isNavalAttack(source,target)?' • غزو برمائي':''}${active!=null?' • السيطرة ${active.progress.toStringAsFixed(0)}%':''}'),
    if(active==null&&available.isNotEmpty)...[const SizedBox(height:12),const Text('الجيوش الميدانية المشاركة',style:TextStyle(fontWeight:FontWeight.bold)),const Text('غير المختار يبقى احتياطًا ويمكن إدخاله لاحقًا مقابل نقطة قيادة.',style:TextStyle(fontSize:12,color:Colors.white70)),...available.map((a)=>CheckboxListTile(contentPadding:EdgeInsets.zero,dense:true,value:selected.contains(a.id),title:Text(a.name),subtitle:Text('قوة ${a.power.toStringAsFixed(1)} • إمداد ${a.supply.toStringAsFixed(0)}%'),onChanged:(v)=>setModalState((){if(v==true)selected.add(a.id);else selected.remove(a.id);})))],
    if(active==null&&available.isEmpty)...[const SizedBox(height:10),const Text('لا توجد جيوش ميدانية في هذا الإقليم؛ ستبدأ الجولة بالقوات الوطنية الموجودة.',style:TextStyle(color:Colors.white70))],const SizedBox(height:10),    if(active==null&&enemyProvinces.isNotEmpty)...[const SizedBox(height:10),const Text('المحافظة المستهدفة',style:TextStyle(fontWeight:FontWeight.bold)),Wrap(spacing:6,runSpacing:6,children:enemyProvinces.take(24).map((p)=>ChoiceChip(label:Text('${p.name} • دفاع ${p.defensePower.toStringAsFixed(0)}'),selected:targetProvinceId==p.id,onSelected:(_)=>setModalState(()=>targetProvinceId=p.id))).toList())],

    ...plans.map((p){final id=p['id']!,cost=game.attackCost(source,plan:id,target:target),estimate=game.estimatedAttackRange(source,target,id,armyIds:selected.toList()),cp=game.attackCommandCost(source,target,id);return Card(child:InkWell(borderRadius:BorderRadius.circular(12),onTap:game.me.commandPoints<cp?null:(){Navigator.pop(outer);game.attack(targetId,plan:id,armyIds:selected.toList(),sourceId:source.id,mode:game.battleMode,targetProvinceId:targetProvinceId);},child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[Expanded(child:Text(p['title']!,style:const TextStyle(fontSize:17,fontWeight:FontWeight.bold))),Text('${game.tr('فرصة','Chance')} ≈ ${estimate.low.toStringAsFixed(0)}–${estimate.high.toStringAsFixed(0)}%')]),Text(p['desc']!,style:const TextStyle(color:Colors.white70)),Text('${game.tr('ثقة الاستخبارات','Intel confidence')} ${(estimate.confidence*100).toStringAsFixed(0)}%',style:const TextStyle(fontSize:11,color:Colors.cyanAccent)),const SizedBox(height:6),Text('قيادة $cp • غذاء ${cost.food.toStringAsFixed(0)} • وقود ${cost.fuel.toStringAsFixed(0)} • حديد ${cost.steel.toStringAsFixed(0)} • مال ${cost.money.toStringAsFixed(0)}',style:const TextStyle(fontSize:12))]))));}),
    const SizedBox(height:6),const Text('التقدير يقيس قوة الجولة وليس ضمان احتلال الإقليم. الحسم يحتاج رفع السيطرة إلى 100%، والتطويق والتفوق الجوي/البحري يغيران سرعة التقدم.',style:TextStyle(fontSize:12,color:Colors.white54)),
  ]))))));
}

class EconomyTab extends StatelessWidget{
  final GameState game;const EconomyTab({super.key,required this.game});
  @override Widget build(BuildContext context){final c=game.me;final s=game.countries[game.selected]??c;return ListView(padding:const EdgeInsets.all(16),children:[
    _title('المخزون الوطني'),ResourceGrid(r:c.stock),
    const Divider(height:28),_title('البنية التحتية والصناعة'),_kv('طاقة شمسية','${c.solar}'),_kv('محطات نووية','${c.nuclear}'),_kv('شبكة كهرباء','${c.grid}'),_kv('مزارع','${c.farms}'),_kv('مصانع أغذية','${c.foodFactories}'),_kv('صناعة مدنية','${c.civilianIndustry}'),_kv('صناعة عسكرية','${c.militaryIndustry}'),const SizedBox(height:12),
    Wrap(spacing:8,runSpacing:8,children:[ActionChip(label:const Text('بناء شمسي'),onPressed:()=>game.build('solar')),ActionChip(label:const Text('بناء نووي'),onPressed:()=>game.build('nuclear')),ActionChip(label:const Text('توسيع الكهرباء'),onPressed:()=>game.build('grid')),ActionChip(label:const Text('مزرعة'),onPressed:()=>game.build('farm')),ActionChip(label:const Text('مصنع أغذية'),onPressed:()=>game.build('food')),ActionChip(label:const Text('صناعة مدنية'),onPressed:()=>game.build('civil')),ActionChip(label:const Text('صناعة عسكرية'),onPressed:()=>game.build('mil'))]),
    const Divider(height:30),_title('البحث والتطوير'),const Text('كل بحث يكلف 2 نقطة قيادة. المستوى الأقصى 5، وتزداد تكلفة المستوى التالي.',style:TextStyle(color:Colors.white70)),const SizedBox(height:8),
    _techCard(game,'agriculture','تقنيات الزراعة',Icons.agriculture,'+8% غذاء لكل مستوى ورفع كفاءة المياه'),
    _techCard(game,'industry','الأتمتة الصناعية',Icons.precision_manufacturing,'+8% فولاذ ومال صناعي لكل مستوى'),
    _techCard(game,'logistics','اللوجستيات',Icons.route,'إمداد أفضل + نقطة قيادة قصوى لكل مستوى'),
    _techCard(game,'armor','المدرعات',Icons.local_shipping,'+6% قوة للدبابات والمدفعية لكل مستوى'),
    _techCard(game,'air','التفوق الجوي',Icons.flight_takeoff,'+6% قوة للطيران والمروحيات والمسيّرات'),
    _techCard(game,'intel','الاستخبارات',Icons.manage_search,'يرفع نجاح التجسس ودقة التخطيط'),
    const Divider(height:30),_title(game.tr('الحرب الحديثة','Modern warfare')),
    Text('${game.tr('مدى الطيران','Air range')} ${game.airRangeKm(game.me).toStringAsFixed(0)} km • ${game.tr('جاهزية الجو','Air readiness')} ${game.me.airReadiness.toStringAsFixed(0)}% • ${game.tr('جاهزية الأسطول','Fleet readiness')} ${game.me.fleetReadiness.toStringAsFixed(0)}%',style:const TextStyle(color:Colors.white70)),
    Text('${game.tr('مخزون الصواريخ','Missile inventory')}: ${game.tr('كروز','Cruise')} ${game.me.cruiseMissiles} • ${game.tr('باليستي','Ballistic')} ${game.me.ballisticMissiles} • ${game.tr('فرط صوتي','Hypersonic')} ${game.me.hypersonicMissiles}',style:const TextStyle(color:Colors.white70)),
    Text('${game.tr('برنامج صاروخي','Missile program')} ${game.me.missileProgram}/5 • ${game.tr('دفاع صاروخي','Missile defense')} ${game.me.missileDefense}/5 • ${game.tr('رادار','Radar')} ${game.me.radarLevel}/5 • ${game.tr('إنذار مبكر','Early warning')} ${game.me.earlyWarning}/5 • EW ${game.me.electronicWarfare}/5 • SAT ${game.me.satelliteRecon}/5',style:const TextStyle(color:Colors.white70)),const SizedBox(height:8),
    Wrap(spacing:8,runSpacing:8,children:[ActionChip(label:Text(game.tr('برنامج صاروخي','Missile program')),onPressed:()=>game.modernBuild('missileProgram')),ActionChip(label:Text(game.tr('كروز +1','Cruise +1')),onPressed:()=>game.modernBuild('cruiseMissile')),ActionChip(label:Text(game.tr('باليستي +1','Ballistic +1')),onPressed:game.me.missileProgram>=2?()=>game.modernBuild('ballisticMissile'):null),ActionChip(label:Text(game.tr('فرط صوتي +1','Hypersonic +1')),onPressed:game.me.missileProgram>=4?()=>game.modernBuild('hypersonicMissile'):null),ActionChip(label:Text(game.tr('دفاع صاروخي','Missile defense')),onPressed:()=>game.modernBuild('missileDefense')),ActionChip(label:Text(game.tr('رادار +1','Radar +1')),onPressed:()=>game.modernBuild('radar')),ActionChip(label:Text(game.tr('إنذار مبكر +1','Early warning +1')),onPressed:()=>game.modernBuild('earlyWarning')),ActionChip(label:const Text('EW +1'),onPressed:()=>game.modernBuild('ew')),ActionChip(label:const Text('Satellite +1'),onPressed:()=>game.modernBuild('satellite')),ActionChip(label:Text(game.tr('سيطرة جوية','Air superiority')),onPressed:()=>game.readinessMission('air')),ActionChip(label:Text(game.tr('دورية بحرية','Sea-control patrol')),onPressed:()=>game.readinessMission('naval'))]),
    if(!game.isMine(s.id))...[const SizedBox(height:8),Wrap(spacing:8,runSpacing:8,children:[OutlinedButton.icon(onPressed:game.me.cruiseMissiles>0&&game.canTypedMissileReach(s.id,'cruise')?()=>game.missileStrike(s.id,type:'cruise'):null,icon:const Icon(Icons.rocket_launch),label:Text(game.tr('كروز','Cruise'))),OutlinedButton.icon(onPressed:game.me.ballisticMissiles>0&&game.canTypedMissileReach(s.id,'ballistic')?()=>game.missileStrike(s.id,type:'ballistic'):null,icon:const Icon(Icons.rocket),label:Text(game.tr('باليستي','Ballistic'))),OutlinedButton.icon(onPressed:game.me.hypersonicMissiles>0&&game.canTypedMissileReach(s.id,'hypersonic')?()=>game.missileStrike(s.id,type:'hypersonic'):null,icon:const Icon(Icons.speed),label:Text(game.tr('فرط صوتي','Hypersonic'))),OutlinedButton.icon(onPressed:game.canAirReach(s.id)?()=>game.strategicStrike(s.id,'air'):null,icon:const Icon(Icons.flight_takeoff),label:Text(game.tr('غارة بعيدة المدى','Long-range air strike')))])],
    const SizedBox(height:10),const Text('القوات لها صيانة دورية الآن. جيش ضخم من دون اقتصاد قادر على دفع الغذاء والوقود والمال سيفقد الإمداد والمعنويات.',style:TextStyle(color:Colors.white70)),
  ]);}
}

Widget _techCard(GameState game,String id,String title,IconData icon,String effect){final level=game.techLevel(id),cost=game.researchCost(id),maxed=level>=5;return Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[Row(children:[Icon(icon),const SizedBox(width:8),Expanded(child:Text(title,style:const TextStyle(fontWeight:FontWeight.bold))),Text('$level/5')]),const SizedBox(height:6),LinearProgressIndicator(value:level/5),const SizedBox(height:6),Text(effect,style:const TextStyle(fontSize:12,color:Colors.white70)),const SizedBox(height:8),FilledButton.tonal(onPressed:maxed?null:()=>game.research(id),child:Text(maxed?'مكتمل':'بحث • طاقة ${cost.power.toStringAsFixed(0)} • حديد ${cost.steel.toStringAsFixed(0)} • مال ${cost.money.toStringAsFixed(0)}'))])));}

class DiplomacyTab extends StatelessWidget {
  final GameState game;const DiplomacyTab({super.key,required this.game});
  @override Widget build(BuildContext context){
    final incoming=game.diplomaticOffers.where((o)=>o['to']?.toString()==game.humanCountry&&o['status']=='pending').toList();
    final others=game.countries.values.where((c)=>c.id!=game.humanCountry);
    return ListView(padding:const EdgeInsets.all(12),children:[
      if(incoming.isNotEmpty)...[_title('طلبات دبلوماسية'),...incoming.map((o)=>Card(child:ListTile(leading:const Icon(Icons.mark_email_unread),title:Text('طلب تحالف من ${game.countries[o['from']]?.name??o['from']}'),subtitle:const Text('القبول يمنع الهجوم المباشر بين جميع الأراضي التابعة للحكومتين.'),trailing:Wrap(spacing:4,children:[IconButton(tooltip:'رفض',onPressed:()=>game.respondAlliance(o['id'].toString(),false),icon:const Icon(Icons.close)),IconButton(tooltip:'قبول',onPressed:()=>game.respondAlliance(o['id'].toString(),true),icon:const Icon(Icons.check))])))),const Divider(height:28)],
      _title('العلاقات والتحالفات والتجارة'),
      ...others.map((c)=>Card(child:ListTile(title:Text(c.name),subtitle:Text('${game.areAllies(game.humanCountry!,c.id)?'حليف':'محايد'} • ${game.sanctions.contains(c.id)?'عقوبات مفروضة':'لا عقوبات'}'),trailing:PopupMenuButton<String>(onSelected:(v){if(v=='alliance')game.toggleAlliance(c.id);if(v=='trade')game.trade(c.id);if(v=='sanction')game.toggleSanction(c.id);if(v=='spy')game.spy(c.id);},itemBuilder:(_)=>[PopupMenuItem(value:'alliance',child:Text(game.areAllies(game.humanCountry!,c.id)?'إنهاء التحالف':'إرسال طلب تحالف')),const PopupMenuItem(value:'trade',child:Text('صفقة تجارة')),const PopupMenuItem(value:'sanction',child:Text('عقوبات / رفع')),const PopupMenuItem(value:'spy',child:Text('تجسس'))])))),
      if(game.tradeDeals.isNotEmpty)...[const SizedBox(height:12),_title('آخر الصفقات'),...game.tradeDeals.take(6).map(Text.new)]
    ]);
  }
}

class StrategyTab extends StatelessWidget {
  final GameState game;const StrategyTab({super.key,required this.game});
  @override Widget build(BuildContext context){
    final c=game.me,selected=game.selectedCountry,rank=game.leaderboard.take(8).toList();
    return ListView(padding:const EdgeInsets.all(16),children:[
      _title('القيادة الاستراتيجية'),
      Row(children:[Expanded(child:_metricCard('القيادة','${c.commandPoints}/${game.commandCap}',Icons.military_tech)),const SizedBox(width:8),Expanded(child:_metricCard('القوة الشاملة',game.controllerScore(c.controller).toStringAsFixed(0),Icons.public))]),
      const SizedBox(height:8),_kv('مركز القيادة',game.countries.values.firstWhere((x)=>x.controller==c.controller,orElse:()=>c).capital),_kv('الإمداد','${c.supply.toStringAsFixed(0)}%'),_kv('معنويات الجيش','${c.morale.toStringAsFixed(0)}%'),_kv('الاستخبارات','${c.intelligence.toStringAsFixed(0)}%'),_kv('إرهاق الحرب','${c.warExhaustion.toStringAsFixed(0)}%'),
      const SizedBox(height:10),LinearProgressIndicator(value:(c.supply/100).clamp(0.0,1.0)),const SizedBox(height:6),LinearProgressIndicator(value:(c.morale/100).clamp(0.0,1.0)),
      const Divider(height:28),_title('ترتيب القوى العالمية'),
      ...rank.indexed.map((e){final i=e.$1,item=e.$2;final country=game.countries.values.firstWhere((x)=>x.controller==item.key,orElse:()=>game.me);final mine=item.key==game.me.controller;final territories=game.countries.values.where((x)=>x.controller==item.key).length;return Card(color:mine?Colors.blueGrey.withValues(alpha: .32):null,child:ListTile(dense:true,leading:CircleAvatar(child:Text('${i+1}')),title:Text(country.name+(mine?' • أنت':'')),subtitle:Text('$territories أقاليم • ${item.key.startsWith('AI:')?'ذكاء اصطناعي':'لاعب'}'),trailing:Text(item.value.toStringAsFixed(0),style:const TextStyle(fontWeight:FontWeight.bold,fontSize:17))));}),
      const Divider(height:28),_title('القواعد واللوجستيات'),_kv('قواعد جوية','${c.airBases}'),_kv('قواعد بحرية','${c.navalBases}'),_kv('مراكز إمداد','${c.supplyHubs}'),Wrap(spacing:8,runSpacing:8,children:[ActionChip(label:const Text('قاعدة جوية'),onPressed:()=>game.strategicBuild('airbase')),ActionChip(label:const Text('قاعدة بحرية'),onPressed:()=>game.strategicBuild('navalbase')),ActionChip(label:const Text('مركز إمداد'),onPressed:()=>game.strategicBuild('supply'))]),
      const SizedBox(height:10),_kv(game.tr('مدى الطيران','Air range'),'${game.airRangeKm(c).toStringAsFixed(0)} km'),_kv(game.tr('مدى الصواريخ','Missile range'),'${game.missileRangeKm(c).toStringAsFixed(0)} km'),_kv(game.tr('جاهزية الجو/البحر','Air / fleet readiness'),'${c.airReadiness.toStringAsFixed(0)}% / ${c.fleetReadiness.toStringAsFixed(0)}%'),
      const SizedBox(height:16),_title('شبكة الإمداد'),...game.countries.values.where((x)=>game.isMine(x.id)).map((x)=>ListTile(dense:true,leading:Icon(game.isSupplyConnected(x.id)?Icons.link:Icons.link_off,color:game.isSupplyConnected(x.id)?Colors.greenAccent:Colors.redAccent),title:Text(x.name),subtitle:Text(game.isSupplyConnected(x.id)?'متصل بمركز القيادة':'معزول: الإمداد والاستقرار يتدهوران'))),
      if(game.isMine(selected.id)&&game.isOccupied(selected))...[
        const Divider(height:28),_title('إدارة الاحتلال — ${selected.name}'),Text('المقاومة ${selected.resistance.toStringAsFixed(0)}% • السياسة الحالية: ${_occupationName(selected.occupationPolicy)}',style:const TextStyle(color:Colors.white70)),const SizedBox(height:8),
        Wrap(spacing:8,runSpacing:8,children:[
          ChoiceChip(label:const Text('أمنية'),selected:selected.occupationPolicy=='security',onSelected:(_)=>game.setOccupationPolicy(selected.id,'security')),
          ChoiceChip(label:const Text('متوازنة'),selected:selected.occupationPolicy=='balanced',onSelected:(_)=>game.setOccupationPolicy(selected.id,'balanced')),
          ChoiceChip(label:const Text('حكم ذاتي'),selected:selected.occupationPolicy=='autonomy',onSelected:(_)=>game.setOccupationPolicy(selected.id,'autonomy')),
          ChoiceChip(label:const Text('استخراج'),selected:selected.occupationPolicy=='extraction',onSelected:(_)=>game.setOccupationPolicy(selected.id,'extraction')),
        ]),const SizedBox(height:6),Text(_occupationDescription(selected.occupationPolicy),style:const TextStyle(fontSize:12,color:Colors.white60)),
      ],
      const SizedBox(height:16),_title('المحافظات والدفاع المحلي'),Text('${game.provincesFor(game.selectedCountry.id).length} محافظة/ولاية في ${game.selectedCountry.name}',style:const TextStyle(color:Colors.white70)),...game.provincesFor(game.selectedCountry.id).map((p)=>Card(child:ListTile(dense:true,onTap:()=>game.selectProvince(p.id),title:Text(game.appLanguage=='en'?p.nameEn:p.name),subtitle:Text('${game.tr('حامية','Garrison')} ${p.garrison} • ${game.tr('تحصين','Fort')} ${p.fortLevel} • ${game.tr('إمداد','Supply')} ${p.supply.toStringAsFixed(0)}% • ${game.tr('بنية','Infra')} ${p.infrastructure.toStringAsFixed(0)} • ${game.tr('دفاع','Defense')} ${p.defensePower.toStringAsFixed(1)}'),trailing:game.isMine(p.countryId)?PopupMenuButton<String>(onSelected:(v){if(v=='fort')game.buildProvinceDefense(p.id);if(v=='troops')game.reinforceProvince(p.id);},itemBuilder:(_)=>const [PopupMenuItem(value:'fort',child:Text('بناء/تقوية دفاعات')),PopupMenuItem(value:'troops',child:Text('تعزيز بـ 2 جنود'))]):null))),
      const SizedBox(height:16),_title('الجيوش الميدانية'),const Text('انقل القوات إلى جيوش على الجبهة. الجيش المعزول يخسر الإمداد والمعنويات حتى لو كانت قوته الاسمية كبيرة.'),const SizedBox(height:8),FilledButton.tonalIcon(onPressed:game.isMine(game.selected)?()=>game.formFieldArmy(game.selected):null,icon:const Icon(Icons.add_moderator),label:Text('تشكيل جيش في ${game.selectedCountry.name}')),
      ...game.fieldArmies.where((a)=>a.owner==game.me.controller).map((a)=>Card(child:ListTile(title:Text(a.name),subtitle:Text('${game.countries[a.location]?.name??a.location} • قوة ${game.combatPower(game.me,Army(soldiers:a.soldiers,tanks:a.tanks,artillery:a.artillery,airDefense:a.airDefense,aircraft:a.aircraft,helicopters:a.helicopters,drones:a.drones,recon:a.recon,navy:0)).toStringAsFixed(1)} • إمداد ${a.supply.toStringAsFixed(0)}% • معنويات ${a.morale.toStringAsFixed(0)}%\nمشاة ${a.soldiers} | دبابات ${a.tanks} | مدفعية ${a.artillery} | دفاع جوي ${a.airDefense} | جو ${a.aircraft} | مروحيات ${a.helicopters} | مسيّرات ${a.drones}'),isThreeLine:true,trailing:PopupMenuButton<String>(onSelected:(v){if(v.startsWith('move:'))game.moveFieldArmy(a.id,v.substring(5));else if(v.startsWith('add:'))game.reinforceFieldArmy(a.id,v.substring(4));},itemBuilder:(_)=>[...game.countries[a.location]!.neighbors.where(game.isMine).map((n){final cost=game.movementCostBetween(a.location,n);return PopupMenuItem(value:'move:$n',child:Text('${game.tr('تحرك إلى','Move to')} ${game.countries[n]!.name} • ⛽${cost['fuelCost']} • ${game.tr('إمداد','supply')} -${cost['supplyLoss']}'));}),const PopupMenuDivider(),const PopupMenuItem(value:'add:soldiers',child:Text('إضافة 2 مشاة')),const PopupMenuItem(value:'add:tank',child:Text('إضافة دبابة')),const PopupMenuItem(value:'add:artillery',child:Text('إضافة مدفعية')),const PopupMenuItem(value:'add:airDefense',child:Text('إضافة دفاع جوي')),const PopupMenuItem(value:'add:air',child:Text('إضافة طائرة')),const PopupMenuItem(value:'add:heli',child:Text('إضافة مروحية')),const PopupMenuItem(value:'add:drone',child:Text('إضافة مسيّرة')),const PopupMenuItem(value:'add:recon',child:Text('إضافة استطلاع'))])))),
      const SizedBox(height:16),_title('اللاعبون في الغرفة'),if(game.multiplayer?.isConnected!=true)const Text('أنت في وضع محلي ضد الكمبيوتر.'),if(game.multiplayer?.isConnected==true)...[Text('متصلون: ${game.onlinePlayers.where((p)=>p['online']!=false).length} • ${game.multiplayer!.isHost?'أنت المضيف':'المضيف لاعب آخر'}'),...game.onlinePlayers.map((p)=>_onlinePlayerCard(context,game,p,showReady:false))],
      const SizedBox(height:16),const Text('نصيحة: التوسع السريع ليس دائمًا الأفضل. حافظ على خط الإمداد، نقاط القيادة، الاقتصاد، وإرهاق الحرب قبل فتح جبهة جديدة.',style:TextStyle(color:Colors.white70)),
    ]);
  }
}
String _occupationName(String p)=>switch(p){'security'=>'أمنية','autonomy'=>'حكم ذاتي','extraction'=>'استخراج مكثف',_=>'متوازنة'};
String _occupationDescription(String p)=>switch(p){'security'=>'تخفض المقاومة ببطء مقابل تكلفة مالية وقيود أشد.','autonomy'=>'أفضل سياسة لخفض المقاومة والتأييد طويل المدى، لكنها تعطي موارد أقل مباشرة.','extraction'=>'تنقل المال والحديد والوقود بسرعة إلى دولتك، لكنها ترفع المقاومة وخطر الانتفاضة.','balanced'=>'توازن بين الاستقرار والتكلفة والعائد من الإقليم المحتل.',_=>'توازن بين الاستقرار والتكلفة والعائد من الإقليم المحتل.'};


class NavalTab extends StatelessWidget {
  final GameState game;const NavalTab({super.key,required this.game});
  String _mission(GameState g,String m)=>switch(m){'sea_control'=>g.tr('سيطرة بحرية','Sea control'),'convoy_raid'=>g.tr('صيد القوافل','Convoy raid'),'carrier_strike'=>g.tr('ضربة حاملة','Carrier strike'),'silent'=>g.tr('تخفي غواصات','Silent running'),_=>g.tr('دورية','Patrol')};
  @override Widget build(BuildContext context){
    final source=game.isMine(game.selected)?game.selectedCountry:game.me,zones=game.seaZonesForCountry(source.id),mine=game.myTaskForces,contacts=game.navalTaskForces.where((x)=>x.owner!=game.me.controller).toList();
    return ListView(padding:const EdgeInsets.all(14),children:[
      _title(game.tr('القيادة البحرية','Naval command')),
      Text('${game.tr('الميناء المختار','Selected coast')}: ${game.countryDisplayName(source)} • ${game.tr('سفن احتياط','Reserve surface ships')} ${game.me.army.navy} • ${game.tr('حاملات','Carriers')} ${game.me.carrierStock} • ${game.tr('غواصات','Submarines')} ${game.me.submarineStock}',style:const TextStyle(color:Colors.white70)),
      const SizedBox(height:8),Wrap(spacing:8,runSpacing:8,children:[ActionChip(avatar:const Icon(Icons.airplanemode_active,size:18),label:Text(game.tr('بناء حاملة','Build carrier')),onPressed:()=>game.navalBuild('carrier')),ActionChip(avatar:const Icon(Icons.submarine,size:18),label:Text(game.tr('بناء غواصة','Build submarine')),onPressed:()=>game.navalBuild('submarine'))]),
      const Divider(height:28),_title(game.tr('مناطق الانتشار المتاحة','Available deployment zones')),
      if(zones.isEmpty)Text(game.tr('هذه الدولة لا تملك منفذًا بحريًا صالحًا.','This country has no usable maritime access.'),style:const TextStyle(color:Colors.white60)),
      ...zones.map((z)=>Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[Row(children:[const Icon(Icons.waves),const SizedBox(width:8),Expanded(child:Text(game.seaZoneName(z),style:const TextStyle(fontWeight:FontWeight.bold))),Text('${game.taskForcesInZone(z).length} TF',style:const TextStyle(color:Colors.white60))]),const SizedBox(height:8),Wrap(spacing:7,runSpacing:7,children:[ActionChip(label:Text(game.tr('دورية سطحية','Surface patrol')),onPressed:game.me.army.navy>=1?()=>game.deployTaskForce(source.id,z,surface:1):null),ActionChip(label:Text(game.tr('مجموعة حاملة','Carrier group')),onPressed:game.me.army.navy>=1&&game.me.carrierStock>=1?()=>game.deployTaskForce(source.id,z,surface:1,carriers:1):null),ActionChip(label:Text(game.tr('مجموعة غواصات','Submarine group')),onPressed:game.me.submarineStock>=1?()=>game.deployTaskForce(source.id,z,surface:0,submarines:1):null)])])))),
      const Divider(height:28),_title(game.tr('قواتك البحرية الميدانية','Your deployed task forces')),
      if(mine.isEmpty)Text(game.tr('لم تنشر أي Task Force بعد.','No task force deployed yet.'),style:const TextStyle(color:Colors.white60)),
      ...mine.map((tf){final enemies=game.navalTaskForces.where((x)=>x.owner!=game.me.controller&&x.zoneId==tf.zoneId).toList();return Card(child:ListTile(leading:Icon(tf.carriers>0?Icons.airplanemode_active:tf.submarines>0&&tf.surface==0?Icons.submarine:Icons.sailing),title:Text('${tf.name} • ${game.seaZoneName(tf.zoneId)}'),subtitle:Text('${game.tr('سطح','Surface')} ${tf.surface} • ${game.tr('حاملات','Carriers')} ${tf.carriers} • ${game.tr('غواصات','Subs')} ${tf.submarines}\n${game.tr('جاهزية','Readiness')} ${tf.readiness.toStringAsFixed(0)}% • ${game.tr('إمداد','Supply')} ${tf.supply.toStringAsFixed(0)}% • ${_mission(game,tf.mission)}'),isThreeLine:true,trailing:PopupMenuButton<String>(onSelected:(v){if(v.startsWith('move:'))game.moveTaskForce(tf.id,v.substring(5));else if(v.startsWith('mission:'))game.setTaskForceMission(tf.id,v.substring(8));else if(v.startsWith('engage:'))game.engageTaskForce(tf.id,v.substring(7));},itemBuilder:(_)=>[...game.adjacentSeaZones(tf.zoneId).map((z)=>PopupMenuItem(value:'move:$z',child:Text('${game.tr('تحرك إلى','Move to')} ${game.seaZoneName(z)}'))),const PopupMenuDivider(),PopupMenuItem(value:'mission:patrol',child:Text(game.tr('دورية','Patrol'))),PopupMenuItem(value:'mission:sea_control',child:Text(game.tr('سيطرة بحرية','Sea control'))),PopupMenuItem(value:'mission:convoy_raid',child:Text(game.tr('صيد القوافل','Convoy raid'))),if(tf.carriers>0)PopupMenuItem(value:'mission:carrier_strike',child:Text(game.tr('ضربة حاملة','Carrier strike'))),if(tf.submarines>0)PopupMenuItem(value:'mission:silent',child:Text(game.tr('تخفي غواصات','Silent running'))),if(enemies.isNotEmpty)const PopupMenuDivider(),...enemies.map((e)=>PopupMenuItem(value:'engage:${e.id}',child:Text('${game.tr('اشتباك مع','Engage')} ${e.name}')))])));}),
      const Divider(height:28),_title(game.tr('الاتصالات البحرية المكتشفة','Detected naval contacts')),
      if(contacts.isEmpty)Text(game.tr('لا توجد اتصالات معادية مؤكدة. الغواصات في وضع التخفي قد لا تظهر مع استخبارات ضعيفة.','No confirmed enemy contacts. Silent submarines may stay hidden with weak intelligence.'),style:const TextStyle(color:Colors.white60)),
      ...contacts.map((tf)=>Card(child:ListTile(leading:const Icon(Icons.radar),title:Text('${game.seaZoneName(tf.zoneId)} • ${tf.name}'),subtitle:Text('${game.tr('سطح','Surface')} ${tf.surface} • ${game.tr('حاملات','Carriers')} ${tf.carriers} • ${game.tr('غواصات','Subs')} ${tf.submarines} • ${game.tr('جاهزية','Readiness')} ${tf.readiness.toStringAsFixed(0)}%')))),
      const SizedBox(height:12),Text(game.tr('القوة البحرية البعيدة عن ميناء صديق تفقد الإمداد والجاهزية. الحاملات تمنح قوة جوية بحرية، والغواصات أصعب كشفًا خصوصًا في مهمة التخفي.','Task forces away from a friendly port lose supply and readiness. Carriers add naval aviation; submarines are harder to detect, especially on silent missions.'),style:const TextStyle(color:Colors.white70)),
    ]);
  }
}

class InfrastructureTab extends StatelessWidget {
  final GameState game;const InfrastructureTab({super.key,required this.game});
  @override Widget build(BuildContext context){final c=game.selectedCountry;final sites=game.sitesForCountry(c.id);return ListView(padding:const EdgeInsets.all(14),children:[
    _title('المدن والمنشآت — ${c.name}'),Text('سلامة البنية التحتية: ${game.infrastructureIntegrity(c.id).toStringAsFixed(0)}%${game.isOccupied(c)?' • المقاومة الشعبية ${c.resistance.toStringAsFixed(0)}%':''}'),const SizedBox(height:8),LinearProgressIndicator(value:(game.infrastructureIntegrity(c.id)/100).clamp(0.0,1.0).toDouble()),const SizedBox(height:12),
    ...sites.map((s)=>Card(child:ListTile(onTap:()=>game.selectSite(s.id),leading:Icon(_siteIcon(s.kind)),title:Text(s.name),subtitle:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('${_siteLabel(s.kind)} • المستوى ${s.level}'),const SizedBox(height:4),LinearProgressIndicator(value:(s.health/100).clamp(0.0,1.0).toDouble()),Text('السلامة ${s.health.toStringAsFixed(0)}%${s.operational?'':' — خارج الخدمة جزئيًا'}')]),isThreeLine:true,trailing:game.isMine(c.id)?IconButton(tooltip:'إصلاح',onPressed:s.health>=99?null:()=>game.repairSite(s.id),icon:const Icon(Icons.handyman)):PopupMenuButton<String>(onSelected:(v){if(v=='air')game.strikeSite(s.id);if(v=='missile')game.missileStrike(c.id,siteId:s.id);},itemBuilder:(_)=>[PopupMenuItem(value:'air',enabled:game.canAirReach(c.id),child:Text(game.tr('غارة جوية دقيقة','Precision air strike'))),PopupMenuItem(value:'missile',enabled:game.me.missileStock>0&&game.canMissileReach(c.id),child:Text(game.tr('ضربة صاروخية','Missile strike')))])))),
    if(game.isMine(c.id))...[const Divider(height:28),_title('إنشاء منشأة في الإقليم'),Wrap(spacing:8,runSpacing:8,children:[ActionChip(label:const Text('مطار'),avatar:const Icon(Icons.flight,size:18),onPressed:()=>game.buildSite(c.id,'airport')),ActionChip(label:const Text('ميناء'),avatar:const Icon(Icons.anchor,size:18),onPressed:()=>game.buildSite(c.id,'port')),ActionChip(label:const Text('مصنع'),avatar:const Icon(Icons.factory,size:18),onPressed:()=>game.buildSite(c.id,'factory')),ActionChip(label:const Text('طاقة'),avatar:const Icon(Icons.bolt,size:18),onPressed:()=>game.buildSite(c.id,'power')),ActionChip(label:const Text('إمداد'),avatar:const Icon(Icons.inventory_2,size:18),onPressed:()=>game.buildSite(c.id,'supply'))])],
    const SizedBox(height:14),const Text('أضرار المصانع والطاقة والإمداد تؤثر فعليًا في الإنتاج وتجدد الإمداد. احتلال دولة متضررة يعني أنك ترث بنيتها التحتية بحالتها الحالية.')
  ]);}
}
IconData _siteIcon(String kind)=>switch(kind){'capital'=>Icons.account_balance,'airport'=>Icons.flight,'port'=>Icons.anchor,'power'=>Icons.bolt,'supply'=>Icons.inventory_2,_=>Icons.factory};
String _siteLabel(String kind)=>switch(kind){'capital'=>'مركز الحكم','airport'=>'قاعدة جوية','port'=>'ميناء','power'=>'طاقة','supply'=>'لوجستيات',_=>'صناعة'};

class LogTab extends StatelessWidget {final GameState game;const LogTab({super.key,required this.game});@override Widget build(BuildContext context)=>ListView.separated(padding:const EdgeInsets.all(14),itemCount:game.logs.length,itemBuilder:(c,i)=>Text(game.logs[i]),separatorBuilder:(_,__)=>const Divider());}

class ResourceGrid extends StatelessWidget {final Resources r;const ResourceGrid({super.key,required this.r});@override Widget build(BuildContext context){final xs=[('غذاء',r.food,Icons.restaurant),('ماء',r.water,Icons.water_drop),('وقود',r.fuel,Icons.local_gas_station),('كهرباء',r.power,Icons.bolt),('حديد',r.steel,Icons.build),('مال',r.money,Icons.payments),('ذهب',r.gold,Icons.diamond_outlined)];return GridView.count(crossAxisCount:4,shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),childAspectRatio:1.25,children:xs.map((x)=>Card(child:Padding(padding:const EdgeInsets.all(8),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Icon(x.$3),Text(x.$1),Text(x.$2.toStringAsFixed(0),style:const TextStyle(fontWeight:FontWeight.bold,fontSize:18))])))).toList());}}
Widget _title(String s)=>Padding(padding:const EdgeInsets.only(bottom:8),child:Text(s,style:const TextStyle(fontWeight:FontWeight.bold,fontSize:20)));
Widget _kv(String a,String b)=>Padding(padding:const EdgeInsets.symmetric(vertical:3),child:Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text(a),Text(b,style:const TextStyle(fontWeight:FontWeight.bold))]));
Widget _unit(String name,int n,IconData icon)=>Card(child:ListTile(leading:Icon(icon),title:Text(name),trailing:Text('$n',style:const TextStyle(fontWeight:FontWeight.bold,fontSize:18))));
