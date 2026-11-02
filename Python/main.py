# TimePlace — main.py
#
# Battery-optimised lifecycle:
#   1. Wake (Pico resets; main.py runs from the top)
#   2. Mount SD, load state from disk
#   3. If not claimed: poll device-status once, show claim code if changed,
#      sleep briefly, repeat
#   4. If claimed: if hourly refresh is due, connect WiFi, refresh cache,
#      disconnect WiFi
#   5. Show the next cached image (no WiFi needed)
#   6. Deep sleep for the configured display interval
#
# All state that must survive sleep is persisted to SD card, because deep
# sleep resets the Pico and clears RAM.

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

# How often to contact the server for a fresh list of images. 3600 = 1 hour.
IMAGE_REFRESH_SECONDS = 3600

# Fallback display interval if the server preference is missing. Real value
# comes from user_preferences.image_interval_seconds.
DEFAULT_IMAGE_DISPLAY_SECONDS = 60

# Minimum display interval. Values below this are clamped up, because the
# panel refresh alone takes 12-15s and anything faster would burn batteries.
MIN_DISPLAY_INTERVAL_SECONDS = 60

# Cap on cached images.
MAX_CACHED_IMAGES = 30

# Cache storage.
CACHE_DIR     = "/sd/timeplace_cache"
MANIFEST_FILE = CACHE_DIR + "/manifest.json"
STATE_FILE    = CACHE_DIR + "/state.json"

# Native panel dimensions (landscape; UI is drawn rotated by wificonnect.py).
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
# State (survives deep sleep via SD card)
# ---------------------------------------------------------------------------

def load_state():
    defaults = {
        "is_claimed": False,
        "shown_claim_code": "",
        "last_displayed": "",
        "image_index": 0,
        "wake_count": 0,
        "seconds_since_refresh": 0,
        "force_refresh": True,
    }
    try:
        with open(STATE_FILE, "r") as f:
            data = json.load(f)
        for k, v in defaults.items():
            data.setdefault(k, v)
        return data
    except Exception:
        return defaults


def save_state(state):
    try:
        with open(STATE_FILE, "w") as f:
            json.dump(state, f)
        return True
    except Exception as exc:
        print("State save failed:", exc)
        return False


# ---------------------------------------------------------------------------
# Manifest
# ---------------------------------------------------------------------------

