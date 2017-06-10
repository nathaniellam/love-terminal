--[[
Utility Functions
--]]

--[[
Basic Class Implementation
--]]

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

--[[
TextBuffer Class
--]]

local TextBuffer = class("TextBuffer")

function TextBuffer:initialize()
  self.lines = { {} }
  self.length = 0
  self.charPos = {}
  self._prevFont = nil
  self._prevWidth = nil
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

function TextBuffer:_refresh(width, font)
  local lineCount = #self.lines
  local i = 1
  while i <= lineCount do
    local cur = self.lines[i]
    local next = self.lines[i + 1] or {}

    -- Handle expanding case.
    if font:getWidth(table.concat(cur)) > width then
      while #cur > 0 and font:getWidth(table.concat(cur)) > width do
        table.insert(next, 1, table.remove(cur))
      end

      if i + 1 > lineCount then
        table.insert(self.lines, next)
        lineCount = lineCount + 1
      end
    -- Handle shrinking case.
    elseif i ~= lineCount and font:getWidth(table.concat(cur)) < width then
      local lastJ = 0
      for j = 1, #next do
        table.insert(cur, next[j])
        if font:getWidth(table.concat(cur)) > width then
          lastJ = j - 1
          table.remove(cur)
          break
        end
      end

      -- Remove characters that were copied.
      if lastJ > 0 then
        for j = lastJ, 1, -1 do
          table.remove(next, j)
        end

        if #next == 0 then
          table.remove(self.lines, i)
        end
      end
    end

    i = i + 1
  end

  -- Re-assign character positions.
  local c = 0
  local cp = {}
  for _, line in ipairs(self.lines) do
    for j = 1, #line do
      c = c + 1
      cp[c] = font:getWidth(table.concat(line, '', 1, j - 1))
    end
  end
  self.charPos = cp
end

function TextBuffer:insert(ch, i)
  i = i or self.length + 1
  local col, row = self:colrow(i)
  table.insert(self.lines[row], col, ch)
  self.length = self.length + 1
  -- self:expand(row)
  self._dirty = true
end

function TextBuffer:remove(i)
  if i > self.length or i <= 0 then
    return
  end

  local col, row = self:colrow(i)
  table.remove(self.lines[row], col)
  self.length = self.length - 1
  -- self:shrink(row)
  self._dirty = true
end

function TextBuffer:mouseToIdx(x, y)
  if x <= 0 and y <= 0 then
    return 1
  end

  local height = self._prevFont:getHeight() * self._prevFont:getLineHeight()
  local i = 1
  for row, line in ipairs(self.lines) do
    if y < row * height and y >= (row - 1) * height then
      for _ = 1, #line - 1 do
        if x >= self.charPos[i] and x < self.charPos[i + 1] then
          return i
        end
        i = i + 1
      end
    else
      i = i + #line
    end
  end

  return self.length
end

function TextBuffer:draw(x, y, width, font, cursor, cursorIdx, selectStart, selectEnd)
  local offX = x or 0
  local offY = y or 0
  width = width or love.graphics.getWidth()
  font = font or love.graphics.getFont()
  if width ~= self._prevWidth or font ~= self._prevFont or self._dirty then
    self:_refresh(width, font)
    self._prevWidth = width
    self._prevFont = font
    self._dirty = false
  end

  local height = font:getHeight() * font:getLineHeight()
  local oldFont
  if font ~= love.graphics.getFont() then
    oldFont = love.graphics.getFont()
    love.graphics.setFont(self.font)
  end

  for ly, line in ipairs(self.lines) do
    love.graphics.print(line, offX, (ly - 1) * height + offY)
  end

  -- Draw cursor
  if cursor and cursorIdx then
    local _, ly = self:colrow(cursorIdx)
    love.graphics.print(cursor, self.charPos[cursorIdx] + offX, (ly - 1) * height + offY)
  end

  -- Draw selection box.
  if selectStart and selectEnd then
    if selectStart > selectEnd then
      selectStart, selectEnd = selectEnd, selectStart
    end

    local _, srow = self:colrow(selectStart)
    local _, erow = self:colrow(selectEnd)

    local sx = self.charPos[selectStart]
    local ex = self.charPos[selectEnd]

    local y1 = (srow - 1) * height + offY
    local y2 = srow * height + offY

    -- Handle selection on single line.
    if srow == erow then
      local x1 = sx + offX
      local x2 = ex + offX

      love.graphics.line(
        x1, y2,
        x1, y1,
        x2, y1,
        x2, y2,
        x1, y2 -- wrap
      )
    -- Handle selection on multiple lines.
    else
      local mx1 = offX
      local mx2 = width + offX

      local y3 = (erow - 1) * height + offY
      local y4 = erow * height + offY

      -- Handle selection on two lines with no overlap.
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
  end

  if oldFont then
    love.graphics.setFont(oldFont)
  end
end

--[[
Terminal Class
--]]

local Terminal = class("Terminal")

Terminal.TextBuffer = TextBuffer

function Terminal:initialize(font)
  self.font = font or love.graphics.getFont()
end

return Terminal
