# TimePlace — main.py
#
# Orchestrates the full device lifecycle:
#   1. Wi-Fi connection (delegated to wificonnect.py)
#   2. Device identity (device_id + device_secret, stored in flash)
#   3. Device claiming (shows claim code until the app pairs it)
#   4. Photo cache refresh (downloads new images on a slow interval)
#   5. Photo cycle loop (displays cached images on a fast interval)
#
# The display interval comes from user_preferences.image_interval_seconds,
# pulled from device-images on each cache refresh. The nickname drawn on
# the photo's bottom-left corner is contrasted against the local pixel
# brightness at that corner.

import gc
import json
import os
import time
import random
import ubinascii
import machine

import urequests
import inky_frame

from wificonnect import (
    graphics,
    text,
    clear_display,
    connect_wifi,
    load_config,
    save_config,
    remove_config,
    provisioning,
    portrait_to_landscape_rect,
    PORTRAIT_WIDTH,
    PORTRAIT_HEIGHT,
)

BLACK = inky_frame.BLACK
WHITE = inky_frame.WHITE


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

SUPABASE_URL       = "https://ihqntnpikgjzvzmeqqcs.supabase.co"
DEVICE_STATUS_URL  = SUPABASE_URL + "/functions/v1/device-status"
DEVICE_IMAGES_URL  = SUPABASE_URL + "/functions/v1/device-images"

DEVICE_CONFIG_FILE = "device_config.json"

# How often to contact the server for a fresh list of images and download any
# new ones. 3600 = one hour.
IMAGE_REFRESH_SECONDS = 3600

# Fallback display interval used when the server doesn't send a preference.
# The real value comes from user_preferences.image_interval_seconds and is
# pulled at every cache refresh.
DEFAULT_IMAGE_DISPLAY_SECONDS = 60

# How often to poll device-status while waiting for the user to claim.
CLAIM_POLL_SECONDS = 5

# Cap on how many images to keep cached on disk.
MAX_CACHED_IMAGES = 30

# Network request timeout, in seconds.
HTTP_TIMEOUT = 20

# Cache storage.
CACHE_DIR     = "/sd/timeplace_cache"
MANIFEST_FILE = CACHE_DIR + "/manifest.json"

# Native panel dimensions (landscape, because the display is created with
# rotate=0 and all UI is drawn rotated by wificonnect.py).
NATIVE_W = 800
NATIVE_H = 480


# ---------------------------------------------------------------------------
# SD card
# ---------------------------------------------------------------------------

def mount_sd():
    try:
        import sdcard
        import uos

        sd_spi = machine.SPI(
            0,
            sck=machine.Pin(18, machine.Pin.OUT),
            mosi=machine.Pin(19, machine.Pin.OUT),
            miso=machine.Pin(16, machine.Pin.OUT),
        )

        sd = sdcard.SDCard(sd_spi, machine.Pin(22))
        uos.mount(sd, "/sd")

        print("SD card mounted.")
        gc.collect()
        return True

    except Exception as exc:
        print("SD card mount failed:", exc)
        return False


def ensure_cache_dir():
    try:
        os.mkdir(CACHE_DIR)
    except OSError:
        pass


# ---------------------------------------------------------------------------
# Device identity
# ---------------------------------------------------------------------------

def load_or_create_device_identity():
    try:
        with open(DEVICE_CONFIG_FILE, "r") as f:
            data = json.load(f)
        if data.get("device_id") and data.get("device_secret"):
            return data["device_id"], data["device_secret"]
    except Exception:
        pass

    device_id = "pico-" + ubinascii.hexlify(machine.unique_id()).decode().lower()

    alphabet = "0123456789abcdef"
    device_secret = "".join(random.choice(alphabet) for _ in range(32))

    try:
        with open(DEVICE_CONFIG_FILE, "w") as f:
            json.dump(
                {"device_id": device_id, "device_secret": device_secret},
                f,
            )
        print("Saved new device identity:", device_id)
    except Exception as exc:
        print("Could not save device identity:", exc)

    return device_id, device_secret


# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------

