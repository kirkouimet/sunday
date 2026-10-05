# Sunday: App Store screenshots

Finished files, ready to upload:

| Slot in App Store Connect | Folder | Size | Count |
|---|---|---|---|
| iPhone 6.5" Display | `Screenshots/iphone-6.5/` | 1284 × 2778 | 6 |
| iPad 13" Display | `Screenshots/ipad-13/` | 2064 × 2752 | 5 |

Apple scales these down for every smaller iPhone and iPad, so no other sizes are needed. Upload them in file-name order; the first three show in search results.

The same frames live on an editable canvas: https://claude.ai/artifact/GEazbhWrLmd4jtUM7oPeW5

## The shots

| # | Screen | Headline | Line beneath |
|---|---|---|---|
| 1 | Feed | Every Sunday dinner, kept. | Snap it, name it, give it your stars. |
| 2 | Dinner page | Your stars stay yours. | Private ratings. Not even the cook sees them. |
| 3 | Years grid | Years of dinners, one album. | The whole family adds to the same timeline. |
| 4 | Ideas (iPhone only) | What's for dinner? | Ideas from your own table, not the internet. |
| 5 | Sunday Live | Everyone at the table. | Go live and the family checks in with photos. |
| 6 | Family | Just your family. No accounts. | Everything stays in your iCloud. |

On iPad the dinner page is third and the years grid second.

## The photos

The dinners in these shots are sample data (`Sunday/Support/PreviewData.swift`) with public-domain and CC0 photos from Wikimedia Commons, listed in `SamplePhotos/SOURCES.md`. To use the family's own dinners, replace a file in `SamplePhotos/` and keep its name, then recapture.

## Recapture

1. Capture the real app on both simulators (about a minute for iPhone, four for iPad). `-collect-test-diagnostics never` matters: without it `xcodebuild` can hang after the test passes.

   ```sh
   xcodegen generate
   for device in "iPhone 17 Pro Max" "iPad Pro 13-inch (M5)"; do
     TEST_RUNNER_SUNDAY_SAMPLE_PHOTOS="$PWD/AppStore/SamplePhotos" xcodebuild test \
       -project Sunday.xcodeproj -scheme Sunday \
       -destination "platform=iOS Simulator,name=$device" \
       -resultBundlePath "build/shots-$device.xcresult" \
       -collect-test-diagnostics never \
       -only-testing:SundayUITests/ScreenshotTests/testLightMode
     xcrun xcresulttool export attachments --path "build/shots-$device.xcresult" --output-path "build/shots-$device"
   done
   ```

2. Copy the captures you want into `Screenshots/raw/iphone/` and `Screenshots/raw/ipad/`, named `1-feed.png`, `2-feed-scrolled.png`, `3-detail.png`, `7-ideas.png`, `8-family.png`, `9-live.png` (the export's `manifest.json` maps its file names to these). `raw/` is not kept in git.

3. Frame them:

   ```sh
   pip install pillow
   python3 AppStore/Screenshots/frame.py
   ```

Headlines, sizes and colors are at the top of `frame.py`. The typeface is Newsreader (SIL Open Font License, `Screenshots/fonts/OFL.txt`).
