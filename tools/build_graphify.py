#!/usr/bin/env python3
"""
tools/build_graphify.py - Comprehensive Knowledge Graph Builder for After Wind
Uses the graphify pipeline with support for GDScript (.gd), Python (.py),
Markdown (.md), and Godot Scenes (.tscn).
"""

import os
import re
import sys
import json
from pathlib import Path
from datetime import datetime, timezone

# Ensure UTF-8 output on Windows console
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

import networkx as nx

from graphify.extract import extract_python, extract_markdown
from graphify.build import build_from_json
from graphify.cluster import cluster, score_all
from graphify.analyze import god_nodes, surprising_connections, suggest_questions
from graphify.report import generate
from graphify.export import to_json, to_html


def normalize_id(path_str: str) -> str:
    return path_str.replace("\\", "/").replace("/", "_").replace(".", "_").replace("-", "_")


def extract_gdscript(path: Path, root: Path) -> dict:
    rel_path = path.relative_to(root).as_posix()
    file_id = normalize_id(rel_path)
    code = path.read_text(encoding="utf-8", errors="replace")
    lines = code.splitlines()

    nodes = [{
        "id": file_id,
        "label": path.name,
        "file_type": "code",
        "source_file": rel_path,
        "source_location": "L1",
        "docstring": ""
    }]
    edges = []

    # Check for top-level docstring
    doc_lines = []
    for line in lines[:15]:
        s = line.strip()
        if s.startswith("##"):
            doc_lines.append(s.lstrip("#").strip())
    if doc_lines:
        nodes[0]["docstring"] = " ".join(doc_lines)

    current_scope = file_id
    class_id = None

    for i, line in enumerate(lines, 1):
        line_clean = line.strip()
        if not line_clean or line_clean.startswith("#"):
            continue

        # class_name
        m_cls = re.match(r"^class_name\s+([A-Za-z0-9_]+)", line_clean)
        if m_cls:
            cname = m_cls.group(1)
            class_id = f"{file_id}_{cname}"
            nodes.append({
                "id": class_id,
                "label": cname,
                "file_type": "code",
                "source_file": rel_path,
                "source_location": f"L{i}"
            })
            edges.append({
                "source": file_id,
                "target": class_id,
                "relation": "defines",
                "confidence": "EXTRACTED",
                "source_file": rel_path,
                "source_location": f"L{i}",
                "weight": 1.0
            })
            current_scope = class_id

        # extends
        m_ext = re.match(r"^extends\s+([A-Za-z0-9_]+)", line_clean)
        if m_ext:
            base = m_ext.group(1)
            edges.append({
                "source": current_scope,
                "target": base,
                "relation": "inherits",
                "confidence": "EXTRACTED",
                "source_file": rel_path,
                "source_location": f"L{i}",
                "weight": 1.0
            })

        # signal
        m_sig = re.match(r"^signal\s+([A-Za-z0-9_]+)", line_clean)
        if m_sig:
            sig = m_sig.group(1)
            sig_id = f"{file_id}_{sig}"
            nodes.append({
                "id": sig_id,
                "label": f"{sig} (signal)",
                "file_type": "code",
                "source_file": rel_path,
                "source_location": f"L{i}"
            })
            edges.append({
                "source": current_scope,
                "target": sig_id,
                "relation": "declares",
                "confidence": "EXTRACTED",
                "source_file": rel_path,
                "source_location": f"L{i}",
                "weight": 1.0
            })

        # func
        m_fn = re.match(r"^func\s+([A-Za-z0-9_]+)\s*\(", line_clean)
        if m_fn:
            fname = m_fn.group(1)
            fn_id = f"{file_id}_{fname}"
            nodes.append({
                "id": fn_id,
                "label": f"{fname}()",
                "file_type": "code",
                "source_file": rel_path,
                "source_location": f"L{i}",
                "_callable": True
            })
            edges.append({
                "source": current_scope,
                "target": fn_id,
                "relation": "contains",
                "confidence": "EXTRACTED",
                "source_file": rel_path,
                "source_location": f"L{i}",
                "weight": 1.0
            })

        # preload("res://...")
        for m_pre in re.finditer(r"preload\([\"']res://([^\"']+)[\"']\)", line_clean):
            imp_path = m_pre.group(1)
            target_id = normalize_id(imp_path)
            edges.append({
                "source": file_id,
                "target": target_id,
                "relation": "imports",
                "confidence": "EXTRACTED",
                "source_file": rel_path,
                "source_location": f"L{i}",
                "weight": 1.0
            })

        # load("res://...")
        for m_load in re.finditer(r"load\([\"']res://([^\"']+)[\"']\)", line_clean):
            load_path = m_load.group(1)
            target_id = normalize_id(load_path)
            edges.append({
                "source": file_id,
                "target": target_id,
                "relation": "loads",
                "confidence": "EXTRACTED",
                "source_file": rel_path,
                "source_location": f"L{i}",
                "weight": 1.0
            })

    return {"nodes": nodes, "edges": edges, "raw_calls": []}


