#!/usr/bin/env python3
"""Synthetic Apple-tool boundary. Never delegates to an Apple/host command."""
import json
import os
from pathlib import Path
import plistlib
import shutil
import sys

tool = Path(sys.argv[0]).name
args = sys.argv[1:]
scenario = os.environ.get('BENZO_FIXTURE_SCENARIO', 'success')
mode = os.environ.get('BENZO_FIXTURE_MODE', 'development')
log = Path(os.environ['BENZO_FIXTURE_LOG'])
with log.open('a') as f:
    f.write(tool + '\t' + '\t'.join(args) + '\n')

def reject(message='Unexpected fixture invocation'):
    raise SystemExit(message)

def value(flag):
    return args[args.index(flag) + 1]

def fail_if(name):
    if scenario == name:
        reject('Injected ' + name)

def write_plist(path, value):
    with Path(path).open('wb') as f:
        plistlib.dump(value, f)
    Path(path).chmod(0o644)

def make_app(app):
    app = Path(app)
    for relative in ['', 'Contents', 'Contents/MacOS', 'Contents/Library', 'Contents/Library/LaunchDaemons']:
        (app / relative).mkdir(parents=True, exist_ok=True)
        (app / relative).chmod(0o755)
    for name in ['Benzo', 'BenzoHelper']:
        (app / 'Contents/MacOS' / name).write_text('fixture executable\n')
        (app / 'Contents/MacOS' / name).chmod(0o755)
    info = {'CFBundleIdentifier': 'com.benzo.app', 'CFBundleExecutable': 'Benzo',
            'CFBundleShortVersionString': '0.3.0', 'CFBundleVersion': '7'}
    if scenario == 'bundle-version': info['CFBundleShortVersionString'] = '0.2.0'
    if scenario == 'bundle-build': info['CFBundleVersion'] = '99'
    if scenario == 'bundle-id': info['CFBundleIdentifier'] = 'com.other.app'
    write_plist(app / 'Contents/Info.plist', info)
    launchd = {'Label': 'com.benzo.helper', 'BundleProgram': 'Contents/MacOS/BenzoHelper',
               'MachServices': {'com.benzo.helper': True}, 'UserName': 'root', 'ProcessType': 'Interactive'}
    if scenario == 'helper-program': launchd['BundleProgram'] = '/tmp/untrusted'
    if scenario == 'helper-service': launchd['MachServices'] = {'com.other.helper': True}
    if scenario == 'helper-root': launchd['UserName'] = 'nobody'
    if scenario == 'helper-extra-arguments': launchd['ProgramArguments'] = ['/bin/sh', '-c', 'bad']
    write_plist(app / 'Contents/Library/LaunchDaemons/com.benzo.helper.plist', launchd)
    if scenario == 'helper-missing': (app / 'Contents/MacOS/BenzoHelper').unlink()
    if scenario == 'helper-symlink':
        (app / 'Contents/MacOS/BenzoHelper').unlink()
        (app / 'Contents/MacOS/BenzoHelper').symlink_to('Benzo')
    if scenario == 'extra-executable': (app / 'Contents/MacOS/Extra').write_text('extra')
    if scenario == 'nested-code': (app / 'Contents/XPCServices').mkdir()

last = args[-1] if args else ''
if tool == 'uname':
    print('Darwin')
elif tool == 'git':
    if 'rev-parse' in args: print('a' * 40)
    elif 'status' in args:
        fail_if('git-status-failure')
        if scenario == 'dirty-source': print(' M tracked-source.swift')
    else: reject()
elif tool == 'xcodebuild':
    if '-version' in args:
        fail_if('xcode-failure')
        print('Command Line Tools only' if scenario == 'xcode-malformed' else 'Xcode 16.4')
        if scenario == 'xcode-split':
            sys.stdout.flush()
            print('Build version 16F6\n' + 'x' * 1048576)
    elif '-showBuildSettings' in args:
        version = '0.3.0'
        if scenario == 'invalid-version': version = '../unsafe'
        if scenario == 'ambiguous-version': version = '0.3.0\n0.4.0'
        settings = [{'buildSettings': {'TARGET_NAME': 'BenzoHelper'}},
                    {'buildSettings': {'TARGET_NAME': 'Benzo', 'MARKETING_VERSION': version, 'CURRENT_PROJECT_VERSION': '7'}}]
        if scenario == 'duplicate-target': settings.append(settings[1])
        print(json.dumps(settings))
    elif 'archive' in args:
        fail_if('archive-failure')
        make_app(Path(value('-archivePath')) / 'Products/Applications/Benzo.app')
    else: reject()
elif tool == 'security':
    if args != ['find-identity', '-v', '-p', 'codesigning']: reject()
    if scenario != 'identity-missing':
        print('  1) ' + 'A' * 40 + ' "Developer ID Application: Fixture (TEAM123456)"')
elif tool == 'ditto':
    if args[:3] == ['-c', '-k', '--keepParent']:
        Path(last).write_text('fixture zip')
    elif len(args) == 2:
        shutil.copytree(args[0], args[1], symlinks=True)
    else: reject()
