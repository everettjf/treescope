import { Loader2, Wifi, WifiOff } from "lucide-react";
import { Button } from "./ui/button";
import type { Inspector } from "../hooks/useInspector";

/** Full-screen overlay shown until the first successful connection. */
export function ConnectionOverlay({ insp }: { insp: Inspector }) {
  const { state, reconnect } = insp;
  if (state.connection === "connected" && state.snapshot) return null;

  const connecting = state.connection === "connecting" || (state.connection !== "failed" && !state.snapshot);

  return (
    <div className="absolute inset-0 z-40 flex items-center justify-center bg-background/95 backdrop-blur">
      <div className="flex max-w-sm flex-col items-center gap-4 rounded-2xl border border-border bg-card p-8 text-center shadow-2xl">
        <div className="flex h-14 w-14 items-center justify-center rounded-2xl bg-primary/15">
          {connecting ? <Loader2 className="h-7 w-7 animate-spin text-primary" />
            : state.connection === "failed" ? <WifiOff className="h-7 w-7 text-[#ff453a]" />
            : <Wifi className="h-7 w-7 text-primary" />}
        </div>
        <div>
          <div className="text-base font-semibold">
            {connecting ? "Connecting to your app…" : state.connection === "failed" ? "Can't reach the app" : "Waiting…"}
          </div>
          <div className="mt-1 text-xs text-muted-foreground">
            {connecting
              ? "Make sure your app is running with Treescope.start()."
              : "The Treescope server isn't responding on this address."}
          </div>
        </div>
        <code className="rounded-md bg-secondary px-2 py-1 font-mono text-xs">{location.host}</code>
        {state.error && <div className="text-[11px] text-[#ff8a80]">{state.error}</div>}
        {state.connection === "failed" && (
          <Button onClick={reconnect} variant="secondary" size="sm">Retry</Button>
        )}
      </div>
    </div>
  );
}
