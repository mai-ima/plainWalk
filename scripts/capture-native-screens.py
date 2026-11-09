"""Capture isolated, synthetic native screens on a booted iPhone Simulator."""
from pathlib import Path
import argparse, datetime, json, os, subprocess, sys, time

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument("group")
args = parser.parse_args()
catalog = json.loads((ROOT / "scripts/native-screen-catalog.json").read_text())
scenes = [s for s in catalog["scenes"] if s["group"] == args.group]
if not scenes:
    raise SystemExit("Unknown screenshot group")
out = ROOT / ".build/native-screens" / args.group
out.mkdir(parents=True, exist_ok=True)

def command(*items, timeout=90, required=True):
    result = subprocess.run(items, capture_output=True, text=True, timeout=timeout)
    if required and result.returncode:
        raise RuntimeError(result.stderr[-2000:])
    return result.stdout.strip()

device = json.loads(command(sys.executable, str(ROOT / "scripts/ios-simulator-device.py"), "--json"))
udid = device["udid"]
command("xcrun", "simctl", "bootstatus", udid, "-b", timeout=360)
app = ROOT / ".build/ios/Build/Products/Debug-iphonesimulator/PlainWalk.app"
command("xcrun", "simctl", "install", udid, str(app))
container = Path(command("xcrun", "simctl", "get_app_container", udid, "org.example.plainwalkweb", "data"))
signals = container / "Library/Application Support/PlainWalk"
signals.mkdir(parents=True, exist_ok=True)
ready = signals / "native-ready.json"

def wait_until(check, seconds, description):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if check():
            return
        time.sleep(0.3)
    raise TimeoutError(description)

def value(path):
    try:
        return path.read_text()
    except FileNotFoundError:
        return ""

def startup_ready():
    try:
        data = json.loads(ready.read_text())
        return data.get("ready") is True and data.get("screenOnly") is True
    except (OSError, ValueError):
        return False

manifest = {"version": 1, "platform": "native", "group": args.group,
            "device": device["name"], "locale": "ja-JP", "sourceCommit": os.environ.get("GITHUB_SHA", "local"),
            "generatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "complete": False, "screens": [], "limitations": catalog["limitations"]}
failed = []
for scene in scenes:
    key = scene["key"]
    marker = signals / ("screen-" + scene["marker"] + ".ready")
    trace = marker.with_suffix(".trace")
    for path in [ready, marker, trace, signals / "capture-scroll.ready", signals / "capture-dialog.ready"]:
        path.unlink(missing_ok=True)
    launch = ["xcrun", "simctl", "launch", "--terminate-running-process", udid, "org.example.plainwalkweb",
              "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP",
              "-PlainWalkSmokeTest", "-PlainWalkScreenOnly", "-PlainWalkScreenshotFixture"]
    if "capture" in scene:
        launch.append("-PlainWalkCapture=" + scene["capture"])
    else:
        launch.append("-PlainWalkScreen=" + scene["screen"])
    for field, flag in [("scroll", "Scroll"), ("dialog", "Dialog"), ("photo", "Photo"), ("lut", "LUT")]:
        if scene.get(field):
            launch.append("-PlainWalkCapture" + flag + "=" + scene[field])
    entry = {**scene, "sourceRoute": key, "part": 1, "path": "ios-" + key + ".png", "status": "missing"}
    try:
        print("Capturing " + key, flush=True)
        try:
            command(*launch)
        except subprocess.TimeoutExpired:
            # simctl can hold its response pipe after the app has launched.
            # A fresh app-written signal is independent evidence; actual view
            # readiness and OCR are still required below.
            if not startup_ready():
                raise
            entry["launchCommandWarning"] = "simctl response timed out after the app signaled readiness"
        # Separate OS process startup from the screen's own presentation budget.
        wait_until(startup_ready, 60, "The application did not reach screenshot routing")
        if scene.get("dialog"):
            wait_until(lambda: value(signals / "capture-dialog.ready") == scene["dialog"], 30, "Dialog did not appear")
        else:
            wait_until(marker.is_file, 30, "Screen did not finish appearing")
        if scene.get("scroll"):
            wait_until(lambda: value(signals / "capture-scroll.ready") == scene["scroll"], 30, "Scroll did not complete")
        time.sleep(1.0)
        command("xcrun", "simctl", "io", udid, "screenshot", str(out / entry["path"]))
        entry["status"] = "captured"
    except (RuntimeError, TimeoutError, subprocess.TimeoutExpired) as error:
        entry["error"] = str(error)
        entry["trace"] = value(trace)
        entry["stage"] = value(signals / "native-smoke-stage.txt")
        command("xcrun", "simctl", "io", udid, "screenshot", str(out / ("failed-" + key + ".png")), required=False)
        print(json.dumps({"key": key, "error": entry["error"], "trace": entry["trace"]}, ensure_ascii=False), flush=True)
        failed.append(key)
    manifest["screens"].append(entry)
    (out / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
manifest["complete"] = not failed
(out / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
if failed:
    raise SystemExit("Screens not captured: " + ", ".join(failed))
print(f"Captured {len(scenes)} native screen states in {args.group}.")
