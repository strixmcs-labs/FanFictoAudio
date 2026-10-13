#!/bin/zsh
set -euo pipefail
project_root="${0:A:h:h}"
app_path="${1:-$project_root/dist/FanFic to Audio.app}"
profile="${2:-${NOTARYTOOL_PROFILE:-}}"
if [[ -z "$profile" ]]; then
    print -u2 'Set up credentials locally: xcrun notarytool store-credentials EPUBToMP3'
    print -u2 'Then run: Scripts/notarize-app.sh "dist/FanFic to Audio.app" EPUBToMP3'
    exit 1
fi
/usr/bin/codesign --verify --deep --strict -R '=anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists' "$app_path"
work="$(mktemp -d "$project_root/dist/.notarization.XXXXXX")"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_path" "$work/submission.zip"
print "Submitting the signed application to Apple; credentials remain in Keychain."
xcrun notarytool submit "$work/submission.zip" --keychain-profile "$profile" --wait --timeout 30m --output-format json > "$work/result.json"
python3 - "$work/result.json" <<'PY'
import json, sys
result=json.load(open(sys.argv[1]))
print('Notarization status:', result.get('status'))
print('Submission ID:', result.get('id'))
if result.get('status')!='Accepted': raise SystemExit('Apple did not accept this submission; preserve result.json and inspect the submission log.')
PY
xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
/usr/sbin/spctl --assess --type execute --verbose=2 "$app_path"
print "Notarization accepted and ticket stapled: $app_path"
