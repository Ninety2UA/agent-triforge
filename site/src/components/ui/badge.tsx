import { cva, type VariantProps } from "class-variance-authority"
import { cn } from "cn"

// shadcn Badge: a small square-cornered label. default prints solid ink; secondary sits on the page.
const badgeVariants = cva("inline-flex h-[22px] items-center rounded-sm px-2 text-[0.8125rem] font-semibold whitespace-nowrap", {
  variants: {
    variant: {
      default: "bg-foreground text-background",
      secondary: "bg-background text-muted-foreground",
      outline: "border border-input text-muted-foreground",
    },
  },
  defaultVariants: { variant: "default" },
})

function Badge({ className, variant, ...props }: React.ComponentProps<"span"> & VariantProps<typeof badgeVariants>) {
  return <span data-slot="badge" className={cn(badgeVariants({ variant }), className)} {...props} />
}

export { Badge, badgeVariants }
