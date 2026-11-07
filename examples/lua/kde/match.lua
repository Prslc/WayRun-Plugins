-- Scoring for KDE settings modules.
--
-- Label hits decide the order. Description, module-id and keyword hits add a
-- smaller amount so that two modules with similar names are still ordered by
-- what they do ("kcm_kwinrules" for window rules).

local util = wayrun.import("kde/util")

local match = {}

local function text_score(text, query, exact, prefix, includes)
  if not text or text == "" then
    return 0
  end
  if text == query then
    return exact
  end
  if text:sub(1, #query) == query then
    return prefix
  end
  if text:find(query, 1, true) then
    return includes
  end
  return 0
end

local function words(text)
  local out = {}
  for word in (text or ""):gmatch("[^%s]+") do
    out[#out + 1] = util.lower(word)
  end
  return out
end

local function entry_score(module, word, describe, search_alt)
  local label = math.max(
    text_score(module.name_lc, word, 1000, 700, 400),
    text_score(module.name_en_lc, word, 1000, 700, 400),
    text_score(module.name_session_lc, word, 1000, 700, 400)
  )
  if search_alt then
    for _, name in ipairs(module.alt_names_lc) do
      label = math.max(label, text_score(name, word, 400, 280, 160))
    end
  end

  local other = math.max(
    text_score(util.lower(describe(module.id)), word, 300, 200, 100),
    text_score(util.lower(module.id), word, 250, 150, 60)
  )
  for _, keyword in ipairs(module.keywords) do
    other = math.max(other, text_score(keyword, word, 250, 150, 60))
  end

  if label == 0 and other == 0 then
    return 0
  end
  return label + other
end

local function scored(module, query, describe, search_alt)
  local total = 0
  for _, word in ipairs(words(query)) do
    local score = entry_score(module, word, describe, search_alt)
    if score == 0 then
      return nil
    end
    total = total + score
  end

  -- A label that contains the whole phrase beats one that merely contains
  -- each word in a different field.
  total = total + math.max(
    text_score(module.name_lc, query, 2000, 1500, 800),
    text_score(module.name_en_lc, query, 2000, 1500, 800),
    text_score(module.name_session_lc, query, 2000, 1500, 800)
  )
  if module.name_lc == query or module.name_en_lc == query then
    total = total + 500
  end
  return total
end

-- Returns { module, score } hits, best first.
function match.rank(list, query, describe, search_alt)
  local hits = {}
  for _, module in ipairs(list) do
    local score = scored(module, query, describe, search_alt)
    if score then
      hits[#hits + 1] = { module = module, score = score }
    end
  end

  table.sort(hits, function(a, b)
    if a.score ~= b.score then
      return a.score > b.score
    end
    return #a.module.name_en < #b.module.name_en
  end)
  return hits
end

return match