elif tool == 'lipo':
    missing = scenario == 'missing-slice' or (scenario == 'helper-missing-slice' and last.endswith('BenzoHelper'))
    print('arm64' if missing else 'arm64 x86_64')
elif tool == 'codesign':
    component = 'dmg' if last.endswith('.dmg') else ('helper' if last.endswith('BenzoHelper') else 'app')
    signature_path = log.parent / ('signed-' + component + '.json')
    if '--sign' in args:
        fail_if('sign-failure')
        if '--deep' in args: reject('Never sign with --deep')
        signature = {'identity': value('--sign'), 'identifier': value('--identifier') if '--identifier' in args else None}
        if '--entitlements' in args:
            with open(value('--entitlements'), 'rb') as f: signature['entitlements'] = plistlib.load(f)
        signature_path.write_text(json.dumps(signature))
        if component == 'app':
            resources = Path(last) / 'Contents/_CodeSignature'
            resources.mkdir(mode=0o755)
            (resources / 'CodeResources').write_text('fixture signature')
            (resources / 'CodeResources').chmod(0o644)
    elif '--verify' in args:
        fail_if('bad-signature')
        if not signature_path.exists(): reject('Verification before signing')
        if '-R' in args and ('anchor apple generic' not in value('-R') or 'TEAM123456' not in value('-R')): reject()
    elif '-dv' in args or '-d' in args:
        signature = json.loads(signature_path.read_text())
        if '--entitlements' in args:
            entitlements = signature['entitlements']
            if scenario == 'wrong-helper-role' and component == 'helper': entitlements = {'com.benzo.helper-client': True}
            if scenario == 'extra-entitlement': entitlements['com.apple.security.get-task-allow'] = True
            sys.stdout.buffer.write(plistlib.dumps(entitlements))
        else:
            identifier = signature['identifier']
            if scenario == 'wrong-helper-id' and component == 'helper': identifier = 'BenzoHelper'
            print('Identifier=' + identifier)
            if mode == 'development': print('Signature=adhoc')
            else:
                print('Authority=Developer ID Application: Fixture (TEAM123456)')
                print('TeamIdentifier=' + ('WRONG12345' if scenario == 'wrong-team' else 'TEAM123456'))
                if scenario != 'no-runtime': print('CodeDirectory v=20500 size=123 flags=0x10000(runtime) hashes=1+1')
                if scenario != 'no-timestamp': print('Timestamp=Nov 13, 2026')
    else: reject()
elif tool == 'xcrun':
    if args[:2] == ['notarytool', 'submit']:
        fail_if('notary-failure')
        if value('--keychain-profile') != 'benzo-fixture' or '--wait' not in args: reject()
        status = 'Invalid' if scenario in ['notary-rejected', 'notary-rejected-command'] or (scenario == 'dmg-rejected' and args[2].endswith('.dmg')) else 'Accepted'
        print(json.dumps({'status': status, 'id': '11111111-1111-4111-8111-111111111111'}))
        if scenario == 'notary-rejected-command': raise SystemExit(65)
    elif args[:2] == ['notarytool', 'log']:
        fail_if('notary-log-failure')
        Path(last).write_text(json.dumps({'issues': [], 'status': 'fixture'}))
    elif args[0] == 'stapler':
        if args[1] == 'staple': fail_if('staple-failure')
        if args[1] == 'validate': fail_if('staple-invalid')
    else: reject()
elif tool == 'hdiutil':
    if args[0] == 'create':
        root = Path(value('-srcfolder'))
        app_name = 'Benzo Development.app' if mode == 'development' else 'Benzo.app'
        if not (root / app_name).is_dir() or (root.stat().st_mode & 0o777) != 0o755: reject('Invalid image root')
        if os.readlink(root / 'Applications') != '/Applications': reject('Missing Applications affordance')
        if mode == 'development' and 'DEVELOPMENT ONLY' not in (root / 'README.txt').read_text(): reject('Missing development label')
        if (root / app_name / 'Contents/_CodeSignature/CodeResources').stat().st_mode & 0o777 != 0o644: reject('Signature mode')
        shutil.copytree(root, log.parent / 'dmg-tree', symlinks=True)
        Path(last).write_text('fixture DMG')
    elif args[0] == 'verify': fail_if('dmg-invalid')
    elif args[0] == 'attach':
        if not all(x in args for x in ['-readonly', '-nobrowse', '-noautoopen', '-plist']): reject('Unsafe attachment')
        mount = Path(value('-mountpoint'))
        shutil.copytree(log.parent / 'dmg-tree', mount, symlinks=True, dirs_exist_ok=True)
        if scenario == 'mounted-helper-missing': (mount / 'Benzo Development.app/Contents/MacOS/BenzoHelper').unlink()
        sys.stdout.buffer.write(plistlib.dumps({'system-entities': [{'dev-entry': '/dev/disk42s1', 'mount-point': str(mount)}]}))
    elif args[0] == 'detach': fail_if('detach-failure')
    else: reject()
elif tool == 'spctl':
    fail_if('assessment-failure')
else:
    reject('Unexpected fixture tool: ' + tool)
