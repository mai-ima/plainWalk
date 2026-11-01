"""Recheck captured pixels against current labels; never repair missing images."""
from pathlib import Path
import argparse, json, os

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument("folder")
parser.add_argument("--capture-commit", required=True)
args = parser.parse_args()
folder = Path(args.folder)
catalog = json.loads((root/"scripts/native-screen-catalog.json").read_text())
scenes = {s["key"]:s for s in catalog["scenes"]}
groups = sorted({s["group"] for s in scenes.values()})
for group in groups:
    path = folder / ("ios-all-screens-"+group) / "manifest.json"
    if not path.is_file():
        raise SystemExit("Capture group missing: "+group)
    data = json.loads(path.read_text())
    expected = {s["key"] for s in scenes.values() if s["group"] == group}
    actual = {s["key"] for s in data["screens"]}
    if actual != expected or data.get("sourceCommit") != args.capture_commit:
        raise SystemExit("Capture inventory or source differs: "+group)
    for screen in data["screens"]:
        name = screen.get("path", "")
        if screen.get("status") != "captured" or Path(name).name != name or not (path.parent/name).is_file():
            raise SystemExit("Actual screenshot missing: "+screen["key"])
        scene = scenes[screen["key"]]
        # Navigation/fixture/scroll must still describe the same captured state.
        for field in ["capture","screen","scroll","dialog","photo","lut","marker"]:
            if screen.get(field) != scene.get(field):
                raise SystemExit("Captured state changed: "+screen["key"]+"/"+field)
        screen.setdefault("originalExpectedText",screen.get("expectedText", ""))
        screen.setdefault("originalTextVerified",screen.get("textVerified"))
        screen["expectedText"] = scene.get("expectedText", "")
        screen["textVerified"] = False
    data["complete"] = True  # Every image exists; OCR will gate it again next.
    data["ocrReviewCommit"] = os.environ.get("GITHUB_SHA", "local")
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n")
print(f"Validated captured pixels and state inventory for {len(groups)} groups.")
