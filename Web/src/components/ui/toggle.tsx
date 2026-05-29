import * as React from "react";
import * as TogglePrimitive from "@radix-ui/react-toggle";
import { cva, type VariantProps } from "class-variance-authority";
import { cn } from "@/lib/utils";

const toggleVariants = cva(
  "inline-flex items-center justify-center gap-1.5 rounded-md text-xs font-medium transition-colors hover:bg-secondary focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring data-[state=on]:bg-primary/20 data-[state=on]:text-primary disabled:pointer-events-none disabled:opacity-50 border border-transparent data-[state=on]:border-primary/40",
  {
    variants: { size: { default: "h-7 px-2.5", sm: "h-6 px-2" } },
    defaultVariants: { size: "default" },
  },
);

export const Toggle = React.forwardRef<
  React.ElementRef<typeof TogglePrimitive.Root>,
  React.ComponentPropsWithoutRef<typeof TogglePrimitive.Root> & VariantProps<typeof toggleVariants>
>(({ className, size, ...props }, ref) => (
  <TogglePrimitive.Root ref={ref} className={cn(toggleVariants({ size, className }))} {...props} />
));
Toggle.displayName = TogglePrimitive.Root.displayName;