def post_json(url, payload):
    try:
        body = json.dumps(payload)
        response = urequests.post(
            url,
            data=body,
            headers={"Content-Type": "application/json"},
        )
        status = response.status_code
        text_body = response.text
        response.close()

        try:
            parsed = json.loads(text_body)
        except Exception:
            parsed = None

        return status, parsed, None

    except Exception as exc:
        return None, None, str(exc)


def download_image(url, path):
    try:
        response = urequests.get(url)
        status = response.status_code

        if status != 200:
            print("Download HTTP status:", status)
            response.close()
            return False

        content = response.content
        response.close()

        with open(path, "wb") as f:
            f.write(content)

        return True

    except Exception as exc:
        print("Download error:", exc)
        return False


# ---------------------------------------------------------------------------
# Cache manifest
# ---------------------------------------------------------------------------

def load_manifest():
    try:
        with open(MANIFEST_FILE, "r") as f:
            data = json.load(f)
        if not isinstance(data, dict):
            raise ValueError("bad manifest")
        data.setdefault("images", [])
        data.setdefault("last_refresh", 0)
        data.setdefault("preferences", {})
        data.setdefault("nicknames", {})
        data.setdefault("hidden_users", [])
        return data
    except Exception:
        return {
            "images": [],
            "last_refresh": 0,
            "preferences": {},
            "nicknames": {},
            "hidden_users": [],
        }


def save_manifest(manifest):
    try:
        with open(MANIFEST_FILE, "w") as f:
            json.dump(manifest, f)
        return True
    except Exception as exc:
        print("Manifest save failed:", exc)
        return False


# ---------------------------------------------------------------------------
# Display screens (portrait, 480 x 800)
# ---------------------------------------------------------------------------

def show_status(title, lines, footer=None):
    try:
        graphics.set_pen(WHITE)
        graphics.clear()

        y = 60
        text(title, 20, y, PORTRAIT_WIDTH - 40, 3)
        y += 60

        for line in lines:
            text(line, 20, y, PORTRAIT_WIDTH - 40, 2)
            y += 40

        if footer:
            text(footer, 20, PORTRAIT_HEIGHT - 60, PORTRAIT_WIDTH - 40, 2)

        graphics.update()
        gc.collect()
    except Exception as exc:
        print("show_status error:", exc)


def show_claim_code(claim_code):
    try:
        graphics.set_pen(WHITE)
        graphics.clear()

        text("TimePlace", 20, 60, PORTRAIT_WIDTH - 40, 3)
        text("Pair this frame", 20, 120, PORTRAIT_WIDTH - 40, 2)

        y = 240
        text("Open the TimePlace app", 20, y, PORTRAIT_WIDTH - 40, 2)
        y += 40
        text("on your phone and enter", 20, y, PORTRAIT_WIDTH - 40, 2)
        y += 40
        text("this code:", 20, y, PORTRAIT_WIDTH - 40, 2)

        y = 440
        text(claim_code, 20, y, PORTRAIT_WIDTH - 40, 5)

        y = 620
        text("Waiting for pairing...", 20, y, PORTRAIT_WIDTH - 40, 2)
        text("Keep this screen on.", 20, y + 40, PORTRAIT_WIDTH - 40, 2)

        graphics.update()
        gc.collect()
    except Exception as exc:
        print("show_claim_code error:", exc)


# ---------------------------------------------------------------------------
# Framebuffer sampling for nickname contrast
# ---------------------------------------------------------------------------

