import { Dialog, DialogContent, DialogTitle } from "./ui/dialog";

const SHORTCUTS: [string, string][] = [
  ["↑ / ↓", "Move selection up / down the tree"],
  ["→ / ←", "Expand / collapse the selected node"],
  ["⌘ R", "Recapture the hierarchy"],
  ["F", "Focus (center + zoom) the selected node"],
  ["⌘-scroll", "Zoom the canvas"],
  ["drag", "Pan the canvas (orbit in 3D mode)"],
  ["⌥ drag", "Pan while in 3D mode"],
  ["double-click", "Reset the 3D angle"],
  ["/", "Focus the search box"],
  ["?", "Show this help"],
];

export function ShortcutsHelp({ open, onOpenChange }: { open: boolean; onOpenChange: (o: boolean) => void }) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogTitle className="mb-3 text-sm font-semibold">Keyboard shortcuts</DialogTitle>
        <div className="grid grid-cols-1 gap-1.5">
          {SHORTCUTS.map(([key, desc]) => (
            <div key={key} className="flex items-center justify-between gap-4 text-xs">
              <span className="text-muted-foreground">{desc}</span>
              <kbd className="shrink-0 rounded border border-border bg-secondary px-1.5 py-0.5 font-mono text-[11px]">{key}</kbd>
            </div>
          ))}
        </div>
      </DialogContent>
    </Dialog>
  );
}
