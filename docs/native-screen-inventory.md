# Implemented native screen inventory — 2026-11-01

This inventories the current independent SwiftUI app, not all screens of the official app. A distinct app-owned page is different from a variant, scroll segment, system picker, permission prompt or physical-device surface. The original 14 screenshots covered initial states. The final catalog captures 86 native frames, including the additional detail, populated and scroll states.

## Distinct app-owned displays

| Group | Screen / actual View | File | Required data / entry |
|---|---|---|---|
| Tabs | My map / NativeMyMapView(model:) | NativeMyMapView.swift | Empty and populated trails; map only |
| Tabs | Records / NativeRecordsView(model:) | NativeRecordsView.swift | Empty and saved walks; calendar + lower history |
| Tabs | Profile / NativeProfileView(model:) | NativeProfileView.swift | Summary + lower actions |
| General | Menu / NativeMenuView(model:) | NativeUtilityViews.swift | Recording controls appear only with active/paused session |
| General | Statistics / NativeStatsView(model:) | NativeUtilityViews.swift | Saved walks for totals/recent list |
| General | Replay / NativeReplayView(model:walkID:) | NativeUtilityViews.swift | nil for all, a valid walk ID for one; empty/populated/exporting |
| General | Health import / NativeHealthImportView(model:) | NativeUtilityViews.swift | Normal opening calls authorize; DEBUG fixture must suppress that, not fake real authorization |
| Preferences | Settings / NativeSettingsView(config:onChange:onAction:onClose:embedded:) | NativeSettingsView.swift | Capture all scroll sections; embedded true matches profile route |
| Preferences | Map layers / NativeLayerView(model:) | NativeLayerView.swift | Capture top + outline/transports + lower toggles |
| Preferences | Step goal / NativeStepGoalView(model:) | NativeStepGoalView.swift | Goal off/on; real steps unavailable must stay unavailable |
| Preferences | LUT / NativeLUTView(model:) | NativeLUTView.swift | Built-in color chart; custom cube enables name/size/delete section |
| Preferences | Developer / NativeDeveloperView(recorder:) | NativeDeveloperView.swift | Status/permissions + test/checklist + export at bottom |
| Answer map | Answer map / NativeAnswerMapView(model:) | NativeAnswerMapView.swift | Standard, satellite, pitched variants |
| Answer map | Destination search / private searchSheet | NativeAnswerMapView.swift | Empty query; result/no-result/loading/error states; actual network results nondeterministic |
| Answer map | Place selection card / private selectionCard(_:) | NativeAnswerMapView.swift | Selected NativeAnswerPlace; overlay of same map, distinct destination action display |
| Media | Capture/import composer / NativePhotoCaptureView(model:) | NativePhotoCaptureView.swift | Photo/video tabs; empty/imported/photo metadata/unplaced/explicit-placement + film/caption/icon |
| Collections | Spots list / NativeCollectionsView(model:collection:.spots) | NativeCollectionsView.swift | Empty + populated |
| Collections | Stickers list / collection:.stickers | NativeCollectionsView.swift | Stickers derive from notes[day].layout where type==sticker |
| Collections | Badges list / collection:.badges via NCBadgesView | NativeCollectionsView.swift | Empty/loading/error/populated; GeoJSON compute is asynchronous |
| Collections | Doodles list / collection:.doodles | NativeCollectionsView.swift | Empty + saved drawings |
| Collections | Shared maps list / collection:.sharedMaps | NativeCollectionsView.swift | Empty + saved papers |
| Collections | Bookmarks list / collection:.bookmarks | NativeCollectionsView.swift | Empty + saved coordinates |
| Collections | Notes list / collection:.notes | NativeCollectionsView.swift | Empty + notes keyed yyyy-MM-dd |
| Collection details | Spot detail / NCSpotDetail(model:spotID:) | NativeCollectionsView.swift | Valid spot; photo and video variants; delete/cutout/share actions |
| Collection details | Sticker giver / NCStickerPicker(model:) | NativeCollectionsView.swift | Empty + sticker grid; opens standard share, no dedicated nearby exchange |
| Collection details | Badge detail / NCBadgeDetail(model:badge:) | NativeCollectionsView.swift | Actual NCBadge from supplied tracks and real bundled boundaries |
| Collection details | Doodle editor / NCDoodleEditor(initialCenter:model:) | NativeCollectionsView.swift | Empty + strokes; drawing/move-map state |
| Collection details | Doodle detail / NCDoodleDetail(model:itemID:) | NativeCollectionsView.swift | Pending and all-done variants |
| Collection details | New shared paper / NCPaperEditor(model:) | NativeCollectionsView.swift | Saved walks for selection |
| Collection details | Shared paper detail / NCPaperDetail(model:itemID:) | NativeCollectionsView.swift | Valid sharedMaps row |
| Collection details | Bookmark detail / NCBookmarkDetail(model:itemID:) | NativeCollectionsView.swift | Valid bookmarks row; current fix optional |
| Collection details | Notebook editor / NativeNotebookEditor(model:day:) -> NCNoteEditor | NativeCollectionsView.swift | Empty + text/photo/route/sticker layout; selected item controls below preview |
| Recording details | Walk detail / NativeWalkDetailView(model:walkID:) | NativeRecordsView.swift | Valid walk; notes/photos strip below top; missing-walk error separate |
| Recording details | Rename/note sheet / private naming sheet inside NativeWalkDetailView | NativeRecordsView.swift | Valid walk; actual sheet via DEBUG initial State; child-presentation gate needed |
| Recording details | Day records / NativeDayRecordsView(model:date:onSelectWalk:) | NativeRecordsView.swift | A saved-walk day, plus a no-record day variant |
| Recording details | Weekly review / NativeWeekReviewView(model:interval:onSelectWalk:) | NativeRecordsView.swift | Interval containing fixture saved walks |
| Recording details | Walk photo preview / NativeWalkPhotoPreview(spot:) | NativeRecordsView.swift | A photo-bearing NativeSpot |
| Recording details | Track editor / NativeTrackEditorView(model:walkID:) | NativeTrackEditorView.swift | >=2 points; selected point reveals lower edit controls; record-in-progress disables save |
| Map details | Map photo preview / NativeMapSpotPreview(spot:) | NativeMyMapView.swift | Photo or text/emoji NativeSpot; distinct body from collection/walk photo detail |
| Map details | Map flag preview / NativeMapFlagPreview(model:flag:) | NativeMyMapView.swift | NativeFlag; optional current fix/distance |

