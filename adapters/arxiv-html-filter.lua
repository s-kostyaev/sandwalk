local function has_class(element, expected)
  for _, class in ipairs(element.classes or {}) do
    if class == expected then
      return true
    end
  end
  return false
end

local function find_article(blocks)
  for _, block in ipairs(blocks) do
    if block.t == "Div" and has_class(block, "ltx_page_content") then
      return block.content
    end
  end
  for _, block in ipairs(blocks) do
    if block.t == "Div" then
      local nested = find_article(block.content)
      if nested then
        return nested
      end
    end
  end
  return nil
end

local function metadata_string(metadata, name)
  local value = metadata[name]
  if value == nil then
    return ""
  end
  return pandoc.utils.stringify(value)
end

local function absolute_target(target, origin, base_url)
  if target == "" or target:match("^#") or target:match("^[%a][%w+.-]*:") then
    return target
  end
  if target:match("^//") then
    return "https:" .. target
  end
  if target:match("^/") then
    return origin .. target
  end
  target = target:gsub("^%./", "")
  return base_url .. target
end

local function media_extension(mime)
  local extensions = {
    ["image/svg+xml"] = "svg",
    ["image/png"] = "png",
    ["image/jpeg"] = "jpg",
    ["image/gif"] = "gif",
    ["image/webp"] = "webp",
  }
  return extensions[mime] or "bin"
end

function Pandoc(document)
  local article = find_article(document.blocks)
  if article == nil then
    error("arXiv article container not found")
  end

  local origin = metadata_string(document.meta, "arxiv-origin")
  local base_url = metadata_string(document.meta, "arxiv-base-url")
  local filter = {}

  function filter.Link(link)
    link.target = absolute_target(link.target, origin, base_url)
    return link
  end

  function filter.Image(image)
    if image.src:match("^data:") then
      local mime, contents = pandoc.mediabag.fetch(image.src)
      local name =
        "images/"
        .. pandoc.utils.sha1(contents)
        .. "."
        .. media_extension(mime)
      pandoc.mediabag.insert(name, mime, contents)
      image.src = name
      return image
    else
      local caption = image.caption
      if caption == nil or #caption == 0 then
        caption = { pandoc.Str("Figure image") }
      end
      return pandoc.Link(
        caption,
        absolute_target(image.src, origin, base_url),
        image.title
      )
    end
  end

  local container = pandoc.walk_block(pandoc.Div(article), filter)
  document.blocks = container.content
  return document
end
