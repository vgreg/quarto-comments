# Quarto Comments Extension

The **Quarto Comments** extension adds collaboration-friendly annotations to Quarto documents. Authors can insert inline notes, to-dos, and discussion points that render as margin callouts in HTML outputs and as `todonotes` in PDF/LaTeX builds. Comments can be toggled globally and customised per author or reviewer.

## Installation

```bash
quarto add vgreg/quarto-comments
```

Then enable the extension for your project:

```yaml
project:
  extensions:
    - comments
```

## Shortcodes

Use the `comment` shortcode or one of its aliases directly inside your document:

```markdown
{{< comment "Need to expand this section" author="vg" type="todo" >}}
{{< note "Cross-check with appendix" >}}
{{< todo "Update Table 2 after rerun" author="sm" >}}
{{< question "Can we validate with external data?" inline=true >}}
```

### Arguments

| Argument    | Type                          | Description                                           |
|-------------|-------------------------------|-------------------------------------------------------|
| positional  | string                        | Required comment text                                 |
| `author`    | string                        | Matches a key defined in the configuration            |
| `type`      | comment \| todo \| note \| question | Controls styling for iconography and colours     |
| `inline`    | boolean                       | Forces inline rendering instead of a margin callout   |

All aliases (`todo`, `note`, `question`) map to the same underlying logic and set the default `type`.

## Configuration

Project-level options live under the `comments` key. They can override extension defaults:

```yaml
comments:
  enabled: true      # toggle comments globally
  show_author: true  # hide author labels when false
  authors:
    vg:
      name: "Vincent Gregoire"
      color_html: "#0072B2"
      color_latex: "blue!20"
    sm:
      name: "Samuel"
      color_html: "#D55E00"
      color_latex: "#FF8800"
```

- When `enabled: false`, all comment shortcodes are stripped from the output.
- Authors without defined colours fall back to sensible defaults per comment type.
- Anonymous comments (no `author`) automatically suppress author labels.

## Output Behaviour

### HTML

- Margin callouts styled as standard Quarto callouts, colourised per author or comment type.
- Inline comments render as compact badges that sit within text runs.
- Custom CSS is bundled (`_extensions/comments/assets/comments.css`) and injected automatically.

### PDF / LaTeX

- Comments render via the `todonotes` package; inline comments use `\todo[inline]{...}`.
- The filter injects `\usepackage{xcolor}` and `\usepackage{todonotes}` only when comments are present.
- Author-specific colours are defined dynamically. Hex colours are converted to `\definecolor`.
- Base layout hints (margin width, default todo styling) live in `_extensions/comments/assets/comments.sty`.

### Other Formats

Formats without specialised handling fall back to a simple textual representation such as:

```
TODO (vg): Need to expand this section.
```

## Minimal Example

A runnable example document is included at `example.qmd`. From the repository root you can render it to both HTML and PDF:

```bash
quarto render example.qmd --to html,pdf
```

The example demonstrates author configuration, margin callouts, and inline comments. Use it as a starting point when wiring the extension into your own projects.
