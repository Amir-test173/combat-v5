#!/usr/bin/env python3
from __future__ import annotations
import json,re,sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
errors=[]
def fail(msg): errors.append(msg)
def text(rel): return (ROOT/rel).read_text(encoding='utf-8')

main=text('lib/main.dart')
settings=text('android/settings.gradle')
app_gradle=text('android/app/build.gradle')
ci=text('.github/workflows/ci.yml')
server=text('server/index.js')
server_js='\n'.join(x.read_text(encoding='utf-8') for x in (ROOT/'server').glob('*.js'))
contract=json.loads(text('assets/mode_parity_contract.json'))
server_contract=json.loads(text('server/mode_parity_contract.json'))

# PDF regression guards: these were real build failures in v1.7 and must never return.
if re.search(r'\?\.[0-9]',main): fail('Dart contains ambiguous/broken ternary syntax like ?.<decimal>')
if re.search(r'\?\.[0-9]',server_js): fail('Server JS contains ambiguous decimal ternary formatting like ?.<decimal>')
if '.withOpacity(' in main: fail('Deprecated Color.withOpacity remains in Dart source')
if "package:countries_world_map/data/maps/world_map.dart" not in main: fail('Explicit SMapWorld import is missing')
if re.search(r'StrategicSite\([^\n;]*\b(?:name|countryId|kind|offset)\s*=',main): fail('StrategicSite call uses = instead of named-parameter :')
for m in re.finditer(r'=>\s*switch\([^)]*\)\{(.*?)\};',main,re.S):
    if '_=>' not in m.group(1): fail('A Dart switch expression lacks a default _=> branch')
if 'army:Army(soldiers:6+min(' in main: fail('Generated Army.soldiers still receives num from min() without toInt()')

# Android matrix proven by the successful GitHub APK build noted by the user.
for needle in [
    'id "com.android.application" version "8.11.1" apply false',
    'id "org.jetbrains.kotlin.android" version "2.2.20" apply false',
]:
    if needle not in settings: fail(f'Missing Android build pin: {needle}')
for needle in ['compileSdk = 36','targetSdk = 36','JavaVersion.VERSION_17']:
    if needle not in app_gradle: fail(f'Missing Android setting: {needle}')
wrapper=text('android/gradle/wrapper/gradle-wrapper.properties')
if 'gradle-8.14.3-bin.zip' not in wrapper: fail('Gradle wrapper distribution is not pinned to 8.14.3')

# CI may verify/generate data/build, but it must not rewrite application source or commit changes.
for pattern,label in [
    (r'git\s+commit','CI commits source changes'),(r'git\s+push','CI pushes source changes'),
    (r'sed\s+-i[^\n]*(?:lib/main\.dart|android/settings\.gradle)','CI patches source with sed'),
    (r'perl[^\n]*(?:lib/main\.dart|android/settings\.gradle)','CI patches source with perl'),
]:
    if re.search(pattern,ci,re.I): fail(label)
if not re.search(r'permissions:\s*\n\s*contents:\s*read',ci): fail('CI permissions are not minimal read-only contents')

# Client/server compatibility contract.
app_protocol=re.search(r"const kProtocolVersion=(\d+);",main)
app_ruleset=re.search(r"const kRulesetVersion='([^']+)';",main)
server_protocol=re.search(r'const PROTOCOL_VERSION=(\d+);',server)
server_ruleset=re.search(r"const RULESET_VERSION='([^']+)';",server)
if not all([app_protocol,app_ruleset,server_protocol,server_ruleset]): fail('Protocol/ruleset constants missing')
else:
    if int(app_protocol.group(1)) != int(server_protocol.group(1)): fail('Client/server protocol mismatch')
    if int(app_protocol.group(1)) != int(contract.get('protocol',-1)): fail('Contract protocol mismatch')
    if app_ruleset.group(1)!=server_ruleset.group(1): fail('Client/server ruleset mismatch')
    if app_ruleset.group(1)!=contract.get('ruleset'): fail('Contract ruleset mismatch')
if contract != server_contract: fail('Flutter/server parity contract JSON files differ')

# Lightweight Dart lexical structure guard. Flutter analyze remains authoritative, but this catches
# truncated strings/comments/brackets before CI spends time generating world data.
def dart_structure_ok(source):
    pairs={')':'(',']':'[','}':'{'}; stack=[]; i=0; quote=None; triple=False
    while i < len(source):
        c=source[i]; n=source[i+1] if i+1<len(source) else ''
        if quote:
            if c=='\\': i+=2; continue
            if triple:
                if source.startswith(quote*3,i): quote=None; triple=False; i+=3; continue
            elif c==quote: quote=None; i+=1; continue
            i+=1; continue
        if c=='/' and n=='/':
            j=source.find('\n',i+2); i=len(source) if j<0 else j+1; continue
        if c=='/' and n=='*':
            j=source.find('*/',i+2)
            if j<0:return False,'unclosed block comment'
            i=j+2; continue
        if c in "'\"":
            quote=c; triple=source.startswith(c*3,i); i+=3 if triple else 1; continue
        if c in '([{': stack.append(c)
        elif c in ')]}':
            if not stack or stack.pop()!=pairs[c]: return False,f'mismatched delimiter near offset {i}'
        i+=1
    if quote:return False,'unclosed string literal'
    if stack:return False,'unclosed delimiter(s)'
    return True,''
ok,why=dart_structure_ok(main)
if not ok: fail(f'Dart lexical structure check failed: {why}')

# LF policy. .bat/.cmd are the only intended CRLF text files.
for path in ROOT.rglob('*'):
    if not path.is_file() or any(part in {'.git','.dart_tool','node_modules','build'} for part in path.parts): continue
    if path.suffix.lower() in {'.dart','.yaml','.yml','.sh','.js','.json','.md','.gradle','.properties','.py'}:
        data=path.read_bytes()
        if b'\r\n' in data: fail(f'CRLF found in LF-only source: {path.relative_to(ROOT)}')

if errors:
    print('CLEAN SOURCE CHECK FAILED')
    for e in errors: print(' -',e)
    sys.exit(1)
print('Clean-source gates passed: Dart regression guards, Android pins, CI immutability, parity contract, LF policy.')
