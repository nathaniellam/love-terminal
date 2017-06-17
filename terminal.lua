local utf8 = require("utf8")

-- Basic Class Implementation

local function call(t, ...)
  return t.new(...)
end

local class_mt = { __call = call }

local function class(name)
  local new_class = { __class = name }
  new_class.__index = new_class
  setmetatable(new_class, class_mt)

  function new_class.new(...)
    local inst = setmetatable({}, new_class)
    if inst.initialize then
      inst:initialize(...)
    end
    return inst
  end

  function new_class.is_class(inst)
    return inst.__class == new_class.inst
  end

  return new_class
end

-- TextBuffer Class

local TextBuffer = class("TextBuffer")

TextBuffer.DEFAULT_REPLACEMENT = "�"

-- TextBuffer Internal API

-- Returns width of row from start to col.
function TextBuffer:_textPos(row, col)
  return self._font:getWidth(table.concat(self.lines[row], '', 1, col or #self.lines[row]))
end

-- Expand number of lines due to overflow.
function TextBuffer:_expand(start)
  local lineCount = #self.lines
  local i = start or 1
  while i <= lineCount do
    local cur = self.lines[i]
    local next = self.lines[i + 1] or {}

    if self._font:getWidth(table.concat(cur)) > self._maxWidth then
      while #cur > 0 and self._font:getWidth(table.concat(cur)) > self._maxWidth do
        table.insert(next, 1, table.remove(cur))
      end

      if i + 1 > lineCount then
        table.insert(self.lines, next)
        lineCount = lineCount + 1
      end
    else
      return
    end

    i = i + 1
  end
end

local function eat(a, b, font, width)
  if not a or not b then
    return false
  end

  local once = false
  while font:getWidth(table.concat(a)) < width do
    if #b == 0 then
      return true
    end
    table.insert(a, table.remove(b, 1))
    once = true
  end

  if once then
    table.insert(b, 1, table.remove(a))
  end
  return false
end

-- Shrink number of lines due to underflow.
function TextBuffer:_shrink(start)
  local lineCount = #self.lines
  local curi = start or 1
  while curi <= lineCount - 1 do
    local cur = self.lines[curi]
    local nexti = curi + 1
    local next = self.lines[nexti]

    while eat(cur, next, self._font, self._maxWidth) do
      nexti = nexti + 1
      next = self.lines[nexti]
    end

    curi = curi + 1
  end

  -- Remove empty lines.
  for i = #self.lines, 1, -1 do
    if #self.lines[i] == 0 then
      table.remove(self.lines, i)
    end
  end
end

-- TextBuffer Public API

function TextBuffer:initialize(font, width)
  self.lines = { {} }
  self.length = 0

  self._font = font or love.graphics.getFont()
  self._maxWidth = width or love.graphics.getWidth()
end

function TextBuffer:getFont()
  return self._font
end

function TextBuffer:setFont(font)
  if self._font ~= font then
    self._font = font
    self._expand()
    self._shrink()
  end
end

function TextBuffer:getMaxWidth()
  return self._maxWidth
end

function TextBuffer:setMaxWidth(width)
  if self._maxWidth ~= width then
    local oldWidth = self._maxWidth
    self._maxWidth = width
    if width < oldWidth then
      self:_expand()
    else
      self:_shrink()
    end
  end
end

function TextBuffer:getHeight()
  local height = self._font:getHeight() * self._font:getLineHeight()
  return self.length > 0 and #self.lines * height or 0
end

function TextBuffer:colrow(i)
  local col = i <= 0 and 1 or i
  for row, line in ipairs(self.lines) do
    col = col - #line
    if col < 1 then
      return col + #line, row
    end
  end

  return #self.lines[#self.lines] + 1, #self.lines
end

function TextBuffer:insert(str, i, replacement)
  i = i or self.length + 1
  replacement = replacement or self.DEFAULT_REPLACEMENT
  local col, row = self:colrow(i)

  local errs = {}
  local j = 1
  while j <= #str do
    local len, err = utf8.len(str, j)
    if not len then
      table.insert(errs, err)
      j = err + 1
    else
      break
    end
  end

  local k = 1
  for _, err in ipairs(errs) do
    for _, cp in utf8.codes(str, k, err - 1) do
      table.insert(self.lines[row], col, utf8.char(cp))
      self.length = self.length + 1
      col = col + 1
    end

    table.insert(self.lines[row], col, replacement)
    self.length = self.length + 1
    col = col + 1
    k = err + 1
  end

  for _, cp in utf8.codes(str, k) do
    table.insert(self.lines[row], col, utf8.char(cp))
    self.length = self.length + 1
    col = col + 1
  end

  self:_expand(row)
end

function TextBuffer:remove(i, j)
  if i > self.length or i <= 0 then
    return
  end

  j = j or i

  if j < i then
    i, j = j, i
  end

  local scol, srow = self:colrow(i)
  local ecol, erow = self:colrow(j)
  -- Handle removing characters from single line.
  if srow == erow then
    for col = ecol, scol, -1 do
      table.remove(self.lines[srow], col)
    end
  -- Handle removing characters from multiple lines.
  else
    for col = #self.lines[srow], scol, -1 do
      table.remove(self.lines[srow], col)
      self.length = self.length - 1
    end

    for col = ecol, 1, -1 do
      table.remove(self.lines[erow], col)
      self.length = self.length - 1
    end

    for row = erow - 1, srow + 1, -1 do
      self.length = self.length - #self.lines[row]
      table.remove(self.lines, row)
    end
  end

  self:_shrink(srow)
end

-- NOTE This does not normalize the mouse coordinates.
function TextBuffer:mouseToIdx(x, y)
  local height = self._font:getHeight() * self._font:getLineHeight()

  local i = 1
  for row, line in ipairs(self.lines) do
    if (y < row * height and y >= (row - 1) * height) or row == #self.lines or y < 0 then
      if x < 0 then
        return i - 1
      end

      for col = 1, #line - 1 do
        if x >= self:_textPos(row, col - 1) and x < self:_textPos(row, col) then
          return i
        end
        i = i + 1
      end

      return i
    else
      i = i + #line
    end
  end

  return self.length
end

function TextBuffer:draw(x, y, cursor, cursorIdx, selectStart, selectEnd)
  love.graphics.push()
  love.graphics.translate(x or 0, y or 0)
  local width = self._maxWidth
  local font = self._font

  local height = font:getHeight() * font:getLineHeight()
  local oldFont
  if font ~= love.graphics.getFont() then
    oldFont = love.graphics.getFont()
    love.graphics.setFont(self.font)
  end

  for ly, line in ipairs(self.lines) do
    love.graphics.print(line, 0, (ly - 1) * height)
  end

  -- Draw selection box.
  if selectStart and selectEnd then
    if selectStart > selectEnd then
      selectStart, selectEnd = selectEnd, selectStart
    end

    local scol, srow = self:colrow(selectStart)
    local ecol, erow = self:colrow(selectEnd)

    local sx = self:_textPos(srow, scol - 1)
    local ex = self:_textPos(erow, ecol)

    local y1 = (srow - 1) * height
    local y2 = srow * height

    -- Handle selection on single line.
    if srow == erow then
      love.graphics.line(
        sx, y2,
        sx, y1,
        ex, y1,
        ex, y2,
        sx, y2
      )
    -- Handle selection on multiple lines.
    else
      local mx1 = 0
      local mx2 = width

      local y3 = (erow - 1) * height
      local y4 = erow * height

      -- Handle two line (no overlap) selection.
      if erow - srow == 1 and ex < sx then
        love.graphics.line(
          sx, y2,
          sx, y1,
          mx2, y1,
          mx2, y2,
          sx, y2
        )

        love.graphics.line(
          ex, y3,
          ex, y4,
          mx1, y4,
          mx1, y3,
          ex, y3
        )
      -- Handle rectangle selection.
      elseif mx1 == sx and mx2 == ex then
        love.graphics.line(
          sx, y1,
          ex, y1,
          ex, y4,
          sx, y4,
          sx, y1
        )
      -- Handle L-shape (bottom) selection.
      elseif mx1 == sx then
        love.graphics.line(
          sx, y1,
          mx2, y1,
          mx2, y3,
          ex, y3,
          ex, y4,
          sx, y4,
          sx, y1
        )
      -- Handle L-shape (top) selection.
      elseif mx2 == ex then
        love.graphics.line(
          sx, y2,
          sx, y1,
          ex, y1,
          ex, y4,
          mx1, y4,
          mx1, y2,
          sx, y2
        )
      -- Handle N-shape selection.
      else
        love.graphics.line(
          sx, y2,
          sx, y1,
          mx2, y1,
          mx2, y3,
          ex, y3,
          ex, y4,
          mx1, y4,
          mx1, y2,
          sx, y2
        )
      end
    end
  -- Draw cursor.
  elseif cursor and cursorIdx then
    local lx, ly = self:colrow(cursorIdx)
    love.graphics.print(cursor, self:_textPos(ly, lx - 1), (ly - 1) * height)
  end

  if oldFont then
    love.graphics.setFont(oldFont)
  end

  love.graphics.pop()
end

-- Terminal Class

local Terminal = class("Terminal")

Terminal.TextBuffer = TextBuffer

-- Terminal Public API

function Terminal:initialize(font, width, height)
  self.font = font or love.graphics.getFont()
  self.width = width or love.graphics.getWidth()
  self.height = height or love.graphics.getHeight()
  self.x = 0
  self.y = 0
  self.backgroundColor = {0, 0, 0, 0}

  self.inputBuffer = self.TextBuffer(self.font, self.width)
  self.outputBuffer = self.TextBuffer(self.font, self.width)
end

function Terminal:draw()
  love.graphics.push('all')
  love.graphics.setFont(self.font)
  love.graphics.setBackgroundColor(self.backgroundColor)

  self.outputBuffer:draw()
  love.graphics.translate(0, self.outputBuffer:getHeight())
  self.inputBuffer:draw()

  love.graphics.pop()
end

return Terminal
