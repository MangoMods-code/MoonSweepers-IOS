"""Exports meshes, textures and a renderer/material map from a Unity game's *_Data folder.

Usage: python extract_unity.py <game_dir> <out_dir>
Run on GitHub Actions by .github/workflows/extract-studio-assets.yml.
"""
import json
import os
import re
import sys
import traceback

import UnityPy

src, out = sys.argv[1], sys.argv[2]
os.makedirs(f"{out}/meshes", exist_ok=True)
os.makedirs(f"{out}/textures", exist_ok=True)


def safe(name):
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", name or "unnamed")[:80] or "unnamed"


def read(obj):
    try:
        return obj.read()
    except Exception:
        return None


def mesh_obj_text(mesh):
    for attempt in (
        lambda: mesh.export(),
        lambda: __import__("UnityPy.export.MeshExporter", fromlist=["x"]).export_mesh(mesh, "obj"),
    ):
        try:
            text = attempt()
            if text:
                return text
        except Exception:
            pass
    return None


data_dirs = []
for root, dirs, _ in os.walk(src):
    for d in dirs:
        if d.endswith("_Data"):
            data_dirs.append(os.path.join(root, d))
if not data_dirs:
    sys.exit(f"No *_Data folder under {src}")
print("Loading", data_dirs[0])
env = UnityPy.load(data_dirs[0])

catalog = {"meshes": [], "textures": [], "renderers": []}
used_names = {}


def unique(kind, name):
    key = (kind, name)
    used_names[key] = used_names.get(key, 0) + 1
    return name if used_names[key] == 1 else f"{name}__{used_names[key]}"


for obj in env.objects:
    t = obj.type.name
    try:
        if t == "Mesh":
            m = read(obj)
            if m is None:
                continue
            text = mesh_obj_text(m)
            if not text or text.count("\nv ") < 3:
                continue
            name = unique("mesh", safe(getattr(m, "m_Name", "")))
            with open(f"{out}/meshes/{name}.obj", "w") as f:
                f.write(text)
            catalog["meshes"].append({"name": name, "path_id": obj.path_id,
                                      "verts": text.count("\nv "), "file": obj.assets_file.name})
        elif t == "Texture2D":
            tex = read(obj)
            if tex is None:
                continue
            img = tex.image
            if img is None or img.width < 8:
                continue
            if max(img.width, img.height) > 2048:
                img.thumbnail((2048, 2048))
            name = unique("tex", safe(getattr(tex, "m_Name", "")))
            img.save(f"{out}/textures/{name}.png")
            catalog["textures"].append({"name": name, "path_id": obj.path_id,
                                        "size": [img.width, img.height], "file": obj.assets_file.name})
        elif t in ("MeshRenderer", "SkinnedMeshRenderer"):
            r = read(obj)
            if r is None:
                continue
            entry = {"type": t, "gameObject": None, "mesh": None, "materials": []}
            go = read(r.m_GameObject) if getattr(r, "m_GameObject", None) else None
            if go is not None:
                entry["gameObject"] = getattr(go, "m_Name", None)
                mf = getattr(go, "m_MeshFilter", None)
                if mf is not None:
                    mfr = mf if not hasattr(mf, "read") else read(mf)
                    if mfr is not None and getattr(mfr, "m_Mesh", None):
                        mesh = read(mfr.m_Mesh)
                        entry["mesh"] = getattr(mesh, "m_Name", None)
            if t == "SkinnedMeshRenderer" and getattr(r, "m_Mesh", None):
                mesh = read(r.m_Mesh)
                entry["mesh"] = getattr(mesh, "m_Name", None)
            for pm in getattr(r, "m_Materials", []) or []:
                mat = read(pm)
                if mat is None:
                    continue
                m_entry = {"name": getattr(mat, "m_Name", None), "textures": {}, "colors": {}}
                props = getattr(mat, "m_SavedProperties", None)
                for key, env_ in (getattr(props, "m_TexEnvs", None) or []):
                    tx = getattr(env_, "m_Texture", None)
                    txo = read(tx) if tx else None
                    if txo is not None:
                        m_entry["textures"][str(key)] = getattr(txo, "m_Name", None)
                for key, col in (getattr(props, "m_Colors", None) or []):
                    try:
                        m_entry["colors"][str(key)] = [round(col.r, 4), round(col.g, 4), round(col.b, 4), round(col.a, 4)]
                    except Exception:
                        pass
                entry["materials"].append(m_entry)
            catalog["renderers"].append(entry)
    except Exception:
        traceback.print_exc(limit=1)

with open(f"{out}/catalog.json", "w") as f:
    json.dump(catalog, f, indent=1)
print(f"meshes={len(catalog['meshes'])} textures={len(catalog['textures'])} renderers={len(catalog['renderers'])}")
