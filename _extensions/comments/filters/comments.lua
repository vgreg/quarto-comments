local ok_quarto, quarto = pcall(require, "quarto")

local DEFAULT_HTML_COLORS = {
  comment = "#6C757D",
  todo = "#D55E00",
  note = "#0072B2",
  question = "#8E44AD",
}

local DEFAULT_LATEX_COLORS = {
  comment = "gray!20",
  todo = "red!20",
  note = "blue!20",
  question = "cyan!20",
}

local CALLOUT_VARIANTS = {
  comment = "callout-note",
  todo = "callout-warning",
  note = "callout-tip",
  question = "callout-important",
}

local state = {
  config = {
    enabled = true,
    show_author = true,
    authors = {},
  },
  comments_seen = false,
  latex = {
    needed = false,
    defined_specs = {},
    header_lines = {},
  },
}

local function shallow_copy(tbl)
  local copy = {}
  for key, value in pairs(tbl) do
    copy[key] = value
  end
  return copy
end

local function sanitize_identifier(value)
  if not value then
    return nil
  end
  local cleaned = tostring(value)
  cleaned = cleaned:gsub("%s+", "-")
  cleaned = cleaned:gsub("[^%w%-_]", "")
  if cleaned == "" then
    return nil
  end
  return cleaned
end

local function meta_to_string(value)
  if value == nil then
    return nil
  end
  local value_type = type(value)
  if value_type == "string" then
    return value
  end
  if value_type == "boolean" or value_type == "number" then
    return tostring(value)
  end
  if type(value) == "table" and value.t then
    if value.t == "MetaString" then
      return value.text
    elseif value.t == "MetaBool" then
      return value.c and "true" or "false"
    elseif value.t == "MetaInlines" or value.t == "MetaBlocks" then
      return pandoc.utils.stringify(value)
    end
  end
  return nil
end

local function meta_to_bool(value)
  if value == nil then
    return nil
  end
  if type(value) == "boolean" then
    return value
  end
  if type(value) == "table" and value.t == "MetaBool" then
    return value.c
  end
  local text = meta_to_string(value)
  if not text then
    return nil
  end
  text = text:lower()
  if text == "true" or text == "1" or text == "yes" then
    return true
  end
  if text == "false" or text == "0" or text == "no" then
    return false
  end
  return nil
end

local function populate_authors(meta_authors)
  if not meta_authors or meta_authors.t ~= "MetaMap" then
    return
  end
  for key, author_meta in pairs(meta_authors) do
    if type(author_meta) == "table" and author_meta.t == "MetaMap" then
      local author = {}
      for field, value in pairs(author_meta) do
        if field == "name" then
          author.name = meta_to_string(value)
        elseif field == "color_html" then
          author.color_html = meta_to_string(value)
        elseif field == "color_latex" then
          author.color_latex = meta_to_string(value)
        end
      end
      state.config.authors[key] = author
    end
  end
end

function Meta(meta)
  state.config = {
    enabled = true,
    show_author = true,
    authors = {},
  }

  local config_meta = meta.comments
  if config_meta and config_meta.t == "MetaMap" then
    for key, value in pairs(config_meta) do
      if key == "enabled" then
        local enabled = meta_to_bool(value)
        if enabled ~= nil then
          state.config.enabled = enabled
        end
      elseif key == "show_author" then
        local show_author = meta_to_bool(value)
        if show_author ~= nil then
          state.config.show_author = show_author
        end
      elseif key == "authors" then
        populate_authors(value)
      end
    end
  end

  return meta
end

local function has_class(el, class)
  if not el or not el.classes then
    return false
  end
  for _, existing in ipairs(el.classes) do
    if existing == class then
      return true
    end
  end
  return false
end

local function is_comment_node(el)
  if not el or not el.attributes then
    return false
  end
  if not has_class(el, "quarto-comment") then
    return false
  end
  if el.attributes["data-comment-type"] == nil then
    return false
  end
  return true
end

local function type_label(comment_type)
  if comment_type == "todo" then
    return "To-do"
  elseif comment_type == "note" then
    return "Note"
  elseif comment_type == "question" then
    return "Question"
  end
  return "Comment"
end

