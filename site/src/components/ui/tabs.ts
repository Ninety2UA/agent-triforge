// shadcn Tabs anatomy (style base-lyra), restyled to the site: a muted track, the selected tab raised
// onto the page, a 6 px radius. The site renders tabs in Astro with plain script (Tabs.astro,
// scripts/tabs.ts) instead of the Base UI component, because a tab must open from a link before any
// island hydrates; these are the component's class strings, so the look is the registry's.
import { cva } from "class-variance-authority"

export const tabsRoot = "group/tabs flex gap-2.5 data-horizontal:flex-col"

export const tabsListVariants = cva(
  "group/tabs-list inline-flex w-fit max-w-full flex-wrap items-center justify-center gap-0.5 rounded-lg p-[3px] text-muted-foreground group-data-vertical/tabs:h-fit group-data-vertical/tabs:flex-col data-[variant=line]:rounded-none",
  {
    variants: {
      variant: {
        default: "bg-muted",
        line: "gap-1 bg-transparent",
      },
    },
    defaultVariants: {
      variant: "default",
    },
  }
)

export const tabsTrigger = [
  "relative inline-flex h-[34px] cursor-pointer items-center justify-center gap-1.5 rounded-md px-3 text-[0.8125rem] font-semibold whitespace-nowrap text-muted-foreground transition-colors hover:text-foreground disabled:pointer-events-none disabled:opacity-50 sm:px-3.5 sm:text-[0.9375rem] [&_svg]:pointer-events-none [&_svg]:shrink-0",
  "data-active:bg-background data-active:text-foreground",
  "group-data-[variant=line]/tabs-list:data-active:bg-transparent group-data-[variant=line]/tabs-list:data-active:after:opacity-100",
  "after:absolute after:inset-x-2 after:bottom-[-4px] after:h-0.5 after:bg-primary after:opacity-0 after:transition-opacity",
].join(" ")

export const tabsContent = "flex-1 outline-none"
