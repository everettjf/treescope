import { useState } from "react";
import { Copy, Check } from "lucide-react";
import type { Attribute, AttributeValue, RGBAColor, ViewNode } from "../protocol";
import { displayValue, hexColor, Flag, hasFlag } from "../protocol";
import { kindColor } from "../store";
import type { Inspector as InspState } from "../hooks/useInspector";
import { Badge } from "./ui/badge";
import { Switch } from "./ui/switch";
import { Input } from "./ui/input";

function CopyButton({ text }: { text: string }) {
  const [done, setDone] = useState(false);
  return (
    <button
      className="shrink-0 rounded p-0.5 text-muted-foreground opacity-0 transition-opacity hover:bg-secondary group-hover:opacity-100"
      title="Copy"
      onClick={(e) => {
        e.stopPropagation();
        navigator.clipboard?.writeText(text).then(() => { setDone(true); setTimeout(() => setDone(false), 1000); });
      }}
    >
      {done ? <Check className="h-3 w-3 text-[#30d158]" /> : <Copy className="h-3 w-3" />}
    </button>
  );
}

export function InspectorPanel({ insp }: { insp: InspState }) {
  const node = insp.selected;
  if (!node) {
    return <div className="flex h-full items-center justify-center text-muted-foreground">Select a view</div>;
  }
  return (
    <div className="h-full overflow-auto p-3.5">
      <Header node={node} />
      <Identity node={node} />
      {node.sections.map((s) => (
        <Section key={s.id} title={s.title}>
          {s.attributes.map((a) => (
            <Row key={a.id} nodeID={node.id} attr={a} onEdit={insp.setAttribute} />
          ))}
        </Section>
      ))}
    </div>
  );
}

function Header({ node }: { node: ViewNode }) {
  return (
    <div className="mb-3 flex items-center gap-2.5">
      <span className="h-3 w-3 shrink-0 rounded-sm" style={{ background: kindColor(node.kind) }} />
      <div className="group min-w-0 flex-1">
        <div className="font-semibold">{node.displayName}</div>
        <div className="flex items-start gap-1">
          <div className="break-all font-mono text-[11px] text-muted-foreground">{node.className}</div>
          <CopyButton text={node.className} />
        </div>
      </div>
    </div>
  );
}

function Identity({ node }: { node: ViewNode }) {
  return (
    <div className="mb-3.5 rounded-lg bg-white/[0.04] p-2.5">
      <div className="mb-1.5 flex flex-wrap gap-1.5">
        <Badge style={{ color: kindColor(node.kind), borderColor: kindColor(node.kind) }}>{node.kind}</Badge>
        {hasFlag(node, Flag.hostsSwiftUI) && <Badge style={{ color: "#ff9f0a", borderColor: "#ff9f0a" }}>SwiftUI</Badge>}
        {hasFlag(node, Flag.hidden) && <Badge style={{ color: "#98989d", borderColor: "#98989d" }}>hidden</Badge>}
        {hasFlag(node, Flag.systemView) && <Badge style={{ color: "#98989d", borderColor: "#98989d" }}>system</Badge>}
      </div>
      <Labeled k="Frame" v={rectStr(node.frame)} />
      <Labeled k="Bounds" v={rectStr(node.bounds)} />
      <Labeled k="Opacity" v={node.opacity.toFixed(2)} />
      {node.children.length > 0 && <Labeled k="Children" v={String(node.children.length)} />}
    </div>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  const [open, setOpen] = useState(true);
  return (
    <div className="mb-3.5">
      <button
        className="mb-1.5 flex w-full items-center text-[11px] font-semibold uppercase tracking-wide text-muted-foreground"
        onClick={() => setOpen((o) => !o)}
      >
        <span className="mr-1">{open ? "▾" : "▸"}</span>{title}
      </button>
      {open && <div>{children}</div>}
    </div>
  );
}

function Row({
  nodeID, attr, onEdit,
}: {
  nodeID: string; attr: Attribute; onEdit: (nodeID: string, keyPath: string, value: AttributeValue) => void;
}) {
  const commit = (v: AttributeValue) => { if (attr.keyPath) onEdit(nodeID, attr.keyPath, v); };
  return (
    <div className="flex min-h-[22px] items-center gap-2 py-0.5">
      <span className="w-28 shrink-0 text-[12px] text-muted-foreground">{attr.title}</span>
      <div className="flex-1 text-right">
        <Value attr={attr} commit={commit} />
      </div>
    </div>
  );
}

function Value({ attr, commit }: { attr: Attribute; commit: (v: AttributeValue) => void }) {
  const v = attr.value;

  if (v.t === "bool") {
    return attr.editable ? (
      <div className="flex justify-end">
        <Switch checked={v.v} onCheckedChange={(c) => commit({ t: "bool", v: c })} />
      </div>
    ) : <span className="font-mono text-[12px]">{v.v ? "true" : "false"}</span>;
  }

  if (v.t === "color") {
    return <ColorValue c={v.v} editable={attr.editable} onChange={(c) => commit({ t: "color", v: c })} />;
  }

  if (attr.editable && (v.t === "number" || v.t === "integer" || v.t === "string" || v.t === "enum")) {
    return (
      <Input
        defaultValue={displayValue(v)}
        className="h-6 text-right font-mono"
        onBlur={(e) => commitText(v.t, e.target.value, commit)}
        onKeyDown={(e) => { if (e.key === "Enter") (e.target as HTMLInputElement).blur(); }}
      />
    );
  }

  if (v.t === "nested") {
    return (
      <div className="flex flex-col items-end gap-0.5">
        {v.v.map((sub) => (
          <div key={sub.id} className="flex gap-1.5">
            <span className="font-mono text-[11px] text-muted-foreground">{sub.title}</span>
            <span className="font-mono text-[11px]">{displayValue(sub.value)}</span>
          </div>
        ))}
      </div>
    );
  }

  return <span className="break-words font-mono text-[12px]">{displayValue(v)}</span>;
}

function commitText(t: string, text: string, commit: (v: AttributeValue) => void) {
  if (t === "number") { const n = parseFloat(text); if (!isNaN(n)) commit({ t: "number", v: n }); }
  else if (t === "integer") { const n = parseInt(text, 10); if (!isNaN(n)) commit({ t: "integer", v: n }); }
  else if (t === "enum") commit({ t: "enum", v: text });
  else commit({ t: "string", v: text });
}

function ColorValue({ c, editable, onChange }: { c: RGBAColor; editable: boolean; onChange: (c: RGBAColor) => void }) {
  return (
    <span className="flex items-center justify-end gap-1.5">
      {editable ? (
        <input
          type="color"
          className="h-4 w-4 cursor-pointer rounded border border-border bg-transparent p-0"
          defaultValue={hexNoAlpha(c)}
          onChange={(e) => onChange({ ...hexToRGBA(e.target.value), alpha: c.alpha })}
        />
      ) : (
        <span className="inline-block h-4 w-4 rounded border border-border"
              style={{ background: `rgba(${r255(c.red)},${r255(c.green)},${r255(c.blue)},${c.alpha})` }} />
      )}
      <span className="font-mono text-[11px] text-muted-foreground">{hexColor(c)}</span>
    </span>
  );
}

function Labeled({ k, v }: { k: string; v: string }) {
  return (
    <div className="flex justify-between gap-2 py-0.5">
      <span className="text-muted-foreground">{k}</span>
      <span className="font-mono">{v}</span>
    </div>
  );
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
