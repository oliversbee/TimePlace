# Time+Place

A BeReal-style iOS app in SwiftUI, built for a shared household: capture a
photo, upload it to Supabase, let each person customize how they see the
rest of the household, and pull everyone's latest photo out with a python
script for display elsewhere (e-paper displays, eventually).

## Features

- **Login only** — email/password against Supabase Auth, no in-app sign-up.
  Accounts are created ahead of time (Authentication -> Users in the
  Supabase dashboard); a matching app-side user record is created
  automatically.
- **Daily prompt** — a local notification fires once a day at a random time
  between 9am and 9pm.
- **Camera capture** — a **Both** / **One** mode toggle. **Both** does
  simultaneous front + back capture via `AVCaptureMultiCamSession` (one
  camera fills the screen, the other appears small in the bottom-right
  corner). **One** just uses whichever camera is currently active. The flip
  button (top-right) swaps which camera is active/main.
- **Upload** — Retake / Upload after capture. Each photo (one for "One"
  mode, two for "Both") is uploaded to Supabase Storage as its own image
  and gets its own row in the `images` table — nothing is
  composited/flattened together.
- **Slide-out menu** — swipe the camera screen right (or drag from the left
  edge) to reveal a panel with **Settings** and **Sign Out**.
- **Settings** — per-user preferences:
  - Display name shown on that person's own display
  - How often their display rotates to the next photo
  - Whether their own photos appear on their own display
  - Per-person show/hide toggles for other household members
  - Per-person **nicknames** — e.g. Oliver sees "Dad", his sister sees
    "Father", for the same person. Private to the viewer; falls back to
    that person's real name if left blank.

## Data model

Three layers, applied via three SQL files, in this order:

**`setup_supabase.sql`** — the core tables:
- **`users`** — `id`, `name`. Auto-populated by a trigger whenever an
  account is created in Authentication -> Users.
- **`images`** — `user_id`, `image_url`, `taken_at`. Every photo ever
  uploaded, one row per photo.
- **`household`** — `user_id`, `recent_image_url`, `recent_taken_at`. One
  row per user, always pointing at their latest photo. Kept current
  automatically by a trigger on `images` — a pull script never has to
  compute "most recent" itself.

**`supabase_add.sql`** — per-user preferences:
- **`user_preferences`** — `user_id`, `display_name`,
  `image_interval_seconds`, `show_own_image`.
- **`hidden_users`** — `(user_id, hidden_user_id)` pairs: who each person
  has chosen not to see.

**`supabase_add_nicknames.sql`** — private nicknames:
- **`nicknames`** — `(viewer_id, target_id, nickname)`. What `viewer_id`
  privately calls `target_id`. Row Level Security keeps this private to the
  viewer — nobody can see what someone else calls them.

**Location is intentionally left out for now.** Easy additive migration
later:
```sql
alter table public.images
  add column latitude double precision,
  add column longitude double precision,
  add column place_name text;
```

## Pulling images (python)

`scripts/pull_recent_images.py` reads the `household` table directly and
prints/downloads each person's latest photo. It uses the Supabase
**service_role** key (not the anon key used by the app) since it's meant to
run somewhere trusted — a server, a Raspberry Pi driving the displays, etc.
Never put the service_role key in the iOS app.

```bash
pip install requests
export SUPABASE_URL="https://YOUR_PROJECT_REF.supabase.co"
export SUPABASE_SERVICE_ROLE_KEY="..."
python scripts/pull_recent_images.py
```

Note: nothing currently reads `nicknames` outside the Settings screen —
there's no feed view yet. Whatever eventually displays other people's names
(in-app or on the e-paper side) should look up `nicknames` for the current
viewer and fall back to `users.name` when there's no entry, same pattern as
`displayLabel()` in `SettingsView.swift`.

## Requirements

- Xcode 15+
- A **physical iPhone XS or newer** to test "Both" capture mode — the
  simulator does not support `AVCaptureMultiCamSession`. "One" camera mode
  and everything else (login, Settings) works fine on the simulator too.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the
  `.xcodeproj` (`brew install xcodegen`, or the `.pkg` installer from
  XcodeGen's GitHub releases if you'd rather skip Homebrew)
