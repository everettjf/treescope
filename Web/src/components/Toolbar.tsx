import { RefreshCw, Grid3x3, Image, Box, Layers, EyeOff, Minus, Plus } from "lucide-react";
import { countNodes } from "../store";
import type { Inspector } from "../hooks/useInspector";
import { Button } from "./ui/button";
import { Toggle } from "./ui/toggle";
import { Tooltip, TooltipContent, TooltipTrigger } from "./ui/tooltip";
import { cn } from "../lib/utils";

export function Toolbar({ insp }: { insp: Inspector }) {
  const { state, setOption, refresh } = insp;
  const { options, serverInfo, snapshot, connection } = state;
  const device = serverInfo?.device;

  return (
    <div className="flex h-[46px] shrink-0 items-center gap-3 border-b border-border bg-card px-3">
      <div className="min-w-[160px]">
        <div className="text-sm font-semibold leading-tight">{device?.appName ?? "Treescope"}</div>
        {device && (
          <div className="text-[10px] text-muted-foreground">
            {device.osName} {device.osVersion} · {device.deviceModel}
          </div>
        )}
      </div>

      <div className="flex flex-1 flex-wrap items-center gap-1.5">
        <Tip label="Recapture (⌘R)">
          <Button size="sm" onClick={refresh} disabled={state.refreshing}>
            <RefreshCw className={cn("h-3.5 w-3.5", state.refreshing && "animate-spin")} /> Refresh
          </Button>
        </Tip>
        <ToggleBtn label="Wireframe" icon={<Grid3x3 className="h-3.5 w-3.5" />} on={options.showWireframe}
                   onClick={() => setOption("showWireframe", !options.showWireframe)} />
        <ToggleBtn label="Snapshots" icon={<Image className="h-3.5 w-3.5" />} on={options.showSnapshots}
                   onClick={() => setOption("showSnapshots", !options.showSnapshots)} />
        <ToggleBtn label="Exploded 3D" icon={<Box className="h-3.5 w-3.5" />} on={options.exploded}
                   onClick={() => setOption("exploded", !options.exploded)} />
        <ToggleBtn label="CALayers (re-fetches)" icon={<Layers className="h-3.5 w-3.5" />} on={options.includeLayers}
                   onClick={() => setOption("includeLayers", !options.includeLayers)} />
        <ToggleBtn label="Hide system views" icon={<EyeOff className="h-3.5 w-3.5" />} on={options.hideSystem}
                   onClick={() => setOption("hideSystem", !options.hideSystem)} />

        <div className="ml-1 flex items-center gap-1">
          <Button variant="ghost" size="icon" onClick={() => setOption("zoom", Math.max(0.1, options.zoom - 0.2))}>
            <Minus className="h-3.5 w-3.5" />
          </Button>
          <span className="w-10 text-center font-mono text-[11px] text-muted-foreground">
            {Math.round(options.zoom * 100)}%
          </span>
          <Button variant="ghost" size="icon" onClick={() => setOption("zoom", Math.min(6, options.zoom + 0.2))}>
            <Plus className="h-3.5 w-3.5" />
          </Button>
          <Button variant="ghost" size="sm" onClick={() => setOption("zoom", 1)}>100%</Button>
        </div>
      </div>

      <div className="min-w-[150px] text-right text-[11px]">
        <span className={cn(
          connection === "connected" ? "text-[#30d158]" : connection === "failed" ? "text-[#ff453a]" : "text-muted-foreground",
        )}>
          {statusText(connection)}
        </span>
        {snapshot && <span className="text-muted-foreground"> · {countNodes(snapshot)} nodes</span>}
      </div>
    </div>
  );
}

function ToggleBtn({ label, icon, on, onClick }: { label: string; icon: React.ReactNode; on: boolean; onClick: () => void }) {
  return (
    <Tip label={label}>
      <Toggle size="sm" pressed={on} onPressedChange={onClick}>{icon}<span className="ml-1">{label.split(" ")[0]}</span></Toggle>
    </Tip>
  );
}

function Tip({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <Tooltip>
      <TooltipTrigger asChild>{children}</TooltipTrigger>
      <TooltipContent>{label}</TooltipContent>
    </Tooltip>
  );
}

function statusText(s: string): string {
  switch (s) {
    case "connected": return "● connected";
    case "connecting": return "○ connecting…";
    case "failed": return "● disconnected";
    default: return "○ offline";
  }
}
