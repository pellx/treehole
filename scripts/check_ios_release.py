"""Fail the release before upload if configuration/signing metadata disagrees."""
import datetime
import glob
import os
import pathlib
import plistlib
import re
import subprocess
import sys
import zipfile

root = pathlib.Path(__file__).resolve().parents[1]
match = re.search(r'^version: (\d+\.\d+\.\d+)\+(\d+)\s*$', (root / 'pubspec.yaml').read_text(encoding='utf-8'), re.M)
if not match:
    raise SystemExit('pubspec requires semantic version + numeric build number')
version, build = match.groups()
with (root / 'ios/ExportOptions.plist').open('rb') as source:
    export = plistlib.load(source)
bundle = 'com.pellx.treehole'

def require(condition, message):
    if not condition:
        raise SystemExit(message)

mode = sys.argv[1]
if mode == 'config':
    require(os.environ.get('RELEASE_VERSION') == version, 'Dispatch version does not match pubspec')
    require(os.environ.get('TEAM_ID') == export['teamID'], 'APPLE_TEAM_ID does not match export team')
    project = (root / 'ios/Runner.xcodeproj/project.pbxproj').read_text()
    require('YOUR_TEAM_ID' not in project, 'Unresolved team placeholder')
    require(set(re.findall(r'DEVELOPMENT_TEAM = ([^;]+);', project)) == {export['teamID']}, 'Xcode team mismatch')
    actual = subprocess.check_output(['xcodebuild', '-version'], text=True)
    require(int(re.search(r'Xcode (\d+)', actual)[1]) >= 26, 'Xcode 26 or later required')
elif mode == 'profile':
    with open(sys.argv[2], 'rb') as source:
        profile = plistlib.load(source)
    require(profile['ExpirationDate'].replace(tzinfo=datetime.timezone.utc) > datetime.datetime.now(datetime.timezone.utc), 'Provisioning profile expired')
    require(export['teamID'] in profile['TeamIdentifier'], 'Profile team mismatch')
    require(profile['Name'] == export['provisioningProfiles'][bundle], 'Profile name mismatch')
    require(profile['Entitlements']['application-identifier'] == export['teamID'] + '.' + bundle, 'Profile bundle mismatch')
    print('Profile expires:', profile['ExpirationDate'])
elif mode == 'ipa':
    paths = glob.glob(str(root / 'build/ios/ipa/*.ipa'))
    require(len(paths) == 1, 'Expected exactly one IPA')
    with zipfile.ZipFile(paths[0]) as archive:
        entries = [name for name in archive.namelist() if re.fullmatch(r'Payload/[^/]+\.app/Info.plist', name)]
        require(len(entries) == 1, 'Expected one main app')
        info = plistlib.loads(archive.read(entries[0]))
    require(info['CFBundleIdentifier'] == bundle, 'IPA bundle mismatch')
    require(info['CFBundleShortVersionString'] == version, 'IPA marketing version mismatch')
    require(info['CFBundleVersion'] == build, 'IPA build number mismatch')
else:
    raise SystemExit('Expected config, profile or ipa')
print(f'Validated {mode}: {bundle} {version} ({build})')
