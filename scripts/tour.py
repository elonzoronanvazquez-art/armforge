"""Visual tour of the running playtest: for each shot, teleport the character near the view (so streaming loads the area), pose the
Studio-only dev camera, and save a screenshot. Usage: python scripts/tour.py <outdir> <shots.json>
shots.json = [{"name": "forge", "tp": [x,y,z], "cam": [px,py,pz,lx,ly,lz], "fov": 70, "wait": 2.5}, ...]"""
import json, os, subprocess, sys, time
HERE = os.path.dirname(__file__)
out = sys.argv[1]
os.makedirs(out, exist_ok=True)
env = dict(os.environ, PYTHONIOENCODING="utf-8")
for shot in json.load(open(sys.argv[2])):
    x, y, z = shot["tp"]
    subprocess.run([sys.executable, os.path.join(HERE, "dev.py"), "tp", str(x), str(y), str(z)], env=env, capture_output=True)
    time.sleep(shot.get("wait", 2.5))
    c = shot["cam"]
    subprocess.run([sys.executable, os.path.join(HERE, "cam.py"), *[str(v) for v in c], str(shot.get("fov", 70))], env=env, capture_output=True)
    time.sleep(0.8)
    path = os.path.join(out, shot["name"] + ".png")
    subprocess.run([sys.executable, os.path.join(HERE, "studio_mcp.py"), "screen_capture", json.dumps({"capture_id": shot["name"]})], env=dict(env, MCP_IMG=path), capture_output=True)
    print("saved", path)
