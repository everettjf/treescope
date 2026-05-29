import type { Attribute, AttributeValue, RGBAColor, ViewNode } from "../protocol";
import { displayValue, hexColor, Flag, hasFlag } from "../protocol";
import { Store, kindColor } from "../store";

/** Property inspector with typed rendering and live editing. */
export class Inspector {
  readonly el = document.createElement("div");

  constructor(
    private store: Store,
    private onEdit: (nodeID: string, keyPath: string, value: AttributeValue) => void,
  ) {
    this.el.className = "inspector";
  }

  render(): void {
    const node = this.store.selectedNode;
    this.el.replaceChildren();
    if (!node) {
      const empty = document.createElement("div");
      empty.className = "inspector-empty";
      empty.textContent = "Select a view";
      this.el.appendChild(empty);
      return;
    }
    this.el.appendChild(this.header(node));
    this.el.appendChild(this.identity(node));
    for (const section of node.sections) this.el.appendChild(this.section(node.id, section));
  }

  private header(node: ViewNode): HTMLElement {
    const h = document.createElement("div");
    h.className = "insp-header";
    const dot = document.createElement("span");
    dot.className = "insp-dot";
    dot.style.background = kindColor(node.kind);
    h.appendChild(dot);
    const text = document.createElement("div");
    text.className = "insp-title";
    const name = document.createElement("div");
    name.className = "insp-name";
    name.textContent = node.displayName;
    const cls = document.createElement("div");
    cls.className = "insp-class";
    cls.textContent = node.className;
    text.append(name, cls);
    h.appendChild(text);
    return h;
  }

  private identity(node: ViewNode): HTMLElement {
    const box = document.createElement("div");
    box.className = "insp-identity";
    const badges = document.createElement("div");
    badges.className = "insp-badges";
    badges.appendChild(badge(node.kind, kindColor(node.kind)));
    if (hasFlag(node, Flag.hostsSwiftUI)) badges.appendChild(badge("SwiftUI", "#ff9f0a"));
    if (hasFlag(node, Flag.hidden)) badges.appendChild(badge("hidden", "#98989d"));
    if (hasFlag(node, Flag.systemView)) badges.appendChild(badge("system", "#98989d"));
    box.appendChild(badges);
    box.appendChild(labeled("Frame", rectStr(node.frame)));
    box.appendChild(labeled("Bounds", rectStr(node.bounds)));
    box.appendChild(labeled("Opacity", node.opacity.toFixed(2)));
    if (node.children.length) box.appendChild(labeled("Children", String(node.children.length)));
    return box;
  }

  private section(nodeID: string, section: { title: string; attributes: Attribute[] }): HTMLElement {
    const wrap = document.createElement("div");
    wrap.className = "insp-section";
    const title = document.createElement("div");
    title.className = "insp-section-title";
    title.textContent = section.title;
    wrap.appendChild(title);
    for (const attr of section.attributes) wrap.appendChild(this.row(nodeID, attr));
    return wrap;
  }

  private row(nodeID: string, attr: Attribute): HTMLElement {
    const row = document.createElement("div");
    row.className = "insp-row";
    const key = document.createElement("span");
    key.className = "insp-key";
    key.textContent = attr.title;
    row.appendChild(key);
    row.appendChild(this.valueEl(nodeID, attr));
    return row;
  }