local function get_comment_data(el)
  local attrs = el.attributes or {}
  local comment = {
    type = (attrs["data-comment-type"] or "comment"):lower(),
    text = attrs["data-comment-text"] or "",
    inline = (attrs["data-comment-inline"] or "false"):lower() == "true",
    author_id = attrs["data-comment-author"],
    original_attr = el.attr,
  }

  if comment.type ~= "todo" and comment.type ~= "note" and comment.type ~= "question" then
    comment.type = "comment"
  end

  return comment
end

local function resolve_author(comment)
  local author_id = comment.author_id
  if not author_id then
    return nil
  end
  local author = state.config.authors[author_id]
  if not author then
    return {
      id = author_id,
      name = author_id,
    }
  end
  local resolved = shallow_copy(author)
  resolved.id = author_id
  if not resolved.name or resolved.name == "" then
    resolved.name = author_id
  end
  return resolved
end

local function resolve_html_color(comment, author)
  if author and author.color_html and author.color_html ~= "" then
    return author.color_html
  end
  return DEFAULT_HTML_COLORS[comment.type] or DEFAULT_HTML_COLORS.comment
end

local function ensure_latex_color_definition(key, hex)
  if state.latex.defined_specs[key] then
    return state.latex.defined_specs[key]
  end
  local color_name = "commentColor" .. key
  local line = string.format("\\definecolor{%s}{HTML}{%s}", color_name, hex)
  table.insert(state.latex.header_lines, line)
  state.latex.defined_specs[key] = color_name
  return color_name
end

local function resolve_latex_color(comment, author)
  local color_spec
  if author and author.color_latex and author.color_latex ~= "" then
    color_spec = author.color_latex
  else
    color_spec = DEFAULT_LATEX_COLORS[comment.type] or DEFAULT_LATEX_COLORS.comment
  end
  if not color_spec or color_spec == "" then
    return nil
  end

  if color_spec:match("^#%x%x%x%x%x%x$") then
    local key = sanitize_identifier((author and author.id) or comment.type) or comment.type
    return ensure_latex_color_definition(key, color_spec:sub(2))
  end
  return color_spec
end

local function is_html_format()
  if ok_quarto and quarto.doc and quarto.doc.is_format then
    if quarto.doc.is_format("html") or quarto.doc.is_format("revealjs") then
      return true
    end
  end
  local format = FORMAT or ""
  return format:match("html") ~= nil
end

local function is_latex_format()
  if ok_quarto and quarto.doc and quarto.doc.is_format then
    if quarto.doc.is_format("latex") or quarto.doc.is_format("pdf") then
      return true
    end
  end
  local format = FORMAT or ""
  return format:match("latex") ~= nil or format:match("pdf") ~= nil
end

local function escape_latex(text)
  local escaped = text
  escaped = escaped:gsub("\\", "\\textbackslash{}")
  escaped = escaped:gsub("{", "\\{")
  escaped = escaped:gsub("}", "\\}")
  escaped = escaped:gsub("%$", "\\$")
  escaped = escaped:gsub("&", "\\&")
  escaped = escaped:gsub("#", "\\#")
  escaped = escaped:gsub("%%", "\\%%")
  escaped = escaped:gsub("_", "\\_")
  escaped = escaped:gsub("~", "\\textasciitilde{}")
  escaped = escaped:gsub("%^", "\\textasciicircum{}")
  return escaped
end

local function build_html_inline(comment, author, html_color)
  local classes = { "quarto-comment", "quarto-comment-inline", "comment-" .. comment.type }
  local attributes = {
    ["data-comment-type"] = comment.type,
    ["data-comment-inline"] = "true",
  }

  if html_color then
    attributes.style = string.format("--comment-color:%s;", html_color)
  end

  if author then
    local sanitized = sanitize_identifier(author.id)
    if sanitized then
      table.insert(classes, "comment-author-" .. sanitized)
    end
    attributes["data-comment-author"] = author.id
    attributes["data-comment-author-name"] = author.name
  end

  local content = pandoc.List()
  local show_author = state.config.show_author and author and author.name and author.name ~= ""
  if show_author then
    content:insert(pandoc.Strong { pandoc.Str(author.name .. ": ") })
  end
  content:insert(pandoc.Str(comment.text))

  return pandoc.Span(content, pandoc.Attr("", classes, attributes))
end

