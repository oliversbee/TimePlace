# TimePlace Wi-Fi setup test with manual rotation.
#
# MANUAL ROTATION
# ---------------
# The Inky Frame 7.3" panel is a native 800x480 landscape display. This file
# draws a portrait (480x800) UI by transforming every drawing operation,
# rather than relying on PicoGraphics rotate=.
#
# ORIENTATION selects which landscape edge becomes the bottom of the
# portrait view:
#
#   "left_bottom"   -> landscape LEFT edge becomes portrait BOTTOM
#                      (equivalently: rotate the physical panel 90 deg
#                       counter-clockwise to view it in portrait)
#   "right_bottom"  -> landscape RIGHT edge becomes portrait BOTTOM
#                      (rotate 90 deg clockwise to view portrait)
#
# If the UI comes out upside-down, switch between the two values.

import gc
import framebuf
import network
import socket
import time
import random
import machine
import ubinascii
import ujson
import inky_frame
from picographics import PicoGraphics, DISPLAY_INKY_FRAME_SPECTRA_7

CONFIG_FILE = "wificonnect_config.json"
SETUP_IP = "192.168.4.1"
SETUP_URL = "http://192.168.4.1"

# ----- Orientation ---------------------------------------------------------
ORIENTATION = "left_bottom"

# Native panel dimensions (landscape)
LANDSCAPE_W = 800
LANDSCAPE_H = 480

# Portrait virtual dimensions the UI is designed for
PORTRAIT_WIDTH = 480
PORTRAIT_HEIGHT = 800

# ----- Graphics ------------------------------------------------------------
# No rotation at the driver level.
graphics = PicoGraphics(DISPLAY_INKY_FRAME_SPECTRA_7, rotate=0)

BLACK = inky_frame.BLACK
WHITE = inky_frame.WHITE


# ----- Coordinate transform ------------------------------------------------
def portrait_to_landscape_rect(px, py, pw, ph):
    """Map a portrait rectangle to the corresponding landscape rectangle."""
    if ORIENTATION == "left_bottom":
        lx = LANDSCAPE_W - py - ph
        ly = px
        lw = ph
        lh = pw
    elif ORIENTATION == "right_bottom":
        lx = py
        ly = LANDSCAPE_H - px - pw
        lw = ph
        lh = pw
    else:
        raise ValueError("Unknown ORIENTATION: " + ORIENTATION)
    return lx, ly, lw, lh


def rect_portrait(x, y, w, h):
    """Draw a filled rectangle using portrait coordinates."""
    if w <= 0 or h <= 0:
        return
    lx, ly, lw, lh = portrait_to_landscape_rect(x, y, w, h)
    graphics.rectangle(lx, ly, lw, lh)


# ----- Rotated text --------------------------------------------------------
# PicoGraphics has no rotated-text support, so each string is rendered into
# a small framebuf (MONO_VLSB, 8x8 font) and then the set pixels are copied
# into the main buffer as small rotated rectangles.
#
# The effective scale is automatically reduced if the string would otherwise
# overflow the supplied width. The requested scale is treated as a maximum.