- A Supabase project
- Python 3 + `requests` if you want to run the pull script

## 1. Set up Supabase

1. Create a project at [supabase.com](https://supabase.com).
2. In the SQL Editor, run these three files **in order**:
   1. `setup_supabase.sql`
   2. `supabase_add.sql`
   3. `supabase_add_nicknames.sql`
3. In **Authentication -> Users**, manually create your accounts (email +
   password) — there's no in-app sign-up flow, and matching `public.users`
   and `public.user_preferences` rows are created for you automatically.
4. In **Project Settings -> API**, copy your **Project URL** and **anon
   public key** (for the app) and your **service_role key** (for the pull
   script only — Settings -> API -> "service_role" under Project API keys).

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
2. Xcode resolves the `supabase-swift` Swift Package automatically (it's
   declared in `project.yml`). If it doesn't, go to
   **File -> Packages -> Resolve Package Versions**.
3. Plug in a physical iPhone (XS or newer for "Both" mode), select it as
   the run destination, and hit Run. Grant camera and notification
   permissions when prompted.

The `.xcodeproj` itself, along with `xcuserdata/`, `DerivedData/`, and
build output, is intentionally excluded via `.gitignore` — it's generated
from `project.yml`, not hand-edited, so there's nothing to lose by not
committing it. Anyone working on this just runs `xcodegen generate` after
cloning.

## How the pieces fit together

| File | Responsibility |
|---|---|
| `App/TimePlaceApp.swift` | App entry point, requests notification permission on launch |
| `Config/SupabaseConfig.swift` | Supabase project URL + anon key |
| `Models/CapturedImage.swift` | Insert payload for the `images` table |
| `Models/UserPreferences.swift` | Preferences, household members, hidden-users, and nickname models |
| `Services/AuthManager.swift` | Login with existing credentials, session persistence, sign out |
| `Services/NotificationManager.swift` | Schedules the random 9am–9pm daily local notification |
| `Services/CameraManager.swift` | `AVCaptureMultiCamSession` setup, `CaptureMode` (Both/One), capture logic |
| `Services/SupabaseManager.swift` | Uploads photo(s), reads/writes preferences, hidden-users, and nicknames |
| `Views/RootView.swift` | Routes between LoginView and CaptureHomeView based on auth state |
| `Views/LoginView.swift` | Email/password login screen |
| `Views/CameraPreview.swift` | UIKit `AVCaptureVideoPreviewLayer` wrapper for SwiftUI |
| `Views/CameraCaptureView.swift` | The live camera screen with mode picker, flip button, and shutter |
| `Views/CaptureHomeView.swift` | Hosts the camera screen + the swipe-out side menu |
| `Views/Sidemenuview.swift` | The slide-out panel: Settings and Sign Out |
| `Views/SettingsView.swift` | Preferences, rotation interval, show/hide + nicknames for household members |
| `Views/PostPreviewView.swift` | Retake/Upload screen shown after capture |
| `scripts/pull_recent_images.py` | Reads `household`, gets each person's latest photo |

## Notes / things you may want to extend

- **True same-moment-for-everyone notifications**: this version schedules a
  random time *per device*. A server-pushed version needs a scheduled
  backend job (e.g. a Supabase Edge Function on a cron trigger) plus APNs
  push.
- **Displays**: not modeled in the database at all right now — deliberately
  left to the python side. If you later want the displays themselves to
  know things (which display shows which user, when it was last seen,
  etc.), that's a small addition when you get there.
- **Late flag**: `taken_at` is stored, so you could compare it against the
  scheduled notification time to show a "posted X late" indicator later.
- **Remembering the last capture mode chosen**: `captureMode` currently
  resets to "Both" each time the capture screen appears. Persist it with
  `@AppStorage` if you want it to remember the user's last choice.
- **Nicknames aren't shown anywhere yet** outside Settings — see the note
  under "Pulling images" above for where to hook this in once there's a
  feed or display view that lists people by name.
