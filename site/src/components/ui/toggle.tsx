import { Toggle as TogglePrimitive } from "@base-ui/react/toggle"
import { cva, type VariantProps } from "class-variance-authority"
import { cn } from "cn"

// shadcn Toggle restyled to 4A's filter chip: quiet text that settles onto the muted surface when pressed.
const toggleVariants = cva(
  "group/toggle inline-flex cursor-pointer items-center justify-center gap-2 rounded-md border-[1.5px] border-transparent font-semibold whitespace-nowrap text-muted-foreground transition-colors hover:bg-muted hover:text-foreground disabled:pointer-events-none disabled:opacity-50 aria-pressed:border-input aria-pressed:bg-muted aria-pressed:text-foreground [&_svg]:pointer-events-none [&_svg]:shrink-0",
  {
    variants: {
      variant: { default: "bg-transparent", outline: "border-input bg-transparent" },
      size: { default: "h-[34px] px-3 text-[0.9375rem]", sm: "h-8 px-2.5 text-[0.9375rem]", lg: "h-10 px-4" },
    },
    defaultVariants: { variant: "default", size: "default" },
  }
)

function Toggle({ className, variant = "default", size = "default", ...props }: TogglePrimitive.Props & VariantProps<typeof toggleVariants>) {
  return <TogglePrimitive data-slot="toggle" className={cn(toggleVariants({ variant, size, className }))} {...props} />
}

export { Toggle, toggleVariants }