_MAX_TEXT_LEN = 64
_SCRATCH_W = _MAX_TEXT_LEN * 8
_SCRATCH_H = 8
_scratch = bytearray(_SCRATCH_W * _SCRATCH_H // 8)
_scratch_fb = framebuf.FrameBuffer(
    _scratch, _SCRATCH_W, _SCRATCH_H, framebuf.MONO_VLSB
)

_CHAR_W = 8   # width of one glyph in the framebuf 8x8 font


def _pick_scale(text_len, max_scale, max_width):
    """Return the largest integer scale <= max_scale that fits in max_width."""
    if text_len <= 0 or max_width <= 0:
        return 1
    scale = max_scale
    while scale > 1 and (text_len * _CHAR_W * scale) > max_width:
        scale -= 1
    return scale


def text(value, x, y, width=PORTRAIT_WIDTH, scale=2, pen=None):
    """Draw a string so that it reads correctly in the portrait view.

    The string is clipped and shrunk to fit inside `width` pixels, starting
    at portrait coordinates (x, y). `scale` is the maximum glyph scale.
    `pen` selects the drawing colour; defaults to BLACK.
    """
    if pen is None:
        pen = BLACK

    s = str(value)
    if not s:
        return

    if len(s) > _MAX_TEXT_LEN:
        s = s[:_MAX_TEXT_LEN]

    effective_scale = _pick_scale(len(s), scale, width)
    if effective_scale < 1:
        return

    while len(s) > 1 and (len(s) * _CHAR_W * effective_scale) > width:
        s = s[:-1]

    _scratch_fb.fill(0)
    _scratch_fb.text(s, 0, 0, 1)

    graphics.set_pen(pen)                        # was: graphics.set_pen(BLACK)
    pixel = _scratch_fb.pixel
    for tx in range(len(s) * _CHAR_W):
        for ty in range(_SCRATCH_H):
            if pixel(tx, ty):
                rect_portrait(
                    x + tx * effective_scale,
                    y + ty * effective_scale,
                    effective_scale,
                    effective_scale,
                )

def clear_display():
    graphics.set_pen(WHITE)
    graphics.clear()
    graphics.update()


# ----- QR code -------------------------------------------------------------
def draw_qr_code(url, ox, oy, target_size=180):
    """Draws a real QR code using the qrcode module, positioned in portrait space."""
    try:
        import qrcode
        code = qrcode.QRCode()
        code.set_text(url)

        size = code.get_size()
        if isinstance(size, (tuple, list)):
            size = size[0]
        size = int(size)

        module_size = int(target_size / size)
        if module_size < 2:
            module_size = 2

        qr_pixel_size = size * module_size
        padding = 6

        graphics.set_pen(WHITE)
        rect_portrait(
            ox - padding,
            oy - padding,
            qr_pixel_size + (padding * 2),
            qr_pixel_size + (padding * 2),
        )

        graphics.set_pen(BLACK)
        rect_portrait(ox - padding, oy - padding, qr_pixel_size + (padding * 2), 2)
        rect_portrait(ox - padding, oy - padding, 2, qr_pixel_size + (padding * 2))
        rect_portrait(
            ox - padding,
            oy + qr_pixel_size + padding - 2,
            qr_pixel_size + (padding * 2),
            2,
        )
        rect_portrait(
            ox + qr_pixel_size + padding - 2,
            oy - padding,
            2,
            qr_pixel_size + (padding * 2),
        )

        for x in range(size):
            for y in range(size):
                if code.get_module(x, y):
                    rect_portrait(
                        ox + (x * module_size),
                        oy + (y * module_size),
                        module_size,
                        module_size,
                    )

        print("QR code drawn.")
    except Exception as exc:
        print("QR generation error:", exc)
        try:
            print("  available methods:", dir(code))
        except Exception:
            pass
        graphics.set_pen(BLACK)
        rect_portrait(ox, oy, 140, 140)
        graphics.set_pen(WHITE)
        rect_portrait(ox + 5, oy + 5, 130, 130)
        graphics.set_pen(BLACK)
        text("Scan Error", ox + 15, oy + 60, 100, 2)


# ----- Setup screen --------------------------------------------------------
def show_setup(ssid, password):
    try:
        print("Clearing display buffer...")
        graphics.set_pen(WHITE)
        graphics.clear()

        W = PORTRAIT_WIDTH
        M = 20
        CW = W - (M * 2)

        text("Welcome to TimePlace", M, 25, CW, 2)
        text("Connect this frame to your home Wi-Fi", M, 70, CW, 2)

        qr_size = 180
        qr_x = (W - qr_size) // 2
        qr_y = 120
        draw_qr_code(SETUP_URL, qr_x, qr_y, target_size=qr_size)
        text("Scan to Setup", qr_x, qr_y + qr_size + 15, qr_size, 2)

        y = 380
        text("1. Open Wi-Fi settings on your phone", M, y, CW, 2)
        y += 40
        text("2. Join this network:", M, y, CW, 2)
        y += 40
        text(ssid, M + 20, y, CW - 20, 3)
        y += 45
        text("Password: " + password, M + 20, y, CW - 20, 2)
        y += 45
        text("3. Scan QR code or open browser:", M, y, CW, 2)
        y += 40
        text(SETUP_URL, M + 20, y, CW - 20, 3)
        y += 45
        text("4. Select your home Wi-Fi & Connect", M, y, CW, 2)

        print("Triggering physical display update (takes ~15-20s)...")
        graphics.update()
        print("Display update command sent successfully.")
    except Exception as exc:
        print("Display update error:", exc)


# ----- Config file ---------------------------------------------------------
def load_config():
    try:
        with open(CONFIG_FILE, "r") as f:
            data = ujson.load(f)
        if data.get("ssid"):
            return data["ssid"], data.get("password", "")
    except Exception:
        pass
    return None


def save_config(ssid, password):
    with open(CONFIG_FILE, "w") as f:
        ujson.dump({"ssid": ssid, "password": password}, f)


def remove_config():
    try:
        import os
        os.remove(CONFIG_FILE)
    except Exception:
        pass


# ----- Wi-Fi ---------------------------------------------------------------
def connect_wifi(ssid, password, timeout=20):
    print("Connecting to home Wi-Fi:", ssid)
    wlan = network.WLAN(network.STA_IF)
    wlan.active(True)
    try:
        wlan.disconnect()
    except Exception:
        pass
    try:
        wlan.connect(ssid, password)
    except Exception as exc:
        print("Wi-Fi error:", exc)
        return False
    start = time.time()
    while time.time() - start < timeout:
        if wlan.isconnected():
            print("Connected. IP:", wlan.ifconfig()[0])
            return True
        time.sleep(0.5)
    try:
        wlan.disconnect()
    except Exception:
        pass
    return False


# ----- Form / HTML helpers -------------------------------------------------
def escape_html(value):
    value = str(value)
    for old, new in [
        ("&", "&amp;"),
        ("<", "&lt;"),
        (">", "&gt;"),
        ('"', "&quot;"),
        ("'", "&#39;"),
    ]:
        value = value.replace(old, new)
    return value


def decode_form(value):
    value = value.replace("+", " ")
    result = bytearray()
    i = 0
    while i < len(value):
        if value[i] == "%" and i + 2 < len(value):
            try:
                result.append(int(value[i + 1:i + 3], 16))
                i += 3
                continue
            except Exception:
                pass
        result.extend(value[i].encode())
        i += 1
    try:
        return result.decode("utf-8")
    except Exception:
        return str(result)


def parse_form(body):
    fields = {}
    for part in body.split("&"):
        if "=" in part:
            key, value = part.split("=", 1)
            fields[decode_form(key)] = decode_form(value)
    return fields


def scan_wifi():
    names = []
    try:
        wlan = network.WLAN(network.STA_IF)
        wlan.active(True)
        time.sleep(0.2)
        for item in wlan.scan():
            try:
                name = item[0].decode("utf-8")
            except Exception:
                name = str(item[0])
            if name and name not in names:
                names.append(name)
        names.sort()
    except Exception as exc:
        print("Wi-Fi scan unavailable; use manual entry:", exc)
    return names


def setup_page(networks, message=""):
    options = '<option value="">Choose a network...</option>'
    for name in networks:
        safe = escape_html(name)
        options += '<option value="' + safe + '">' + safe + "</option>"
    page = """<!doctype html>
<html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<title>TimePlace setup</title><style>
body{font-family:Arial;max-width:480px;margin:30px auto;padding:0 18px}
label{display:block;margin-top:20px;font-weight:bold}
select,input{box-sizing:border-box;width:100%;padding:13px;margin-top:8px;font-size:16px}
button{width:100%;padding:14px;margin-top:25px;background:#111;color:white;border:0;font-size:17px}
.note{font-size:13px;color:#555}
</style><script>
function manualChoice(){document.getElementById('manual').style.display=document.getElementById('ssid').value==='__manual__'?'block':'none';}
</script></head><body><h1>Set up TimePlace</h1>
<p>Choose your home Wi-Fi and enter its password.</p>"""
    if message:
        page += "<p>" + escape_html(message) + "</p>"
    page += (
        """
<form method="POST" action="/connect">
<label for="ssid">Wi-Fi network</label>
<select id="ssid" name="ssid" onchange="manualChoice()" required>"""
        + options
        + """
<option value="__manual__">My network is not listed</option></select>
<div id="manual" style="display:none"><label for="manual_ssid">Network name</label>
<input id="manual_ssid" name="manual_ssid" autocomplete="off"></div>
<label for="password">Wi-Fi password</label>
<input id="password" name="password" type="password" autocomplete="current-password">
<p class="note">Credentials are saved in a local test config file on this Pico.</p>
<button type="submit">Connect</button></form></body></html>"""
    )
    return page


def send_response(client, status, body):
    data = body.encode("utf-8")
    header = (
        "HTTP/1.1 " + status
        + "\r\nContent-Type: text/html; charset=utf-8"
        + "\r\nContent-Length: " + str(len(data))
        + "\r\nConnection: close"
        + "\r\nCache-Control: no-store\r\n\r\n"
    )
    client.send(header.encode())
    client.send(data)


def read_request(client):
    client.settimeout(3)
    data = b""
    while b"\r\n\r\n" not in data and len(data) < 8192:
        part = client.recv(1024)
        if not part:
            break
        data += part
    if b"\r\n\r\n" not in data:
        return "", "", b""
    headers, body = data.split(b"\r\n\r\n", 1)
    lines = headers.decode("utf-8", "ignore").split("\r\n")
    bits = lines[0].split(" ")
    method = bits[0] if len(bits) > 0 else ""
    path = bits[1] if len(bits) > 1 else "/"
    length = 0
    for line in lines[1:]:
        if line.lower().startswith("content-length:"):
            try:
                length = int(line.split(":", 1)[1].strip())
            except Exception:
                pass
    while len(body) < length:
        part = client.recv(1024)
        if not part:
            break
        body += part
    return method, path, body


# ----- Access point / provisioning -----------------------------------------
def random_password(length=10):
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    return "".join(random.choice(alphabet) for _ in range(length))


def start_access_point():
    device = ubinascii.hexlify(machine.unique_id()).decode().upper()
    ssid = "TimePlace-" + device[-6:]
    password = random_password()
    ap = network.WLAN(network.AP_IF)
    ap.active(False)
    time.sleep(0.2)
    ap.config(ssid=ssid, password=password)
    ap.active(True)
    start = time.time()
    while not ap.active() and time.time() - start < 5:
        time.sleep(0.1)
    try:
        ap.ifconfig((SETUP_IP, "255.255.255.0", SETUP_IP, SETUP_IP))
    except Exception:
        pass
    print("Join Wi-Fi:", ssid)
    print("Setup password:", password)
    print("Then visit:", SETUP_URL)
    return ap, ssid, password


def provisioning():
    ap, ap_ssid, ap_password = start_access_point()
    show_setup(ap_ssid, ap_password)
    networks = scan_wifi()
    server = socket.socket()
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("0.0.0.0", 80))
    server.listen(2)
    server.settimeout(1)
    credentials = None
    try:
        while credentials is None:
            try:
                client, address = server.accept()
            except OSError:
                continue
            try:
                method, path, body = read_request(client)
                if method == "POST" and path == "/connect":
                    fields = parse_form(body.decode("utf-8", "ignore"))
                    ssid = fields.get("ssid", "")
                    if ssid == "__manual__":
                        ssid = fields.get("manual_ssid", "")
                    password = fields.get("password", "")
                    if not ssid.strip():
                        send_response(
                            client,
                            "400 Bad Request",
                            setup_page(networks, "Choose or enter a network name."),
                        )
                    else:
                        send_response(
                            client,
                            "200 OK",
                            "<html><body><h2>Connecting TimePlace...</h2>"
                            "<p>Please wait.</p></body></html>",
                        )
                        credentials = (ssid.strip(), password)
                else:
                    send_response(client, "200 OK", setup_page(networks))
            except Exception as exc:
                print("Request error:", exc)
            finally:
                try:
                    client.close()
                except Exception:
                    pass
    finally:
        server.close()
        ap.active(False)
    return credentials


# ----- Entry point ---------------------------------------------------------
def main():
    print("TimePlace Wi-Fi setup test starting")
    config = load_config()
    if config and connect_wifi(config[0], config[1]):
        clear_display()
        print("Already connected; display left blank.")
        return
    if config:
        remove_config()
    while True:
        ssid, password = provisioning()
        if connect_wifi(ssid, password):
            save_config(ssid, password)
            clear_display()
            print("Setup successful; display left blank.")
            return
        remove_config()

        # Error screen (portrait)
        graphics.set_pen(WHITE)
        graphics.clear()
        text("Could not connect to Wi-Fi", 20, 350, PORTRAIT_WIDTH - 40, 2)
        text("Check the password and try again.", 20, 400, PORTRAIT_WIDTH - 40, 2)
        graphics.update()
        time.sleep(5)
        gc.collect()


if __name__ == "__main__":
    main()
