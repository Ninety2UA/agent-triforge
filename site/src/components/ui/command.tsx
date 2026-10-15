"use client"

import * as React from "react"
import { Command as CommandPrimitive } from "cmdk"
import { cn } from "cn"

import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { Icon } from "@/components/Icon"

// shadcn Command restyled to 4A: a 640 px dialog 12vh from the top, a search row over a
// dotted rule, the selected row on the muted surface. No shadow.

// cmdk 1.1.1 recomputes aria-activedescendant only when its own key handling changes the
// selection. A controlled `value`, or new results that replace the selected option's
// element, leave the input naming an option that is no longer active or no longer exists.
// The option cmdk marks aria-selected="true" is always the right one, so after every change
// under the root the input and the list name that option's id. A MutationObserver runs in
// the same task as the change, before assistive technology reads the attribute.
function useActiveDescendant(root: React.RefObject<HTMLDivElement | null>) {
  React.useLayoutEffect(() => {
    const el = root.current
    if (!el) return
    const sync = () => {
      const id = el.querySelector('[cmdk-item][aria-selected="true"]')?.id
      for (const owner of el.querySelectorAll("[cmdk-input], [cmdk-list]")) {
        if (!id) owner.removeAttribute("aria-activedescendant")
        else if (owner.getAttribute("aria-activedescendant") !== id) owner.setAttribute("aria-activedescendant", id)
      }
    }
    const observer = new MutationObserver(sync)
    observer.observe(el, {
      subtree: true,
      childList: true,
      attributes: true,
      attributeFilter: ["aria-selected", "aria-activedescendant"],
    })
    sync()
    return () => observer.disconnect()
  }, [root])
}

function Command({
  className,
  ...props
}: Omit<React.ComponentProps<typeof CommandPrimitive>, "ref">) {
  const root = React.useRef<HTMLDivElement>(null)
  useActiveDescendant(root)
  return (
    <CommandPrimitive
      ref={root}
      data-slot="command"
      className={cn(
        "flex size-full flex-col overflow-hidden bg-popover text-popover-foreground",
        className
      )}
      {...props}
    />
  )
}

function CommandDialog({
  title = "Search",
  description = "Search the site",
  children,
  className,
  showCloseButton = false,
  finalFocus,
  ...props
}: Omit<React.ComponentProps<typeof Dialog>, "children"> &
  Pick<React.ComponentProps<typeof DialogContent>, "finalFocus"> & {
    title?: string
    description?: string
    className?: string
    showCloseButton?: boolean
    children: React.ReactNode
  }) {
  return (
    <Dialog {...props}>
      <DialogContent
        className={cn(
          "top-[12vh] flex max-h-[min(560px,calc(100dvh-120px))] w-[min(640px,calc(100vw-32px))] max-w-none translate-y-0 flex-col gap-0 overflow-hidden p-0 sm:max-w-none",
          className
        )}
        showCloseButton={showCloseButton}
        finalFocus={finalFocus}
      >
        {/* inside the popup, so the dialog's name and description come from its own content */}
        <DialogHeader className="sr-only">
          <DialogTitle>{title}</DialogTitle>
          <DialogDescription>{description}</DialogDescription>
        </DialogHeader>
        {children}
      </DialogContent>
    </Dialog>
  )
}

function CommandInput({
  className,
  after,
  ...props
}: React.ComponentProps<typeof CommandPrimitive.Input> & {
  /** shown at the end of the search row, such as the palette's esc control */
  after?: React.ReactNode
}) {
  return (
    <div
      data-slot="command-input-wrapper"
      className="flex items-center gap-2.5 border-b-2 border-dotted border-border px-3.5 text-muted-foreground [&_svg]:size-[18px] [&_svg]:shrink-0"
    >
      <Icon name="search" />
      <CommandPrimitive.Input
        data-slot="command-input"
        className={cn(
          "h-[54px] w-full min-w-0 border-0 bg-transparent font-sans text-base text-foreground outline-none placeholder:text-muted-foreground disabled:cursor-not-allowed disabled:opacity-50",
          className
        )}
        {...props}
      />
      {after}
    </div>
  )
}

function CommandList({
  className,
  ...props
}: React.ComponentProps<typeof CommandPrimitive.List>) {
  return (
    <CommandPrimitive.List
      data-slot="command-list"
      className={cn(
        "max-h-[calc(min(560px,100dvh-120px)-96px)] scroll-py-1.5 overflow-x-hidden overflow-y-auto p-1.5 outline-none",
        className
      )}
      {...props}
    />
  )
}

function CommandEmpty({
  className,
  ...props
}: React.ComponentProps<typeof CommandPrimitive.Empty>) {
  return (
    <CommandPrimitive.Empty
      data-slot="command-empty"
      className={cn("px-4 py-7 text-center text-[0.9375rem] text-muted-foreground", className)}
      {...props}
    />
  )
}

function CommandGroup({
  className,
  ...props
}: React.ComponentProps<typeof CommandPrimitive.Group>) {
  return (
    <CommandPrimitive.Group
      data-slot="command-group"
      className={cn(
        "overflow-hidden text-foreground **:[[cmdk-group-heading]]:px-2.5 **:[[cmdk-group-heading]]:pt-2.5 **:[[cmdk-group-heading]]:pb-1 **:[[cmdk-group-heading]]:text-[0.8125rem] **:[[cmdk-group-heading]]:font-semibold **:[[cmdk-group-heading]]:text-muted-foreground",
        className
      )}
      {...props}
    />
  )
}

function CommandItem({
  className,
  children,
  ...props
}: React.ComponentProps<typeof CommandPrimitive.Item>) {
  return (
    <CommandPrimitive.Item
      data-slot="command-item"
      className={cn(
        "group/command-item relative flex cursor-pointer items-center gap-3 px-2.5 py-2.5 text-[0.9375rem] outline-none select-none data-[disabled=true]:pointer-events-none data-[disabled=true]:opacity-50 rounded-md data-selected:bg-muted [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4",
        className
      )}
      {...props}
    >
      {children}
      <span className="ml-auto hidden group-data-[checked=true]/command-item:contents">
        <Icon name="check" />
      </span>
    </CommandPrimitive.Item>
  )
}

export {
  Command,
  CommandDialog,
  CommandInput,
  CommandList,
  CommandEmpty,
  CommandGroup,
  CommandItem,
}