  private valueEl(nodeID: string, attr: Attribute): HTMLElement {
    const v = attr.value;
    const commit = (val: AttributeValue) => { if (attr.keyPath) this.onEdit(nodeID, attr.keyPath, val); };

    if (v.t === "bool") {
      if (attr.editable) {
        const cb = document.createElement("input");
        cb.type = "checkbox";
        cb.className = "insp-toggle";
        cb.checked = v.v;
        cb.addEventListener("change", () => commit({ t: "bool", v: cb.checked }));
        return cb;
      }
      const span = document.createElement("span");
      span.className = "insp-val mono";
      span.textContent = v.v ? "true" : "false";
      return span;
    }

    if (v.t === "color") {
      return this.colorEl(v.v, attr.editable, (c) => commit({ t: "color", v: c }));
    }

    if (attr.editable && (v.t === "number" || v.t === "integer" || v.t === "string" || v.t === "enum")) {
      const input = document.createElement("input");
      input.className = "insp-input mono";
      input.value = displayValue(v);
      input.addEventListener("change", () => {
        if (v.t === "number") { const n = parseFloat(input.value); if (!isNaN(n)) commit({ t: "number", v: n }); }
        else if (v.t === "integer") { const n = parseInt(input.value, 10); if (!isNaN(n)) commit({ t: "integer", v: n }); }
        else if (v.t === "enum") commit({ t: "enum", v: input.value });
        else commit({ t: "string", v: input.value });
      });
      return input;
    }

    if (v.t === "nested") {
      const box = document.createElement("div");
      box.className = "insp-nested";
      for (const sub of v.v) {
        const line = document.createElement("div");
        line.className = "insp-nested-line";
        line.innerHTML = `<span class="mono dim">${escapeHtml(sub.title)}</span> <span class="mono">${escapeHtml(displayValue(sub.value))}</span>`;
        box.appendChild(line);
      }
      return box;
    }

    const span = document.createElement("span");
    span.className = "insp-val mono";
    span.textContent = displayValue(v);
    return span;
  }

  private colorEl(c: RGBAColor, editable: boolean, onChange: (c: RGBAColor) => void): HTMLElement {
    const wrap = document.createElement("span");
    wrap.className = "insp-color";
    const swatch = document.createElement(editable ? "input" : "span");
    if (editable && swatch instanceof HTMLInputElement) {
      swatch.type = "color";
      swatch.className = "insp-swatch";
      swatch.value = hexNoAlpha(c);
      swatch.addEventListener("input", () => onChange({ ...hexToRGBA(swatch.value), alpha: c.alpha }));
    } else {
      swatch.className = "insp-swatch static";
      (swatch as HTMLElement).style.background = `rgba(${r255(c.red)},${r255(c.green)},${r255(c.blue)},${c.alpha})`;
    }
    wrap.appendChild(swatch);
    const hex = document.createElement("span");
    hex.className = "mono dim";
    hex.textContent = hexColor(c);
    wrap.appendChild(hex);
    return wrap;
  }
}

function badge(text: string, color: string): HTMLElement {
  const b = document.createElement("span");
  b.className = "insp-badge";
  b.textContent = text;
  b.style.color = color;
  b.style.borderColor = color;
  return b;
}

function labeled(title: string, value: string): HTMLElement {
  const row = document.createElement("div");
  row.className = "insp-labeled";
  row.innerHTML = `<span class="dim">${escapeHtml(title)}</span><span class="mono">${escapeHtml(value)}</span>`;
  return row;
}

function rectStr(r: { x: number; y: number; width: number; height: number }): string {
  return `{${r.x.toFixed(1)}, ${r.y.toFixed(1)}, ${r.width.toFixed(1)}, ${r.height.toFixed(1)}}`;
}
function r255(v: number): number { return Math.round(Math.max(0, Math.min(1, v)) * 255); }
function hexNoAlpha(c: RGBAColor): string {
  const h = (v: number) => r255(v).toString(16).padStart(2, "0");
  return `#${h(c.red)}${h(c.green)}${h(c.blue)}`;
}
function hexToRGBA(hex: string): RGBAColor {
  const n = hex.replace("#", "");
  return {
    red: parseInt(n.slice(0, 2), 16) / 255,
    green: parseInt(n.slice(2, 4), 16) / 255,
    blue: parseInt(n.slice(4, 6), 16) / 255,
    alpha: 1,
  };
}
function escapeHtml(s: string): string {
  return s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]!));
}
