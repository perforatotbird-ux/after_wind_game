#!/usr/bin/env python3
"""Convert GAME_EXPANSION_MASTERPLAN.md to a styled standalone HTML document."""
import html
import re
from pathlib import Path

def convert_md_to_html(md_path: Path, html_path: Path):
    content = md_path.read_text(encoding="utf-8")
    lines = content.splitlines()

    html_out = []
    toc_items = []
    
    in_code = False
    code_lang = ""
    code_lines = []
    
    in_table = False
    table_header = []
    table_rows = []
    
    in_blockquote = False
    blockquote_lines = []
    
    in_list = False
    list_type = "ul"
    
    def slugify(text):
        s = text.lower().strip()
        s = re.sub(r"[^\w\s-]", "", s)
        s = re.sub(r"[\s_]+", "-", s)
        return s or "heading"

    def format_inline(text):
        # Escape raw HTML first
        # But allow safe spans or inline formatting
        # Placeholders for inline code
        codes = []
        def code_sub(m):
            codes.append(m.group(1))
            return f"__INLINE_CODE_{len(codes)-1}__"
        
        t = re.sub(r"`([^`]+)`", code_sub, text)
        t = html.escape(t)
        
        # Links
        t = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', t)
        # Bold
        t = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", t)
        # Italic
        t = re.sub(r"\*([^*]+)\*", r"<em>\1</em>", t)
        # Checkboxes
        t = re.sub(r"^☐\s*", r'<span class="checkbox">☐</span> ', t)
        t = re.sub(r"^☑\s*", r'<span class="checkbox checked">☑</span> ', t)
        
        # Restore inline code
        for i, c in enumerate(codes):
            t = t.replace(f"__INLINE_CODE_{i}__", f"<code>{html.escape(c)}</code>")
        return t

    def flush_table():
        nonlocal in_table, table_header, table_rows
        if not in_table:
            return
        res = ['<div class="table-container"><table>']
        if table_header:
            res.append('<thead><tr>')
            for cell in table_header:
                res.append(f'<th>{format_inline(cell.strip())}</th>')
            res.append('</tr></thead>')
        if table_rows:
            res.append('<tbody>')
            for row in table_rows:
                res.append('<tr>')
                for cell in row:
                    res.append(f'<td>{format_inline(cell.strip())}</td>')
                res.append('</tr>')
            res.append('</tbody>')
        res.append('</table></div>')
        html_out.append('\n'.join(res))
        in_table = False
        table_header = []
        table_rows = []

    def flush_blockquote():
        nonlocal in_blockquote, blockquote_lines
        if not in_blockquote:
            return
        text = "\n".join(blockquote_lines)
        alert_match = re.match(r"^\[!(NOTE|IMPORTANT|TIP|WARNING|CAUTION)\]\s*(.*)", text, re.DOTALL)
        if alert_match:
            atype = alert_match.group(1).lower()
            arest = alert_match.group(2).strip()
            title = alert_match.group(1)
            icon = {"note": "ℹ️", "important": "❗", "tip": "💡", "warning": "⚠️", "caution": "🛑"}.get(atype, "📌")
            formatted = "<br>".join(format_inline(l) for l in arest.splitlines() if l.strip())
            html_out.append(f'<div class="callout callout-{atype}"><div class="callout-header"><span class="callout-icon">{icon}</span> <strong>{title}</strong></div><div class="callout-body">{formatted}</div></div>')
        else:
            formatted = "<br>".join(format_inline(l) for l in blockquote_lines)
            html_out.append(f'<blockquote>{formatted}</blockquote>')
        in_blockquote = False
        blockquote_lines = []

    def flush_list():
        nonlocal in_list, list_type
        if not in_list:
            return
        html_out.append(f"</{list_type}>")
        in_list = False

    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        # Code blocks
        if stripped.startswith("```"):
            flush_table()
            flush_blockquote()
            flush_list()
            if not in_code:
                in_code = True
                code_lang = stripped[3:].strip()
                code_lines = []
            else:
                in_code = False
                joined_code = "\n".join(code_lines)
                if code_lang == "mermaid":
                    html_out.append(f'<div class="mermaid-wrap"><pre class="mermaid">\n{html.escape(joined_code)}\n</pre></div>')
                else:
                    html_out.append(f'<pre><code class="language-{code_lang}">{html.escape(joined_code)}</code></pre>')
                code_lines = []
            i += 1
            continue

        if in_code:
            code_lines.append(line)
            i += 1
            continue

        # Blank line
        if not stripped:
            flush_table()
            flush_blockquote()
            flush_list()
            i += 1
            continue

        # Horizontal rule
        if stripped in ("---", "***", "___"):
            flush_table()
            flush_blockquote()
            flush_list()
            html_out.append("<hr>")
            i += 1
            continue

        # Blockquote
        if line.startswith(">"):
            flush_table()
            flush_list()
            in_blockquote = True
            bq_content = line[1:].strip()
            blockquote_lines.append(bq_content)
            i += 1
            continue
        elif in_blockquote:
            flush_blockquote()

        # Tables
        if "|" in line and (line.startswith("|") or line.endswith("|")):
            flush_blockquote()
            flush_list()
            cells = [c for c in line.split("|")[1:-1]]
            if not in_table:
                # Header row
                in_table = True
                table_header = cells
                # Check next line for separator
                if i + 1 < len(lines) and re.match(r"^\|?\s*[-:]+[-| :]*\s*\|?$", lines[i+1].strip()):
                    i += 1  # skip separator
            else:
                table_rows.append(cells)
            i += 1
            continue
        elif in_table:
            flush_table()

        # Headings
        h_match = re.match(r"^(#{1,6})\s+(.*)$", line)
        if h_match:
            flush_table()
            flush_blockquote()
            flush_list()
            level = len(h_match.group(1))
            h_text = h_match.group(2).strip()
            slug = slugify(h_text)
            
            # Extract plain text without markdown for TOC
            clean_text = re.sub(r"[*`\[\]]", "", h_text)
            clean_text = re.sub(r"\(.*?\)", "", clean_text).strip()
            if level in (2, 3):
                toc_items.append((level, slug, clean_text))
            
            html_out.append(f'<h{level} id="{slug}">{format_inline(h_text)} <a class="anchor" href="#{slug}">#</a></h{level}>')
            i += 1
            continue

        # Unordered list / Task list
        ul_match = re.match(r"^[-*]\s+(.*)$", line)
        if ul_match:
            flush_table()
            flush_blockquote()
            item_text = ul_match.group(1).strip()
            if not in_list:
                in_list = True
                list_type = "ul"
                html_out.append("<ul>")
            # Check for task
            if item_text.startswith("[ ] "):
                html_out.append(f'<li class="task-item"><span class="checkbox">☐</span> {format_inline(item_text[4:])}</li>')
            elif item_text.startswith("[x] ") or item_text.startswith("[X] "):
                html_out.append(f'<li class="task-item"><span class="checkbox checked">☑</span> {format_inline(item_text[4:])}</li>')
            else:
                html_out.append(f'<li>{format_inline(item_text)}</li>')
            i += 1
            continue

        # Ordered list
        ol_match = re.match(r"^(\d+)\.\s+(.*)$", line)
        if ol_match:
            flush_table()
            flush_blockquote()
            item_text = ol_match.group(2).strip()
            if not in_list:
                in_list = True
                list_type = "ol"
                html_out.append("<ol>")
            if item_text.startswith("☐ "):
                html_out.append(f'<li class="task-item"><span class="checkbox">☐</span> {format_inline(item_text[2:])}</li>')
            elif item_text.startswith("☑ "):
                html_out.append(f'<li class="task-item"><span class="checkbox checked">☑</span> {format_inline(item_text[2:])}</li>')
            else:
                html_out.append(f'<li>{format_inline(item_text)}</li>')
            i += 1
            continue

        # Plain paragraph
        flush_table()
        flush_blockquote()
        flush_list()
        html_out.append(f"<p>{format_inline(line)}</p>")
        i += 1

    flush_table()
    flush_blockquote()
    flush_list()

    # Build TOC HTML
    toc_html = []
    toc_html.append('<nav class="toc-nav">')
    toc_html.append('<div class="toc-title">📋 Содержание</div>')
    toc_html.append('<ul>')
    for level, slug, title in toc_items:
        cls = "toc-l2" if level == 2 else "toc-l3"
        toc_html.append(f'<li class="{cls}"><a href="#{slug}">{html.escape(title)}</a></li>')
    toc_html.append('</ul>')
    toc_html.append('</nav>')

    # Complete HTML template
    full_html = f"""<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>After The Storm — Мастер-план развития игры</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
<script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
<script>
  mermaid.initialize({{
    startOnLoad: true,
    theme: 'neutral',
    securityLevel: 'loose',
    fontFamily: 'Inter, sans-serif'
  }});
</script>
<style>
:root {{
  --bg-primary: #0d1117;
  --bg-secondary: #161b22;
  --bg-tertiary: #21262d;
  --bg-card: #1c2128;
  --text-main: #e6edf3;
  --text-muted: #8b949e;
  --accent: #58a6ff;
  --accent-hover: #79c0ff;
  --accent-green: #3fb950;
  --accent-yellow: #d29922;
  --accent-red: #f85149;
  --accent-purple: #bc8cff;
  --border-color: #30363d;
  --border-muted: #21262d;
  --table-stripe: rgba(255, 255, 255, 0.02);
  --code-bg: #11151c;
  --callout-note: #1f6feb;
  --callout-tip: #238636;
  --callout-warn: #9e6a03;
  --callout-imp: #bd561d;
  --callout-danger: #da3633;
}}

@media (prefers-color-scheme: light) {{
  :root[data-theme="auto"] {{
    --bg-primary: #ffffff;
    --bg-secondary: #f6f8fa;
    --bg-tertiary: #eaeef2;
    --bg-card: #f6f8fa;
    --text-main: #1f2328;
    --text-muted: #656d76;
    --accent: #0969da;
    --accent-hover: #0550ae;
    --border-color: #d0d7de;
    --border-muted: #eaeef2;
    --table-stripe: rgba(0, 0, 0, 0.02);
    --code-bg: #f6f8fa;
  }}
}}

:root[data-theme="light"] {{
  --bg-primary: #ffffff;
  --bg-secondary: #f6f8fa;
  --bg-tertiary: #eaeef2;
  --bg-card: #f6f8fa;
  --text-main: #1f2328;
  --text-muted: #656d76;
  --accent: #0969da;
  --accent-hover: #0550ae;
  --border-color: #d0d7de;
  --border-muted: #eaeef2;
  --table-stripe: rgba(0, 0, 0, 0.02);
  --code-bg: #f6f8fa;
}}

* {{
  box-sizing: border-box;
  margin: 0;
  padding: 0;
}}

html {{
  scroll-behavior: smooth;
  scroll-padding-top: 2rem;
}}

body {{
  font-family: 'Inter', -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  background-color: var(--bg-primary);
  color: var(--text-main);
  line-height: 1.65;
  font-size: 15px;
}}

/* Top Navigation Bar */
.topbar {{
  position: sticky;
  top: 0;
  z-index: 100;
  background: var(--bg-secondary);
  border-bottom: 1px solid var(--border-color);
  padding: 0.75rem 2rem;
  display: flex;
  align-items: center;
  justify-content: space-between;
  backdrop-filter: blur(10px);
}}

.topbar-brand {{
  display: flex;
  align-items: center;
  gap: 0.75rem;
  font-weight: 700;
  font-size: 1.1rem;
  color: var(--text-main);
  text-decoration: none;
}}

.badge {{
  display: inline-flex;
  align-items: center;
  font-size: 0.75rem;
  font-weight: 600;
  padding: 0.15rem 0.6rem;
  border-radius: 999px;
  background: rgba(88, 166, 255, 0.15);
  color: var(--accent);
  border: 1px solid rgba(88, 166, 255, 0.3);
}}

.topbar-actions {{
  display: flex;
  gap: 0.75rem;
  align-items: center;
}}

.btn {{
  background: var(--bg-tertiary);
  color: var(--text-main);
  border: 1px solid var(--border-color);
  padding: 0.4rem 0.8rem;
  border-radius: 6px;
  font-size: 0.85rem;
  cursor: pointer;
  display: inline-flex;
  align-items: center;
  gap: 0.4rem;
  text-decoration: none;
  font-weight: 500;
  transition: all 0.2s ease;
}}

.btn:hover {{
  background: var(--border-color);
  color: var(--accent);
}}

/* Layout */
.layout {{
  display: flex;
  max-width: 1480px;
  margin: 0 auto;
  padding: 2rem;
  gap: 2.5rem;
}}

.sidebar {{
  width: 320px;
  flex-shrink: 0;
  position: sticky;
  top: 4.5rem;
  height: calc(100vh - 5.5rem);
  overflow-y: auto;
  padding-right: 1rem;
}}

.sidebar::-webkit-scrollbar {{
  width: 5px;
}}
.sidebar::-webkit-scrollbar-thumb {{
  background: var(--border-color);
  border-radius: 3px;
}}

.content {{
  flex: 1;
  min-width: 0;
  max-width: 1040px;
}}

/* TOC Styling */
.toc-nav {{
  background: var(--bg-secondary);
  border: 1px solid var(--border-color);
  border-radius: 8px;
  padding: 1.25rem;
}}

.toc-title {{
  font-weight: 700;
  font-size: 0.95rem;
  margin-bottom: 0.85rem;
  padding-bottom: 0.5rem;
  border-bottom: 1px solid var(--border-color);
  color: var(--text-main);
}}

.toc-nav ul {{
  list-style: none;
  padding: 0;
  margin: 0;
}}

.toc-nav li {{
  margin: 0.35rem 0;
}}

.toc-nav li.toc-l2 {{
  font-size: 0.85rem;
  font-weight: 600;
}}

.toc-nav li.toc-l3 {{
  font-size: 0.8rem;
  padding-left: 1rem;
  color: var(--text-muted);
}}

.toc-nav a {{
  color: var(--text-muted);
  text-decoration: none;
  transition: color 0.15s ease;
  display: block;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}}

.toc-nav a:hover {{
  color: var(--accent);
}}

/* Typography */
h1, h2, h3, h4, h5, h6 {{
  color: var(--text-main);
  font-weight: 700;
  line-height: 1.3;
  margin-top: 2rem;
  margin-bottom: 1rem;
  position: relative;
}}

h1 {{
  font-size: 2.2rem;
  margin-top: 0;
  border-bottom: 1px solid var(--border-color);
  padding-bottom: 0.8rem;
}}

h2 {{
  font-size: 1.6rem;
  border-bottom: 1px solid var(--border-muted);
  padding-bottom: 0.5rem;
  margin-top: 3rem;
}}

h3 {{
  font-size: 1.25rem;
  margin-top: 2rem;
}}

h4 {{
  font-size: 1.05rem;
}}

.anchor {{
  opacity: 0;
  text-decoration: none;
  color: var(--text-muted);
  font-weight: 400;
  margin-left: 0.4rem;
  transition: opacity 0.2s ease;
}}

h1:hover .anchor, h2:hover .anchor, h3:hover .anchor, h4:hover .anchor {{
  opacity: 0.7;
}}

p {{
  margin-bottom: 1.1rem;
}}

a {{
  color: var(--accent);
  text-decoration: none;
}}

a:hover {{
  text-decoration: underline;
}}

hr {{
  border: none;
  height: 1px;
  background: var(--border-color);
  margin: 2.5rem 0;
}}

/* Tables */
.table-container {{
  overflow-x: auto;
  margin: 1.25rem 0 2rem 0;
  border-radius: 8px;
  border: 1px solid var(--border-color);
  background: var(--bg-secondary);
}}

table {{
  width: 100%;
  border-collapse: collapse;
  font-size: 0.9rem;
  text-align: left;
}}

th, td {{
  padding: 0.75rem 1rem;
  border-bottom: 1px solid var(--border-color);
}}

th {{
  background: var(--bg-tertiary);
  font-weight: 600;
  color: var(--text-main);
  border-bottom: 2px solid var(--border-color);
  white-space: nowrap;
}}

tbody tr:nth-child(even) {{
  background: var(--table-stripe);
}}

tbody tr:hover {{
  background: rgba(88, 166, 255, 0.05);
}}

/* Callouts / Alerts */
.callout {{
  margin: 1.25rem 0;
  padding: 1rem 1.25rem;
  border-radius: 8px;
  border-left: 4px solid var(--accent);
  background: var(--bg-card);
  border: 1px solid var(--border-color);
  border-left-width: 4px;
}}

.callout-header {{
  display: flex;
  align-items: center;
  gap: 0.5rem;
  font-weight: 600;
  margin-bottom: 0.4rem;
  font-size: 0.9rem;
  text-transform: uppercase;
  letter-spacing: 0.5px;
}}

.callout-note {{ border-left-color: var(--callout-note); }}
.callout-note .callout-header {{ color: var(--accent); }}

.callout-important {{ border-left-color: var(--callout-imp); }}
.callout-important .callout-header {{ color: #ffa657; }}

.callout-tip {{ border-left-color: var(--callout-tip); }}
.callout-tip .callout-header {{ color: var(--accent-green); }}

.callout-warning {{ border-left-color: var(--callout-warn); }}
.callout-warning .callout-header {{ color: var(--accent-yellow); }}

.callout-caution {{ border-left-color: var(--callout-danger); }}
.callout-caution .callout-header {{ color: var(--accent-red); }}

.callout-body {{
  font-size: 0.95rem;
  color: var(--text-main);
}}

blockquote {{
  margin: 1.25rem 0;
  padding: 0.75rem 1.25rem;
  border-left: 4px solid var(--accent);
  background: var(--bg-secondary);
  color: var(--text-muted);
  border-radius: 0 6px 6px 0;
}}

/* Lists */
ul, ol {{
  margin: 0.75rem 0 1.25rem 1.5rem;
}}

li {{
  margin: 0.35rem 0;
}}

li.task-item {{
  list-style: none;
  margin-left: -1.2rem;
  display: flex;
  align-items: center;
  gap: 0.4rem;
}}

.checkbox {{
  font-size: 1.1rem;
  color: var(--text-muted);
}}
.checkbox.checked {{
  color: var(--accent-green);
}}

/* Code & Pre */
pre {{
  background: var(--code-bg);
  border: 1px solid var(--border-color);
  border-radius: 8px;
  padding: 1.2rem;
  overflow-x: auto;
  font-family: 'JetBrains Mono', Consolas, monospace;
  font-size: 0.85rem;
  line-height: 1.5;
  margin: 1.25rem 0;
}}

code {{
  font-family: 'JetBrains Mono', Consolas, monospace;
  font-size: 0.88em;
  background: var(--code-bg);
  border: 1px solid var(--border-muted);
  padding: 0.15rem 0.35rem;
  border-radius: 4px;
}}

pre code {{
  border: none;
  padding: 0;
  background: transparent;
}}

.mermaid-wrap {{
  background: var(--bg-secondary);
  border: 1px solid var(--border-color);
  border-radius: 8px;
  padding: 1.5rem;
  margin: 1.5rem 0;
  display: flex;
  justify-content: center;
  overflow-x: auto;
}}

.mermaid-wrap pre.mermaid {{
  background: transparent;
  border: none;
  padding: 0;
  margin: 0;
}}

/* Footer */
footer {{
  border-top: 1px solid var(--border-color);
  padding: 2rem 0;
  margin-top: 4rem;
  text-align: center;
  color: var(--text-muted);
  font-size: 0.85rem;
}}

@media (max-width: 992px) {{
  .sidebar {{
    display: none;
  }}
  .layout {{
    padding: 1rem;
  }}
}}
</style>
</head>
<body>

<header class="topbar">
  <div class="topbar-brand">
    <span>🌪️ After The Storm</span>
    <span class="badge">v1.0 Master Plan</span>
  </div>
  <div class="topbar-actions">
    <button class="btn" onclick="toggleTheme()" title="Переключить тему">🌓 Тема</button>
    <button class="btn" onclick="window.print()" title="Печать">🖨️ Печать</button>
  </div>
</header>

<div class="layout">
  <aside class="sidebar">
    {'\n'.join(toc_html)}
  </aside>

  <main class="content">
    {'\n'.join(html_out)}
    <footer>
      <p>🌪️ After The Storm · Мастер-план развития игры · Создан для Godot 4.7.2</p>
    </footer>
  </main>
</div>

<script>
function toggleTheme() {{
  const html = document.documentElement;
  const current = html.getAttribute('data-theme') || 'dark';
  const next = current === 'dark' ? 'light' : 'dark';
  html.setAttribute('data-theme', next);
  localStorage.setItem('theme', next);
}}

(function initTheme() {{
  const saved = localStorage.getItem('theme');
  if (saved) {{
    document.documentElement.setAttribute('data-theme', saved);
  }} else {{
    document.documentElement.setAttribute('data-theme', 'dark');
  }}
}})();
</script>

</body>
</html>
"""

    html_path.write_text(full_html, encoding="utf-8")
    print(f"OK: Generated {html_path} ({len(full_html)} bytes)")

if __name__ == "__main__":
    src = Path(r"K:\After Wind\docs\GAME_EXPANSION_MASTERPLAN.md")
    dst = Path(r"K:\After Wind\docs\GAME_EXPANSION_MASTERPLAN.html")
    convert_md_to_html(src, dst)
