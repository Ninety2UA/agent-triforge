---
name: tilde-fence
description: "Use when a fixture proves that body scans honor CommonMark fences (C16)."
---

# Tilde Fence

Everything inside the two fences below is code and must not be scanned as headings or links.

~~~bash
## Step 9: a heading inside a tilde fence
[escapes](../outside.md)
~~~

```
## Step 7: a heading inside a backtick fence closed by a longer closer
````

## Output

- A line.