def load_manifest():
    try:
        with open(MANIFEST_FILE, "r") as f:
            data = json.load(f)
        if not isinstance(data, dict):
            raise ValueError("bad manifest")
        data.setdefault("images", [])
        data.setdefault("preferences", {})
        data.setdefault("nicknames", {})
        data.setdefault("hidden_users", [])
        return data
    except Exception:
        return {
            "images": [],
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
# WiFi teardown — critical before sleep
# ---------------------------------------------------------------------------

def turn_off_wifi():
    """Properly tear down WiFi before deep sleep.

    If the radio is left active, the Pico either wakes immediately or keeps
    drawing current trying to maintain a dead link.
    """
    try:
        import network
        wlan = network.WLAN(network.STA_IF)
        try:
            wlan.disconnect()
        except Exception:
            pass
        try:
            wlan.active(False)
        except Exception:
            pass
        try:
            wlan.deinit()
        except Exception:
            pass
        del wlan
        gc.collect()
        time.sleep_ms(1)
    except Exception:
        pass


# ---------------------------------------------------------------------------
# Display screens
# ---------------------------------------------------------------------------

def show_status(title, lines):
    try:
        graphics.set_pen(WHITE)
        graphics.clear()

        y = 60
        text(title, 20, y, PORTRAIT_WIDTH - 40, 3)
        y += 60

        for line in lines:
            text(line, 20, y, PORTRAIT_WIDTH - 40, 2)
            y += 40

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
    try:
        v = graphics.get_pixel(lx, ly)
        if isinstance(v, int):
            return v
    except Exception:
        pass

    try:
        buf = graphics.buffer
        if callable(buf):
            buf = buf()
        buf_len = len(buf)
    except Exception:
        return None

    if not (0 <= lx < NATIVE_W and 0 <= ly < NATIVE_H):
        return None

    if buf_len == (NATIVE_W * NATIVE_H) // 2:
        idx = ly * (NATIVE_W // 2) + (lx >> 1)
        if idx >= buf_len:
            return None
        b = buf[idx]
        return (b >> 4) if (lx & 1) == 0 else (b & 0x0F)

    if buf_len == NATIVE_W * NATIVE_H:
        return buf[ly * NATIVE_W + lx]

    return None


def _is_portrait_region_dark(px, py, pw, ph, sample_step=8):
    lx1, ly1, lw, lh = portrait_to_landscape_rect(px, py, pw, ph)
    dark = 0
    total = 0
    for ly in range(ly1, ly1 + lh, sample_step):
        for lx in range(lx1, lx1 + lw, sample_step):
            v = _get_pixel_pen(lx, ly)
            if v is None:
                continue
            total += 1
            if v == BLACK:
                dark += 1
    if total == 0:
        return False
    return (dark / total) > 0.5


# ---------------------------------------------------------------------------
# Image display
# ---------------------------------------------------------------------------

def display_photo(path, nickname=None):
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
            footer_x = 20
            footer_y = PORTRAIT_HEIGHT - 60
            footer_w = PORTRAIT_WIDTH - 40
            footer_h = 40

            is_dark = _is_portrait_region_dark(
                footer_x, footer_y, footer_w, footer_h
            )
            pen = WHITE if is_dark else BLACK

            text(nickname, footer_x, footer_y, footer_w, 2, pen=pen)

        graphics.update()
        gc.collect()
        return True

    except Exception as exc:
        print("display_photo error:", exc)
        show_status("Image error", ["Could not display image."])
        return False


# ---------------------------------------------------------------------------
# Cache refresh
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
    nicknames = data.get("nicknames") or {}
    hidden = data.get("hidden_users") or []

    manifest = load_manifest()
    old_entries = manifest.get("images", [])

    surviving = [e for e in old_entries if e["id"] in server_ids]
    surviving_ids = set(e["id"] for e in surviving)

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
            except Exception:
                pass

    try:
        interval = int(
            preferences.get("image_interval_seconds", DEFAULT_IMAGE_DISPLAY_SECONDS)
        )
    except Exception:
        interval = DEFAULT_IMAGE_DISPLAY_SECONDS

    if interval < MIN_DISPLAY_INTERVAL_SECONDS:
        interval = MIN_DISPLAY_INTERVAL_SECONDS

    save_manifest({
        "images": surviving,
        "preferences": {
            "image_interval_seconds": interval,
            "show_own_image": bool(preferences.get("show_own_image", True)),
        },
        "nicknames": nicknames,
        "hidden_users": hidden,
    })

    print("Cache refresh complete:", len(surviving), "image(s)")
    return len(surviving)

# ---------------------------------------------------------------------------
# Wi-Fi
# ---------------------------------------------------------------------------

def ensure_wifi():
    """Connect to saved Wi-Fi, running provisioning only if no config exists.

    Returns True on success, False otherwise. Unlike the original version,
    a transient connection failure on a saved network does NOT trigger
    reprovisioning - that would leave the device stuck in AP mode and
    drain the battery. The caller sleeps and retries on the next wake.

    Full provisioning (access point + setup screen) only runs when there
    is no saved config at all, which is the one-time first-boot case.
    """
    config = load_config()

    if config:
        if connect_wifi(config[0], config[1]):
            return True
        print("Saved Wi-Fi failed to connect; will retry next wake")
        return False

    # No saved config - run the full setup flow (blocking).
    while True:
        ssid, password = provisioning()
        if connect_wifi(ssid, password):
            save_config(ssid, password)
            return True

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
# Main
# ---------------------------------------------------------------------------

def main():
    print("TimePlace starting")

    if not mount_sd():
        show_status("Storage error", ["Could not mount the SD card."])
        inky_frame.sleep_for(1)
        return

    ensure_cache_dir()

    state = load_state()
    manifest = load_manifest()
    device_id, device_secret = load_or_create_device_identity()

    print("device_id:", device_id)
    print("wake_count:", state.get("wake_count", 0))

    # -------------------------------------------------------------------
    # Claim mode
    # -------------------------------------------------------------------
    if not state.get("is_claimed"):
        if not ensure_wifi():
            token = "error:wifi"
            if state.get("last_displayed") != token:
                if state.get("shown_claim_code"):
                    show_claim_code(state["shown_claim_code"])
                else:
                    show_status("No WiFi", ["Retrying shortly..."])
                state["last_displayed"] = token
                save_state(state)
            inky_frame.sleep_for(1)
            return

        status, data, err = post_json(
            DEVICE_STATUS_URL,
            {"device_id": device_id, "device_secret": device_secret},
        )

        if err is not None or status != 200 or not isinstance(data, dict):
            print("device-status failed:", status, err)
            turn_off_wifi()
            token = "error:status"
            if state.get("last_displayed") != token:
                if state.get("shown_claim_code"):
                    show_claim_code(state["shown_claim_code"])
                else:
                    show_status("Server unavailable", ["Retrying shortly..."])
                state["last_displayed"] = token
                save_state(state)
            inky_frame.sleep_for(1)
            return

        if data.get("claimed") is True:
            print("Device is claimed.")
            state["is_claimed"] = True
            state["force_refresh"] = True
            state["last_displayed"] = ""
            save_state(state)
            # Fall through to display mode; WiFi is still connected.
        else:
            code = data.get("claim_code", "")
            token = "claim:" + code
            if code and state.get("last_displayed") != token:
                show_claim_code(code)
                state["last_displayed"] = token
                state["shown_claim_code"] = code
                save_state(state)
            turn_off_wifi()
            inky_frame.sleep_for(1)
            return

    # -------------------------------------------------------------------
    # Display mode
    # -------------------------------------------------------------------
    state["wake_count"] = state.get("wake_count", 0) + 1

    interval = manifest.get("preferences", {}).get(
        "image_interval_seconds", DEFAULT_IMAGE_DISPLAY_SECONDS
    )
    if interval < MIN_DISPLAY_INTERVAL_SECONDS:
        interval = MIN_DISPLAY_INTERVAL_SECONDS

    sleep_minutes = (interval + 59) // 60
    actual_sleep_seconds = sleep_minutes * 60

    # -------------------------------------------------------------------
    # Refresh if due
    # -------------------------------------------------------------------
    if state.get("force_refresh") or state["seconds_since_refresh"] >= IMAGE_REFRESH_SECONDS:
        print("Refreshing cache (WiFi on)...")
        if ensure_wifi():
            result = refresh_image_cache(device_id, device_secret)
            turn_off_wifi()

            if result is None:
                print("Device became unclaimed.")
                state["is_claimed"] = False
                state["shown_claim_code"] = ""
                state["last_displayed"] = ""
                save_state(state)
                inky_frame.sleep_for(1)
                return

            manifest = load_manifest()
            state["seconds_since_refresh"] = 0
            state["force_refresh"] = False
            state["image_index"] = 0
        else:
            print("WiFi failed, will retry next wake")
            turn_off_wifi()
            if not manifest.get("images"):
                token = "status:nowifi"
                if state.get("last_displayed") != token:
                    show_status("No WiFi", ["Retrying shortly..."])
                    state["last_displayed"] = token
                save_state(state)
                inky_frame.sleep_for(1)
                return
    else:
        # WiFi should be off. Make sure.
        turn_off_wifi()

    # -------------------------------------------------------------------
    # Show next image
    # -------------------------------------------------------------------
    images = manifest.get("images", [])
    hidden = set(manifest.get("hidden_users", []))

    if not images:
        token = "status:nophotos"
        if state.get("last_displayed") != token:
            show_status("No photos yet", [
                "Add photos in the app",
                "to see them here.",
            ])
            state["last_displayed"] = token
        state["force_refresh"] = True
        state["seconds_since_refresh"] = 0
        save_state(state)
        inky_frame.sleep_for(1)
        return

    shown = False
    for _ in range(len(images)):
        idx = state["image_index"] % len(images)
        entry = images[idx]
        state["image_index"] = (idx + 1) % len(images)

        if entry.get("user_id") in hidden:
            continue

        token = "image:" + entry["id"]
        nickname = manifest.get("nicknames", {}).get(entry.get("user_id"))

        if state.get("last_displayed") != token:
            display_photo(entry["filename"], nickname=nickname)
            state["last_displayed"] = token
        else:
            print("Same image already on screen, skipping redraw")
        shown = True
        break

    if not shown:
        token = "status:allhidden"
        if state.get("last_displayed") != token:
            show_status("No photos", ["All photos hidden."])
            state["last_displayed"] = token

    # Accumulate time and save before sleeping
    state["seconds_since_refresh"] += actual_sleep_seconds
    save_state(state)

    turn_off_wifi()

    print("Sleeping", sleep_minutes, "minute(s)")
    inky_frame.sleep_for(sleep_minutes)


if __name__ == "__main__":
    main()
