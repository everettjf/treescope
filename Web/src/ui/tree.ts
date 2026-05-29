import type { ViewNode } from "../protocol";
import { Flag, hasFlag } from "../protocol";
import { Store, kindColor, kindGlyph } from "../store";

/** Renders the hierarchy tree sidebar. */
export class TreeView {
  readonly el = document.createElement("div");
  private list = document.createElement("div");
  private searchInput = document.createElement("input");

  constructor(private store: Store, private onSelect: (id: string) => void) {
    this.el.className = "tree";

    const bar = document.createElement("div");
    bar.className = "tree-search";
    this.searchInput.type = "search";
    this.searchInput.placeholder = "Filter views…";
    this.searchInput.spellcheck = false;
    this.searchInput.addEventListener("input", () => {
      this.store.update((s) => { s.search = this.searchInput.value; });
    });
    bar.appendChild(this.searchInput);
    this.el.appendChild(bar);

    this.list.className = "tree-list";
    this.el.appendChild(this.list);
  }

  render(): void {
    const roots = this.store.displayRoots();
    this.list.replaceChildren();
    for (const root of roots) this.renderNode(root, 0);
    if (roots.length === 0) {
      const empty = document.createElement("div");
      empty.className = "tree-empty";
      empty.textContent = this.store.state.snapshot ? "No matching views" : "Not connected";
      this.list.appendChild(empty);
    }
  }

  private renderNode(node: ViewNode, depth: number): void {
    const { expanded, selectedID } = this.store.state;
    const isExpanded = expanded.has(node.id);
    const hasKids = node.children.length > 0;

    const row = document.createElement("div");
    row.className = "tree-row" + (node.id === selectedID ? " selected" : "");
    row.style.paddingLeft = `${depth * 14 + 6}px`;

    const twisty = document.createElement("span");
    twisty.className = "twisty";
    twisty.textContent = hasKids ? (isExpanded ? "▾" : "▸") : "";
    twisty.addEventListener("click", (e) => {
      e.stopPropagation();
      this.store.update((s) => {
        if (s.expanded.has(node.id)) s.expanded.delete(node.id);
        else s.expanded.add(node.id);
      });
    });
    row.appendChild(twisty);

    const glyph = document.createElement("span");
    glyph.className = "glyph";
    glyph.textContent = kindGlyph(node.kind);
    glyph.style.color = kindColor(node.kind);
    row.appendChild(glyph);

    const name = document.createElement("span");
    name.className = "node-name" + (node.kind === "swiftUI" ? " swiftui" : "");
    name.textContent = node.displayName;
    row.appendChild(name);

    const subtitle = nodeSubtitle(node);
    if (subtitle) {
      const sub = document.createElement("span");
      sub.className = "node-subtitle";
      sub.textContent = subtitle;
      row.appendChild(sub);
    }

    if (hasFlag(node, Flag.hidden)) {
      const badge = document.createElement("span");
      badge.className = "row-badge";
      badge.textContent = "hidden";
      row.appendChild(badge);
    }

    row.addEventListener("click", () => this.onSelect(node.id));
    this.list.appendChild(row);

    if (isExpanded) for (const child of node.children) this.renderNode(child, depth + 1);
  }
}

function nodeSubtitle(node: ViewNode): string {
  if (node.label) return node.label;
  // Surface a Text's content or a frame size hint.
  for (const section of node.sections) {
    for (const attr of section.attributes) {
      if ((attr.title === "text" || attr.title === "stringValue") && attr.value.t === "string" && attr.value.v) {
        return `"${attr.value.v}"`;
      }
    }
  }
  return "";
}
