import { Button as ButtonPrimitive } from "@base-ui/react/button"
import { cva, type VariantProps } from "class-variance-authority"
import { cn } from "cn"

// shadcn Button (added with the CLI, style base-lyra), restyled to 4A: a 6 px radius, a 1.5 px border,
// no shadow, the example's accent only on the primary action, the page's own focus outline.
const buttonCva = cva(
  "group/button inline-flex shrink-0 cursor-pointer items-center justify-center rounded-md border-[1.5px] border-transparent bg-clip-padding font-semibold whitespace-nowrap no-underline transition-[background-color,border-color,color,transform] duration-150 outline-none select-none active:not-aria-[haspopup]:scale-[0.98] disabled:pointer-events-none disabled:opacity-50 aria-invalid:border-destructive aria-invalid:ring-1 aria-invalid:ring-destructive/20 dark:aria-invalid:border-destructive/50 dark:aria-invalid:ring-destructive/40 [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4",
  {
    variants: {
      variant: {
        default: "bg-primary text-primary-foreground hover:bg-primary/88",
        outline: "border-input bg-transparent text-foreground hover:border-foreground hover:bg-muted aria-expanded:bg-muted",
        secondary: "bg-muted text-foreground hover:bg-muted/70 aria-expanded:bg-muted",
        ghost: "text-foreground hover:bg-muted aria-expanded:bg-muted",
        destructive: "bg-destructive text-primary-foreground hover:bg-destructive/88",
        link: "text-foreground underline underline-offset-4",
      },
      size: {
        default: "h-11 gap-2 px-5 text-[0.9375rem] [&_svg:not([class*='size-'])]:size-[18px]",
        xs: "h-8 gap-1.5 px-2.5 text-[0.8125rem] [&_svg:not([class*='size-'])]:size-[15px]",
        sm: "h-9 gap-2 px-3.5 text-[0.9375rem] [&_svg:not([class*='size-'])]:size-4",
        lg: "h-12 gap-2 px-6 text-base",
        icon: "size-10 [&_svg:not([class*='size-'])]:size-5",
        "icon-xs": "size-7 [&_svg:not([class*='size-'])]:size-3.5",
        "icon-sm": "size-8 [&_svg:not([class*='size-'])]:size-4",
        "icon-lg": "size-11 [&_svg:not([class*='size-'])]:size-5",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  }
)

// cva concatenates; cn merges the conflicting utilities (border-transparent vs border-input), so links
// styled with buttonVariants() in Astro get the same classes as the Button component.
const buttonVariants = ({ className, ...variants }: VariantProps<typeof buttonCva> & { className?: string } = {}) =>
  cn(buttonCva(variants), className)

function Button({
  className,
  variant = "default",
  size = "default",
  ...props
}: Omit<ButtonPrimitive.Props, "className"> & { className?: string } & VariantProps<typeof buttonCva>) {
  return (
    <ButtonPrimitive
      data-slot="button"
      className={buttonVariants({ variant, size, className })}
      {...props}
    />
  )
}

export { Button, buttonVariants }