def extract_godot_scene(path: Path, root: Path) -> dict:
    rel_path = path.relative_to(root).as_posix()
    file_id = normalize_id(rel_path)
    content = path.read_text(encoding="utf-8", errors="replace")
    nodes = [{
        "id": file_id,
        "label": path.name,
        "file_type": "scene",
        "source_file": rel_path,
        "source_location": "L1"
    }]
    edges = []

    # Look for [ext_resource ... path="res://..."]
    for i, line in enumerate(content.splitlines(), 1):
        if line.startswith("[ext_resource"):
            m = re.search(r'path="res://([^"]+)"', line)
            if m:
                target_path = m.group(1)
                target_id = normalize_id(target_path)
                edges.append({
                    "source": file_id,
                    "target": target_id,
                    "relation": "references",
                    "confidence": "EXTRACTED",
                    "source_file": rel_path,
                    "source_location": f"L{i}",
                    "weight": 1.0
                })

    return {"nodes": nodes, "edges": edges, "raw_calls": []}


def main():
    root = Path(".").resolve()
    out_dir = root / "graphify-out"
    out_dir.mkdir(exist_ok=True)

    print(">>> 1. Сканирование репозитория After Wind...")
    all_nodes = []
    all_edges = []
    seen_node_ids = set()

    def add_result(res):
        for n in res.get("nodes", []):
            if n["id"] not in seen_node_ids:
                seen_node_ids.add(n["id"])
                all_nodes.append(n)
        for e in res.get("edges", []):
            all_edges.append(e)

    # A. GDScript (.gd)
    gd_files = sorted(list(root.glob("scripts/**/*.gd")) + list(root.glob("tests/**/*.gd")))
    print(f"  Извлечение GDScript файлов ({len(gd_files)} шт.)...")
    for p in gd_files:
        try:
            add_result(extract_gdscript(p, root))
        except Exception as err:
            print(f"  [warn] Ошибка парсинга {p}: {err}")

    # B. Python (.py)
    py_files = sorted(root.glob("tools/*.py"))
    print(f"  Извлечение Python инструментов ({len(py_files)} шт.)...")
    for p in py_files:
        try:
            add_result(extract_python(p, root=root))
        except Exception as err:
            print(f"  [warn] Ошибка парсинга {p}: {err}")

    # C. Markdown (.md)
    md_files = [
        root / "DEVELOPER_HANDOVER.md",
        root / "AGENTS.md",
        root / "README.md",
        root / "docs/DOCUMENTATION.md",
        root / "docs/SOLID_FUEL_GENERATOR.md",
        root / "docs/PRIMITIVE_BED.md",
        root / "docs/BATTERIES_AND_SOLAR.md",
    ]
    md_files = [p for p in md_files if p.is_file()]
    obsidian_docs = list(root.glob("obsidian-mind/*.md"))[:30]
    md_files.extend(obsidian_docs)
    print(f"  Извлечение Markdown документации ({len(md_files)} шт.)...")
    for p in md_files:
        try:
            add_result(extract_markdown(p))
        except Exception as err:
            print(f"  [warn] Ошибка парсинга {p}: {err}")

    # D. Godot Scenes (.tscn)
    scene_files = sorted(root.glob("scenes/**/*.tscn"))
    print(f"  Извлечение Godot сцен ({len(scene_files)} шт.)...")
    for p in scene_files:
        try:
            add_result(extract_godot_scene(p, root))
        except Exception as err:
            print(f"  [warn] Ошибка парсинга {p}: {err}")

    print(f"✅ Извлечение завершено: {len(all_nodes)} узлов, {len(all_edges)} связей")

    extraction = {
        "nodes": all_nodes,
        "edges": all_edges,
        "hyperedges": [],
        "input_tokens": 0,
        "output_tokens": 0
    }
    (out_dir / ".graphify_extract.json").write_text(json.dumps(extraction, indent=2, ensure_ascii=False), encoding="utf-8")

    detection = {
        "total_files": len(gd_files) + len(py_files) + len(md_files) + len(scene_files),
        "total_words": 350000,
        "files": {
            "code": [p.as_posix() for p in gd_files + py_files],
            "document": [p.as_posix() for p in md_files],
            "scene": [p.as_posix() for p in scene_files]
        }
    }
    (out_dir / ".graphify_detect.json").write_text(json.dumps(detection, indent=2, ensure_ascii=False), encoding="utf-8")

    print(">>> 2. Построение графа и алгоритм сообществ (Louvain)...")
    G = build_from_json(extraction, root=str(root), directed=False)
    print(f"  Граф собран: {G.number_of_nodes()} узлов, {G.number_of_edges()} связей")

    communities = cluster(G)
    cohesion = score_all(G, communities)
    gods = god_nodes(G, top_n=12)
    surprises = surprising_connections(G, communities, top_n=8)

    # Автоматическое семантическое именование сообществ на основе узлов
    community_labels = {}
    for cid, members in communities.items():
        member_labels = [G.nodes[m].get("label", m) for m in members if m in G.nodes]
        joined = " ".join(member_labels).lower()
        if "inventory" in joined or "item" in joined or "рюкзак" in joined or "itemgrid" in joined:
            lbl = "Инвентарь и предметы"
        elif "generator" in joined or "energy" in joined or "battery" in joined or "power" in joined or "cable" in joined:
            lbl = "Энергосеть и генератор"
        elif "farm" in joined or "crop" in joined or "plant" in joined or "seed" in joined:
            lbl = "Фермерство и агрокультуры"
        elif "craft" in joined or "machine" in joined or "recipe" in joined or "crusher" in joined or "smelter" in joined:
            lbl = "Станки и рецепты крафта"
        elif "player" in joined or "health" in joined or "hunger" in joined or "thirst" in joined or "bed" in joined:
            lbl = "Игрок и механики выживания"
        elif "ui" in joined or "hud" in joined or "dialog" in joined or "menu" in joined:
            lbl = "Пользовательский интерфейс (UI/HUD)"
        elif "world" in joined or "season" in joined or "weather" in joined or "day" in joined or "sun" in joined:
            lbl = "Окружающий мир и погода"
        elif "save" in joined or "core" in joined or "audio" in joined or "setting" in joined:
            lbl = "Ядро и сохранение игры"
        elif "test" in joined:
            lbl = "Автоматические тесты"
        else:
            lbl = f"Модуль {cid} ({member_labels[0] if member_labels else 'компоненты'})"
        community_labels[cid] = lbl

    print(f"  Выделено {len(communities)} сообществ:")
    for cid, lbl in list(community_labels.items())[:10]:
        print(f"    - Сообщество {cid}: {lbl} ({len(communities[cid])} узлов)")

    questions = suggest_questions(G, communities, community_labels, top_n=7)

    tokens = {"input": 0, "output": 0}
    report = generate(
        G, communities, cohesion, community_labels, gods, surprises,
        detection, tokens, str(root), suggested_questions=questions
    )

    print(">>> 3. Экспорт артефактов graphify...")
    # A. graph.json
    to_json(G, communities, str(out_dir / "graph.json"), force=True, community_labels=community_labels)
    # B. graph.html
    to_html(G, communities, str(out_dir / "graph.html"), community_labels=community_labels)
    # C. GRAPH_REPORT.md
    (out_dir / "GRAPH_REPORT.md").write_text(report, encoding="utf-8")
    # D. .graphify_labels.json
    (out_dir / ".graphify_labels.json").write_text(json.dumps({str(k): v for k, v in community_labels.items()}, indent=2, ensure_ascii=False), encoding="utf-8")

    # E. cost.json
    cost_data = {
        "runs": [{
            "date": datetime.now(timezone.utc).isoformat(),
            "input_tokens": 0,
            "output_tokens": 0,
            "nodes": G.number_of_nodes(),
            "edges": G.number_of_edges(),
            "communities": len(communities)
        }],
        "total_input_tokens": 0,
        "total_output_tokens": 0
    }
    (out_dir / "cost.json").write_text(json.dumps(cost_data, indent=2, ensure_ascii=False), encoding="utf-8")

    print("\n" + "=" * 60)
    print("✨ Граф знаний graphify успешно построен!")
    print(f"  Узлов (nodes): {G.number_of_nodes()}")
    print(f"  Связей (edges): {G.number_of_edges()}")
    print(f"  Сообществ (communities): {len(communities)}")
    print(f"  Интерактивный граф: {out_dir / 'graph.html'}")
    print(f"  Отчет архитектуры: {out_dir / 'GRAPH_REPORT.md'}")
    print(f"  Данные графа: {out_dir / 'graph.json'}")
    print("=" * 60)


if __name__ == "__main__":
    main()
