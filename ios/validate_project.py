"""Structural validation only. This does not compile Swift or validate Apple APIs."""
from pathlib import Path
import plistlib,re,xml.etree.ElementTree as ET
root=Path(__file__).resolve().parent
for path in root.rglob('*.plist'):plistlib.loads(path.read_bytes())
for path in root.rglob('*.xcprivacy'):plistlib.loads(path.read_bytes())
for path in root.rglob('*.entitlements'):plistlib.loads(path.read_bytes())
text=(root/'PlainWalk.xcodeproj/project.pbxproj').read_text()
objects=set(re.findall(r'^([A-F0-9]{24}) = \{',text,re.M));refs=set(re.findall(r'\b[A-F0-9]{24}\b',text))
assert refs<=objects, refs-objects
assert text.count('isa = PBXNativeTarget;')==2
for path in re.findall(r'lastKnownFileType = sourcecode.swift; path = "([^"]+)"',text):assert (root/path).is_file(),path
for path in root.rglob('*.xcscheme'):ET.parse(path)
assert '../dist' in text
app=plistlib.loads((root/'PlainWalk/Info.plist').read_bytes())
assert 'location' in app['UIBackgroundModes'] and app['NSSupportsLiveActivities']
assert plistlib.loads((root/'PlainWalk/PlainWalk.entitlements').read_bytes())['com.apple.developer.healthkit']
print('Xcode project references, two targets, property lists, scheme, background mode and HealthKit entitlement structurally valid. Swift compilation NOT performed.')