local function build_html_block(comment, author, html_color)
  local classes = {
    "quarto-comment",
    "quarto-comment-block",
    "comment-" .. comment.type,
    "callout",
    "callout-margin",
    CALLOUT_VARIANTS[comment.type] or CALLOUT_VARIANTS.comment,
  }
  local attributes = {
    ["data-comment-type"] = comment.type,
  }

  if html_color then
    attributes.style = string.format("--comment-color:%s;", html_color)
  end

  if author then
    local sanitized = sanitize_identifier(author.id)
    if sanitized then
      table.insert(classes, "comment-author-" .. sanitized)
    end
    attributes["data-comment-author"] = author.id
    attributes["data-comment-author-name"] = author.name
  end

  local title_text
  local show_author = state.config.show_author and author and author.name and author.name ~= ""
  if show_author then
    title_text = author.name
  else
    title_text = type_label(comment.type)
  end
  local title_inlines = pandoc.List()
  title_inlines:insert(pandoc.Str(title_text))
  if show_author and comment.type ~= "comment" then
    title_inlines:insert(pandoc.Space())
    title_inlines:insert(pandoc.Str("— " .. type_label(comment.type)))
  elseif not show_author and comment.type ~= "comment" then
    title_inlines:insert(pandoc.Str(" (" .. type_label(comment.type) .. ")"))
  end

  local content_para = pandoc.Para({ pandoc.Str(comment.text) })
  local title_div = pandoc.Div({ pandoc.Plain(title_inlines) }, pandoc.Attr("", { "callout-title" }))
  local content_div = pandoc.Div({ content_para }, pandoc.Attr("", { "callout-content" }))
  local body_div = pandoc.Div({ title_div, content_div }, pandoc.Attr("", { "callout-body" }))

  return pandoc.Div({ body_div }, pandoc.Attr("", classes, attributes))
end

local function build_latex(comment, author)
  state.latex.needed = true

  local latex_color = resolve_latex_color(comment, author)
  local options = {}
  if comment.inline then
    table.insert(options, "inline")
  end
  if latex_color and latex_color ~= "" then
    table.insert(options, "color=" .. latex_color)
  end
  local option_string = ""
  if #options > 0 then
    option_string = "[" .. table.concat(options, ",") .. "]"
  end

  local pieces = {}
  local show_author = state.config.show_author and author and author.name and author.name ~= ""
  if show_author then
    table.insert(pieces, "\\textbf{" .. escape_latex(author.name) .. ":} ")
  end
  table.insert(pieces, escape_latex(comment.text))
  local content = table.concat(pieces)

  local todo = string.format("\\todo%s{%s}", option_string, content)
  if comment.inline then
    return pandoc.RawInline("tex", todo)
  else
    return pandoc.RawBlock("tex", todo)
  end
end

local function handle_comment(el, is_block)
  if not is_comment_node(el) then
    return nil
  end

  if not state.config.enabled then
    return pandoc.Null()
  end

  state.comments_seen = true

  local comment = get_comment_data(el)
  local author = resolve_author(comment)

  if is_html_format() then
    local html_color = resolve_html_color(comment, author)
    if comment.inline then
      return build_html_inline(comment, author, html_color)
    else
      return build_html_block(comment, author, html_color)
    end
  end

  if is_latex_format() then
    return build_latex(comment, author)
  end

  -- leave fallback content produced by shortcode
  return nil
end

function Div(el)
  return handle_comment(el, true)
end

function Span(el)
  return handle_comment(el, false)
end

local function ensure_latex_header(doc)
  if not state.latex.needed or not state.comments_seen then
    return
  end

  if not is_latex_format() then
    return
  end

  local header = {}
  table.insert(header, "\\usepackage{xcolor}")
  table.insert(header, "\\usepackage{todonotes}")
  table.insert(header, "\\input{comments.sty}")
  for _, line in ipairs(state.latex.header_lines) do
    table.insert(header, line)
  end

  local joined = table.concat(header, "\n")
  local includes = doc.meta["header-includes"]
  local new_entry = pandoc.MetaBlocks({ pandoc.RawBlock("tex", joined) })

  if not includes then
    doc.meta["header-includes"] = pandoc.MetaList({ new_entry })
    return
  end

  if includes.t == "MetaList" then
    table.insert(includes, new_entry)
    doc.meta["header-includes"] = includes
    return
  end

  doc.meta["header-includes"] = pandoc.MetaList({ includes, new_entry })
end

function Pandoc(doc)
  ensure_latex_header(doc)
  return doc
end
