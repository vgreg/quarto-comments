# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Quarto extension written in Lua, CSS, and LaTeX that adds collaborative annotations (comments, to-dos, notes, questions) to Quarto documents. The extension renders differently based on output format: styled callouts in HTML, `todonotes` in PDF/LaTeX, and plain text fallback for other formats.

**Key files:**
- Extension manifest: [_extensions/comments/_extension.yml](_extensions/comments/_extension.yml)
- Shared logic: [_extensions/comments/shortcodes/comment_core.lua](_extensions/comments/shortcodes/comment_core.lua)
- Main filter: [_extensions/comments/filters/comments.lua](_extensions/comments/filters/comments.lua)
- HTML styling: [_extensions/comments/assets/comments.css](_extensions/comments/assets/comments.css)
- LaTeX styling: [_extensions/comments/assets/comments.sty](_extensions/comments/assets/comments.sty)

## Common Commands

### Testing the Extension
```bash
# Render example document to HTML and PDF
quarto render example.qmd --to html,pdf

# Render to specific format only
quarto render example.qmd --to html
quarto render example.qmd --to pdf
```

### Installation (for users)
```bash
# Install from GitHub
quarto add vgreg/quarto-comments
```

## Architecture

### Two-Phase Processing Pipeline

1. **Shortcode Phase**: Converts `{{< comment >}}` syntax to Pandoc AST nodes
   - Four shortcode handlers ([comment.lua](_extensions/comments/shortcodes/comment.lua), [todo.lua](_extensions/comments/shortcodes/todo.lua), [note.lua](_extensions/comments/shortcodes/note.lua), [question.lua](_extensions/comments/shortcodes/question.lua))
   - Each loads [comment_core.lua](_extensions/comments/shortcodes/comment_core.lua) dynamically via `dofile()`
   - Returns `Div` (block) or `Span` (inline) with metadata in data attributes
   - Includes fallback text for unsupported formats

2. **Filter Phase**: Post-processes AST for format-specific rendering
   - [comments.lua](_extensions/comments/filters/comments.lua) runs after shortcodes
   - `Meta()` hook: Reads configuration from document YAML frontmatter
   - `Div()`/`Span()` hooks: Transform comment elements based on output format
   - `Pandoc()` hook: Injects LaTeX headers if needed

### Output Format Handling

**HTML**: Creates styled Div elements that mimic Quarto callouts
- Uses CSS custom properties (`--comment-color`) for per-author theming
- Margin callouts (default) or inline badges (when `inline=true`)

**PDF/LaTeX**: Generates `\todo{}` commands from todonotes package
- Dynamically injects `\usepackage{xcolor}` and `\usepackage{todonotes}`
- Converts hex colors to LaTeX via `\definecolor`
- Inline or margin notes based on `inline` parameter

**Other formats**: Falls back to plain text (e.g., "TODO (vg): text")

### Configuration System

Extension behavior controlled via document YAML frontmatter:

```yaml
comments:
  enabled: true              # Toggle all comments on/off
  show_author: true          # Show/hide author names
  authors:                   # Author metadata
    vg:
      name: "Vincent Gregoire"
      color_html: "#0072B2"        # Hex color for HTML
      color_latex: "blue!20"       # LaTeX color spec
```

Configuration is read in the `Meta()` filter hook and stored in state for use during element transformation.

## Key Patterns

### Dynamic Module Loading
All shortcode handlers use this pattern to load shared logic from [comment_core.lua](_extensions/comments/shortcodes/comment_core.lua):

```lua
local function core()
  local source = debug.getinfo(1, "S").source:sub(2)
  local directory = source:match("(.*/)")
  return dofile(directory .. "comment_core.lua")
end
```

This avoids hardcoded paths and allows each handler to customize behavior via a `forced_type` parameter.

### Data Attribute Encoding
Comment metadata flows through the pipeline via HTML data attributes:
- `data-comment-type`: "comment" | "todo" | "note" | "question"
- `data-comment-text`: The comment content
- `data-comment-inline`: "true" | "false"
- `data-comment-author`: Author ID from configuration

The filter extracts these in `Div()`/`Span()` hooks for transformation.

### Stateful Filter Processing
[comments.lua](_extensions/comments/filters/comments.lua) maintains state across hooks:
- `state.config`: Configuration from `Meta()` phase
- `state.latex.defined_specs`: Tracks LaTeX color definitions to avoid duplicates
- `state.latex.header_lines`: Accumulates preamble injections for `Pandoc()` hook

### Format Detection with Fallback
```lua
local function is_html_format()
  if ok_quarto and quarto.doc and quarto.doc.is_format then
    return quarto.doc.is_format("html") or quarto.doc.is_format("revealjs")
  end
  return (FORMAT or ""):match("html") ~= nil
end
```

Checks Quarto API first, falls back to global `FORMAT` variable.

## Directory Structure

```
_extensions/
├── comments/                    # Main extension (local development)
│   ├── _extension.yml           # Manifest: shortcodes, filters, resources
│   ├── shortcodes/              # Shortcode handlers
│   │   ├── comment.lua
│   │   ├── todo.lua
│   │   ├── note.lua
│   │   ├── question.lua
│   │   └── comment_core.lua     # Shared rendering logic
│   ├── filters/
│   │   └── comments.lua         # Main post-processing filter
│   └── assets/
│       ├── comments.css         # HTML styling
│       └── comments.sty         # LaTeX layout hints
└── vgreg/comments/              # Published version (identical copy)
    └── [same structure]         # Used by `quarto add vgreg/quarto-comments`

example.qmd                      # Test/demo document
```

## Modification Guidelines

### Adding New Comment Types
1. Create new shortcode handler in [_extensions/comments/shortcodes/](_extensions/comments/shortcodes/)
2. Follow existing pattern: load `comment_core.lua` with custom `forced_type`
3. Add shortcode name to `_extension.yml`
4. Update CSS/LaTeX styling for new type

### Changing HTML Styling
- Edit [_extensions/comments/assets/comments.css](_extensions/comments/assets/comments.css)
- Uses CSS custom properties for colors
- Element structure defined in `build_html_block()` and `build_html_inline()` in [comments.lua](_extensions/comments/filters/comments.lua)

### Changing LaTeX Rendering
- Modify `build_latex()` function in [comments.lua](_extensions/comments/filters/comments.lua)
- Layout hints in [_extensions/comments/assets/comments.sty](_extensions/comments/assets/comments.sty)
- Must maintain `todonotes` package compatibility

### Supporting New Output Formats
Add format detection and transformation logic in [comments.lua](_extensions/comments/filters/comments.lua):
1. Create `is_<format>_format()` helper
2. Add case in `handle_comment()` function
3. Implement `build_<format>()` transformation

## Testing Strategy

No automated tests. Manual testing workflow:
1. Modify extension code
2. Run `quarto render example.qmd --to html,pdf`
3. Inspect HTML output in browser
4. Inspect PDF output for LaTeX rendering
5. Verify both margin and inline comments render correctly
6. Test with/without author configuration
7. Test with `enabled: false` to ensure comments are stripped
