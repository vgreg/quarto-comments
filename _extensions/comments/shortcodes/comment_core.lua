local utils = {}

local VALID_TYPES = {
  comment = true,
  todo = true,
  note = true,
  question = true,
}

local function sanitize_class(value)
  local cleaned = tostring(value or "")
  cleaned = cleaned:gsub("%s+", "-")
  cleaned = cleaned:gsub("[^%w%-_]", "")
  if cleaned == "" then
    return nil
  end
  return cleaned
end

local function parse_bool(value)
  if value == nil then
    return false
  end
  if type(value) == "boolean" then
    return value
  end
  local lowered = tostring(value):lower()
  return lowered == "true" or lowered == "1" or lowered == "yes" or lowered == "y"
end

local function trim(value)
  local stripped = value:gsub("^%s+", "")
  stripped = stripped:gsub("%s+$", "")
  return stripped
end

local function extract_text(args, kwargs)
  if args ~= nil and #args > 0 then
    local first = args[1]
    if type(first) == "string" then
      return first
    elseif type(first) == "table" then
      return pandoc.utils.stringify(first)
    end
  end
  if kwargs ~= nil and kwargs.text ~= nil then
    local value = kwargs.text
    if type(value) == "string" then
      return value
    elseif type(value) == "table" then
      return pandoc.utils.stringify(value)
    end
  end
  return ""
end

local function build_attr(comment_type, author_id, inline, text)
  local classes = { "quarto-comment", "comment-" .. comment_type }
  local attributes = {
    ["data-comment-type"] = comment_type,
    ["data-comment-text"] = text,
    ["data-comment-inline"] = inline and "true" or "false",
  }

  if author_id and author_id ~= "" then
    attributes["data-comment-author"] = author_id
    local class_safe = sanitize_class(author_id)
    if class_safe then
      table.insert(classes, "comment-author-" .. class_safe)
    end
  end

  return pandoc.Attr("", classes, attributes)
end

local function fallback_label(comment_type, author_id)
  local label = comment_type:gsub("^%l", string.upper)
  if comment_type == "todo" then
    label = "TODO"
  elseif comment_type == "note" then
    label = "Note"
  elseif comment_type == "question" then
    label = "Question"
  end
  if author_id and author_id ~= "" then
    label = label .. " (" .. author_id .. ")"
  end
  return label
end

local function build_fallback(comment_type, author_id, text)
  local label = fallback_label(comment_type, author_id)
  local inline_content = pandoc.List()
  inline_content:extend({
    pandoc.Str(label .. ": "),
    pandoc.Str(text),
  })
  return inline_content
end

function utils.render(args, kwargs, meta, forced_type)
  kwargs = kwargs or {}
  local comment_text = extract_text(args, kwargs)
  comment_text = trim(comment_text or "")

  if comment_text == "" then
    return pandoc.Null()
  end

  local comment_type = forced_type or kwargs.type or "comment"
  comment_type = tostring(comment_type):lower()
  if not VALID_TYPES[comment_type] then
    comment_type = "comment"
  end

  local author_id = kwargs.author and tostring(kwargs.author) or nil
  local inline = parse_bool(kwargs.inline)

  local attr = build_attr(comment_type, author_id, inline, comment_text)
  local fallback = build_fallback(comment_type, author_id, comment_text)

  if inline then
    return pandoc.Span(fallback, attr)
  else
    local paragraph = pandoc.Para(fallback)
    return pandoc.Div({ paragraph }, attr)
  end
end

return utils.render
