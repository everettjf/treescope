import { useMemo } from "react";
import { Doughnut } from "react-chartjs-2";
import { Chart as ChartJS, ArcElement, Tooltip as ChartTooltip, Legend } from "chart.js";
import { BarChart3 } from "lucide-react";
import type { HierarchySnapshot, ViewNode } from "../protocol";
import { kindColor } from "../store";
import { Popover, PopoverContent, PopoverTrigger } from "./ui/popover";
import { Button } from "./ui/button";

ChartJS.register(ArcElement, ChartTooltip, Legend);

/** Toolbar popover: a Chart.js doughnut of node-kind distribution + tree depth. */
export function Stats({ snapshot }: { snapshot?: HierarchySnapshot }) {
  const stats = useMemo(() => computeStats(snapshot), [snapshot]);

  return (
    <Popover>
      <PopoverTrigger asChild>
        <Button variant="ghost" size="icon" title="Hierarchy stats" disabled={!snapshot}>
          <BarChart3 className="h-3.5 w-3.5" />
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-64" align="end">
        {!stats ? (
          <div className="text-xs text-muted-foreground">No data</div>
        ) : (
          <div className="flex flex-col gap-2">
            <div className="text-xs font-semibold">Hierarchy stats</div>
            <div className="mx-auto h-40 w-40">
              <Doughnut
                data={{
                  labels: stats.entries.map((e) => e.kind),
                  datasets: [{
                    data: stats.entries.map((e) => e.count),
                    backgroundColor: stats.entries.map((e) => kindColor(e.kind)),
                    borderColor: "#1c1c1e",
                    borderWidth: 2,
                  }],
                }}
                options={{
                  plugins: { legend: { display: false } },
                  cutout: "62%",
                  animation: { duration: 250 },
                }}
              />
            </div>
            <div className="grid grid-cols-2 gap-x-3 gap-y-1 text-[11px]">
              {stats.entries.map((e) => (
                <div key={e.kind} className="flex items-center gap-1.5">
                  <span className="inline-block h-2 w-2 rounded-sm" style={{ background: kindColor(e.kind) }} />
                  <span className="text-muted-foreground">{e.kind}</span>
                  <span className="ml-auto font-mono">{e.count}</span>
                </div>
              ))}
            </div>
            <div className="mt-1 flex justify-between border-t border-border pt-1.5 text-[11px] text-muted-foreground">
              <span>total <span className="font-mono text-foreground">{stats.total}</span></span>
              <span>max depth <span className="font-mono text-foreground">{stats.maxDepth}</span></span>
            </div>
          </div>
        )}
      </PopoverContent>
    </Popover>
  );
}

function computeStats(snapshot?: HierarchySnapshot) {
  if (!snapshot) return null;
  const counts = new Map<string, number>();
  let total = 0, maxDepth = 0;
  const walk = (n: ViewNode, d: number) => {
    total++; maxDepth = Math.max(maxDepth, d);
    counts.set(n.kind, (counts.get(n.kind) ?? 0) + 1);
    n.children.forEach((c) => walk(c, d + 1));
  };
  snapshot.roots.forEach((r) => walk(r, 0));
  const entries = [...counts.entries()].map(([kind, count]) => ({ kind, count })).sort((a, b) => b.count - a.count);
  return { entries, total, maxDepth };
}
