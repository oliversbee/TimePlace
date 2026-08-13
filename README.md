# Time+Place

A minimal BeReal-style iOS app in SwiftUI:

- Log in with an email/password account that already exists in Supabase Auth (no sign-up screen).
- A local notification fires once a day at a random time between 9am and 9pm.
- Tapping into the app opens a camera capture screen. A segmented control lets
  you choose **Both** (simultaneous front + back capture via
  `AVCaptureMultiCamSession` — one camera fills the screen, the other appears
  small in the bottom-right corner) or **One** (just whichever camera is
  currently active). The flip button (top-right) swaps which camera is active/main.
- After capture you get a preview with **Retake** / **Upload**. In "Both" mode,
  upload flattens both photos into one image; in "One" mode it uploads the
  single photo as-is. Either way it's sent to Supabase Storage, and a row is
  inserted into a `posts` table.

## Requirements

- Xcode 15+
- A **physical iPhone XS or newer** to test the "Both" capture mode — the
  simulator does not support `AVCaptureMultiCamSession`. "One" camera mode
  works fine on the simulator too.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the `.xcodeproj`
  (`brew install xcodegen`)
- A Supabase project

## 1. Set up Supabase

1. Create a project at [supabase.com](https://supabase.com).
2. In the SQL Editor, run `setup_supabase.sql` from this folder. It creates the
   `posts` table, row-level security policies, and a public `posts` storage bucket.
3. In **Authentication -> Users**, manually create the user account(s) that will
   log into the app (email + password) — there's no in-app sign-up flow by design.
4. In **Project Settings -> API**, copy your **Project URL** and **anon public key**.

## 2. Configure the app

Open `TimePlace/Config/SupabaseConfig.swift` and fill in:

```swift
static let url = URL(string: "https://YOUR_PROJECT_REF.supabase.co")!
static let anonKey = "YOUR_SUPABASE_ANON_KEY"
```

## 3. Generate and open the Xcode project

```bash
cd TimePlace
xcodegen generate
open TimePlace.xcodeproj
```

In Xcode:

1. Select the `TimePlace` target -> **Signing & Capabilities** -> set your
   Development Team (needed to run on a physical device).
2. Xcode will resolve the `supabase-swift` Swift Package automatically (it's
   declared in `project.yml`). If it doesn't, go to
   **File -> Packages -> Resolve Package Versions**.
3. Plug in a physical iPhone (XS or newer for "Both" mode), select it as the
   run destination, and hit Run. Grant camera and notification permissions
   when prompted.

## How the pieces fit together

| File | Responsibility |
|---|---|
| `Services/AuthManager.swift` | Login with existing credentials, session persistence |
| `Services/NotificationManager.swift` | Schedules the random 9am–9pm daily local notification |
| `Services/CameraManager.swift` | `AVCaptureMultiCamSession` setup, `CaptureMode` (Both/One), capture logic |
| `Services/ImageCompositor.swift` | Flattens main + corner photo into one image (only used in "Both" mode) |
| `Services/SupabaseManager.swift` | Uploads the photo to Storage and inserts the `posts` row |
| `Views/CameraCaptureView.swift` | The live camera screen with mode picker, flip button, and shutter |
| `Views/PostPreviewView.swift` | Retake/Upload screen shown after capture |

## Notes / things you may want to extend

- **True same-moment-for-everyone notifications**: this version schedules a
  random time *per device*. The real BeReal has a server pick one random time
  and push it to everyone at once — that needs a scheduled server job (e.g. a
  Supabase Edge Function on a cron trigger) plus APNs push, which is a bigger
  lift than a local notification.
- **Feed / friends**: there's no feed screen here — only capture → upload, per
  your spec. A `posts` table already exists if you want to add one later.
- **Late flag**: `taken_at` is stored, so you could compare it against the
  scheduled notification time to show a "posted X late" badge later.
- **Remembering the last mode chosen**: `captureMode` currently resets to
  "Both" each time the capture screen appears. If you want it to remember the
  user's last choice, persist it (e.g. `@AppStorage`) instead of a plain
  `@Published` var on `CameraManager`.