def _get_pixel_pen(lx, ly):
    """Return the pen value at landscape pixel (lx, ly), or None if
    the framebuffer cannot be read."""
    # Try get_pixel if the build exposes it.
    try:
        v = graphics.get_pixel(lx, ly)
        if isinstance(v, int):
            return v
    except Exception:
        pass

    # Try direct buffer access.
    try:
        buf = graphics.buffer
        if callable(buf):
            buf = buf()
        buf_len = len(buf)
    except Exception:
        return None

    if not (0 <= lx < NATIVE_W and 0 <= ly < NATIVE_H):
        return None

    # 4bpp packed (two pixels per byte). This is the common layout for
    # Inky Frame Spectra panels.
    if buf_len == (NATIVE_W * NATIVE_H) // 2:
        idx = ly * (NATIVE_W // 2) + (lx >> 1)
        if idx >= buf_len:
            return None
        b = buf[idx]
        return (b >> 4) if (lx & 1) == 0 else (b & 0x0F)

    # 8bpp
    if buf_len == NATIVE_W * NATIVE_H:
        return buf[idx] if False else buf[ly * NATIVE_W + lx]

    return None


def _is_portrait_region_dark(px, py, pw, ph, sample_step=8):
    """Sample a portrait-space rectangle, return True if mostly black."""
    lx1, ly1, lw, lh = portrait_to_landscape_rect(px, py, pw, ph)

    black = BLACK
    dark = 0
    total = 0

    for ly in range(ly1, ly1 + lh, sample_step):
        for lx in range(lx1, lx1 + lw, sample_step):
            v = _get_pixel_pen(lx, ly)
            if v is None:
                continue
            total += 1
            if v == black:
                dark += 1

    if total == 0:
        return False  # Can't read; assume light and draw black text.

    return (dark / total) > 0.5


# ---------------------------------------------------------------------------
# Image display
# ---------------------------------------------------------------------------

def display_photo(path, nickname=None):
    """Draw the image and optionally overlay the owner's nickname at the
    portrait bottom-left, with automatic white-vs-black text contrast.

    Full-scale decode only. Scaled decodes on this panel trigger the strip
    artifact, so we never pass a scale argument to jpeg.decode().
    """
    try:
        import jpegdec
    except ImportError:
        print("jpegdec module not available")
        show_status("Image error", ["jpegdec module missing."])
        return False

    try:
        jpeg = jpegdec.JPEG(graphics)
        jpeg.open_file(path)

        graphics.set_pen(WHITE)
        graphics.clear()
        jpeg.decode()

        if nickname:
            # Portrait bottom-left footer.
            footer_x = 20
            footer_y = PORTRAIT_HEIGHT - 60
            footer_w = PORTRAIT_WIDTH - 40
            footer_h = 40

            is_dark = _is_portrait_region_dark(
                footer_x, footer_y, footer_w, footer_h
            )
            pen = WHITE if is_dark else BLACK

            print(
                "Nickname footer:",
                "dark area -> white text"
                if is_dark else "light area -> black text",
            )

            text(
                nickname,
                footer_x,
                footer_y,
                footer_w,
                2,
                pen=pen,
            )

        graphics.update()
        gc.collect()
        return True

    except Exception as exc:
        print("display_photo error:", exc)
        show_status("Image error", ["Could not display image."])
        return False


# ---------------------------------------------------------------------------
# Cache refresh (network-touching, slow interval)
# ---------------------------------------------------------------------------

def refresh_image_cache(device_id, device_secret):
    print("Refreshing image cache...")

    status, data, err = post_json(
        DEVICE_IMAGES_URL,
        {"device_id": device_id, "device_secret": device_secret},
    )

    if err is not None or status != 200 or not isinstance(data, dict):
        print("device-images failed:", status, err, data)
        return len(load_manifest().get("images", []))

    if data.get("claimed") is not True:
        return None

    server_images = data.get("images") or []
    server_images = server_images[:MAX_CACHED_IMAGES]
    server_ids = set(img["id"] for img in server_images)

    preferences = data.get("preferences") or {}
    nicknames   = data.get("nicknames") or {}
    hidden      = data.get("hidden_users") or []

    manifest = load_manifest()
    old_entries = manifest.get("images", [])

    surviving = [entry for entry in old_entries if entry["id"] in server_ids]
    surviving_ids = set(entry["id"] for entry in surviving)

    for img in server_images:
        img_id = img["id"]
        if img_id in surviving_ids:
            continue

        url = img.get("url")
        if not url:
            continue

        filename = CACHE_DIR + "/" + img_id + ".jpg"
        print("Downloading new image:", img_id)

        if download_image(url, filename):
            surviving.append({
                "id": img_id,
                "user_id": img.get("user_id"),
                "taken_at": img.get("taken_at"),
                "filename": filename,
            })
            surviving_ids.add(img_id)

    for entry in old_entries:
        if entry["id"] not in server_ids:
            try:
                os.remove(entry["filename"])
                print("Removed cached image:", entry["id"])
            except Exception:
                pass

    try:
        interval = int(
            preferences.get(
                "image_interval_seconds",
                DEFAULT_IMAGE_DISPLAY_SECONDS,
            )
        )
    except Exception:
        interval = DEFAULT_IMAGE_DISPLAY_SECONDS
    if interval < 5:
        interval = 5

    new_manifest = {
        "images": surviving,
        "last_refresh": time.time(),
        "preferences": {
            "image_interval_seconds": interval,
            "show_own_image": bool(preferences.get("show_own_image", True)),
        },
        "nicknames": nicknames,
        "hidden_users": hidden,
    }
    save_manifest(new_manifest)

    print(
        "Cache refresh complete:",
        len(surviving),
        "image(s), interval =",
        interval,
        "s,",
        len(nicknames),
        "nickname(s),",
        len(hidden),
        "hidden user(s)",
    )
    return len(surviving)


# ---------------------------------------------------------------------------
# Claim flow
# ---------------------------------------------------------------------------

def wait_for_claim(device_id, device_secret):
    last_code = None

    while True:
        status, data, err = post_json(
            DEVICE_STATUS_URL,
            {"device_id": device_id, "device_secret": device_secret},
        )

        if err is not None or status != 200 or not isinstance(data, dict):
            print("device-status failed:", status, err, data)
            show_status(
                "Server unavailable",
                ["Retrying in 10 seconds..."],
            )
            time.sleep(10)
            continue

        if data.get("claimed") is True:
            print("Device is claimed.")
            return True

        claim_code = data.get("claim_code")
        if claim_code and claim_code != last_code:
            last_code = claim_code
            print("Claim code:", claim_code)
            show_claim_code(claim_code)

        time.sleep(CLAIM_POLL_SECONDS)


# ---------------------------------------------------------------------------
# Wi-Fi
# ---------------------------------------------------------------------------

def ensure_wifi():
    config = load_config()
    if config and connect_wifi(config[0], config[1]):
        return True

    if config:
        remove_config()

    while True:
        ssid, password = provisioning()
        if connect_wifi(ssid, password):
            save_config(ssid, password)
            return True

        remove_config()
        show_status(
            "Wi-Fi failed",
            [
                "Could not connect to",
                "the network you chose.",
                "",
                "Restarting setup...",
            ],
        )
        time.sleep(5)
        gc.collect()


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    print("TimePlace starting")

    ensure_wifi()
    print("Wi-Fi connected")

    if not mount_sd():
        show_status(
            "Storage error",
            ["Could not mount the SD card."],
        )
        raise RuntimeError("SD card not available")
    ensure_cache_dir()

    device_id, device_secret = load_or_create_device_identity()
    print("device_id:", device_id)

    show_status("Starting up...", ["Checking pairing status..."])
    wait_for_claim(device_id, device_secret)

    result = refresh_image_cache(device_id, device_secret)
    if result is None:
        wait_for_claim(device_id, device_secret)
        refresh_image_cache(device_id, device_secret)

    manifest = load_manifest()
    last_refresh = manifest.get("last_refresh", 0)
    index = 0

    while True:
        # Refresh cache on a slow interval.
        if time.time() - last_refresh >= IMAGE_REFRESH_SECONDS:
            result = refresh_image_cache(device_id, device_secret)

            if result is None:
                wait_for_claim(device_id, device_secret)
                refresh_image_cache(device_id, device_secret)

            manifest = load_manifest()
            last_refresh = manifest.get("last_refresh", 0)
            index = 0

        images = manifest.get("images", [])

        if not images:
            show_status(
                "No photos yet",
                [
                    "Add photos in the app",
                    "to see them here.",
                    "",
                    "Checking again soon...",
                ],
            )
            time.sleep(60)
            last_refresh = 0
            continue

        entry = images[index % len(images)]
        index = (index + 1) % len(images)

        owner_id = entry.get("user_id")
        nicknames = manifest.get("nicknames", {})
        hidden_users = set(manifest.get("hidden_users", []))

        # Defence in depth: the server already filters, but skip locally
        # if the manifest is stale relative to a fresh hide.
        if owner_id in hidden_users:
            continue

        nickname = nicknames.get(owner_id)

        display_photo(entry["filename"], nickname=nickname)

        interval = manifest.get("preferences", {}).get(
            "image_interval_seconds",
            DEFAULT_IMAGE_DISPLAY_SECONDS,
        )
        time.sleep(interval)


if __name__ == "__main__":
    main()