40 entries above include the destination selection overlay as a display. The same View reused from multiple entry points need not be counted as a new screen; entry-point navigation coverage should be tracked separately.

## Already added DEBUG factories

- `nativeCaptureCollectionScreen(_:model:onContentReady:)`: `spotDetail`, `stickerPicker`, `bookmarkDetail`, `paperEditor`, `paperDetail`, `doodleEditor`, `doodleDetail`, `badgeDetail`.
- `nativeCaptureRecordScreen(_:model:)`: `walk`, `walkRename`, `day`, `week`, `walkPhoto`, `trackEditor`.
- `nativeCaptureMapScreen(_:model:)`: `mapSpot`, `mapFlag`.
- Data selection uses the supplied model's first matching valid item, not production storage or hard-coded personal coordinates.
- `badgeDetail` computes asynchronously and calls `onContentReady` only on actual successful badge materialization. On failure it displays a reason and intentionally does not release the success gate.
- `walkRename` opens the existing nested sheet. The outer host's appearance is insufficient: verify the child title 「さんぽを編集」 before capture.
- `-PlainWalkScreenshotFixture` suppresses HealthImport's `authorize()` task and displays an explicit fixture/no-real-access explanation in the existing empty state.

## Scroll coverage needed in addition to one image per View

- Settings: (1) movement/home/work; (2) appearance/units/steps/LUT; (3) notifications/time; (4) Health; (5) import/export/backup/about; (6) beta/reset/developer. Turn beta/developer on in isolated fixture to expose their subordinate controls.
- Layers: (1) palette/line/pin/current marker; (2) outline/fade/transports; (3) thickening/smoothing/grid/highlight/photo/tweet toggles. Horizontal palette choices also exceed first five.
- Developer: (1) status/permissions; (2) storage/recovery tests; (3) manual checklist and JSON export.
- Notebook: top text/paper/font, paper canvas, bottom insert/item/opacity/Undo/share controls. Empty preview cannot demonstrate layout or selected-item controls.
- Capture: top media/film, lower caption/icon/placement metadata/error; selected photo and selected video differ.
- Walk detail: upper route/metrics/actions and lower note/photos strip.
- Profile: summary/collection links and lower utility/import/export actions.
- Records: week/calendar and lower quick actions/month/history; populated list must be captured.
- LUT: color preview/film and lower custom cube section.

## Relevant dialogs and transient app states

- Root error/info alerts, settings about/limitations and unsupported-auto-detection notices.
- Reset, walk deletion, doodle deletion, shared-paper deletion, spot deletion, LUT deletion.
- Note discard and track-edit discard/delete-point confirmations.
- Menu discard-recording confirmation and paused/active/recovered record controls.
- Replay progress/cancel/export error; photo load/render/error; selected track point and Undo available/unavailable.
- Native menus/pickers: step goal presets, map standard/satellite/3D menu, paper/font/film/icon menus, note insert-photo/route/emoji menu; expanded system time picker.

These are states, not separate unique screens. An exhaustive Cartesian product of color, contents and OS state is unbounded; a manifest must distinguish page, scroll segment, state and system surface.

## OS-owned / physical-device surfaces and unsupported official pages

- System-owned screens: Files import for GPX/TCX/JSON/.cube; PhotosPicker; UIActivityViewController/share destinations. Capture actual OS UIs separately when automation is available. Place shared fixture exports in their own child temp folder because NativeShareView removes the URL's parent folder after sharing.
- Camera and microphone permission/camera preview need physical camera hardware. Simulator camera-unavailable notice is not camera coverage.
- HealthKit permissions and actual authorized workout contents require explicit OS/device testing. Do not substitute fake approval or claim synthetic workout rows are real Health data.
- Location permission/approximate/denied and notifications authorization are OS surfaces, separate from app's developer status rows.
- Live Activity target (`PlainWalkLive/PlainWalkLive.swift`) implements Lock Screen, Dynamic Island expanded, compact, minimal displays. Their compilation does not capture their real SpringBoard rendering. Foreground screenshot app cannot stand in for these surfaces.
- Watch app, ordinary widgets, automated geofence/start settings pages, original nearby exchange flow, cloud invitation/join/sync pages, full original 3D finishes, multiple note pages/day are unimplemented. Do not fabricate screenshots and mark covered.

## Suggested capture scheduling

One compiled app artifact can feed several Simulator capture jobs grouped by app navigation, collections/details and settings/scroll/states. Around 70 images in one 15-minute job risks repeating the prior slow-boot timeout; preserve per-route readiness/actual rendering and add content gates to asynchronous views rather than shortening verification.
