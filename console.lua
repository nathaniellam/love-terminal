local utf8 = require('utf8')

local console = {}

function console.new(...)
  local instance = setmetatable({}, {__index = console})
  console._init(instance, ...)
  return instance
end

function console:_init(width, height)
  self.cursor = '_'
  self.scroll_y = 0
  self.max_scroll_height = 0
  self.width = width
  self.height = height
  self.font = love.graphics.newFont()
  self.config = {
    output_max_lines = 2000,
    scroll_speed_y = 10
  }

  self._canvas = love.graphics.newCanvas(width, height)
  self._output_buffer = {}
  self._pre_input_buffer = {}
  self._post_input_buffer = {}
  self._gap_buffer = {}
end

function console:processText(text)
  if text then
    local f, err = loadstring('return ' .. text)
    if not f then
      -- If there is a syntax error when trying to append 'return' to chunk,
      -- try again with just the input.
      f, err = loadstring(text)
    end

    if f then
      -- Execute the chunk in the current context and safely.
      f = setfenv(f, self:getContext())
      local results = {pcall(f)}
      local status = results[1]
      local retvals = select(2, unpack(results))
      if status then
        self._print(text)
        self._print(unpack(retvals))
      else
        -- There was an error and the message is the first retval.
        self._print(retvals[1])
      end
    else
      self:_print(err)
    end
  end
end

function console:_draw_console()
  love.graphics.push()
  love.graphics.setCanvas(self._canvas)
  love.graphics.clear()
  love.graphics.translate(0, -self.scroll_y)

  -- Draw output
  love.graphics.printf(self._output_buffer, 0, 0, self.width)

  -- Draw current input
  local cursor_x, cursor_y = self:_draw_buffer(self._pre_input_buffer)
  self:_draw_cursor(cursor_x, cursor_y)
  local _, total_height = self:_draw_buffer(self._post_input_buffer, cursor_x, cursor_y)
  self.max_scroll_height = math.max(0, total_height - self.height)

  love.graphics.setCanvas()
  love.graphics.pop()
end

function console:draw()
  love.graphics.draw(self._canvas)
end

function console:textinput(ch)
  self:insert(ch)
end

--[[
Input Functions
--]]
function console:insert(text)
  local n, bad_pos = utf8.len(text)
  if n then
    for _, c in utf8.codes(text) do
      table.insert(self._pre_input_buffer, utf8.char(c))
    end
    self:_normalize_input()
  end
  self:_draw_console()
end

function console:move_cursor(n)
  if n > 0 then
    for _ = 1, n do
      if #self._pre_input_buffer > 0 then
        table.insert(self._post_input_buffer, 1, table.remove(self._pre_input_buffer))
      end
    end
  elseif n < 0 then
    for _ = -1, n, -1 do
      if #self._post_input_buffer > 0 then
        table.insert(self._pre_input_buffer, table.remove(self._post_input_buffer, 1))
      end
    end
  end
  self:_draw_console()
end

function console:process()
end

-- Select a range of text from any given buffer (output or input).
function console:select()
end

function console:scroll(ds)
  self.scroll_y =
    math.min(self.max_scroll_height, math.max(0, self.scroll_y + self.config.scroll_speed_y * ds))
  self:_draw_console()
end

function console:toggle_table()
end

function console:copy()
end

function console:paste()
end

--[[
Internal Functions
--]]
function console:_print(...)
  local nargs = select('#', ...)
  local output = ''
  if nargs > 0 then
    for _, v in pairs({...}) do
      output = output .. tostring(v) .. '\t'
    end
  end
  output = output .. '\n'
  table.insert(self._output_buffer, output)

  if #self._output_buffer > self.config.output_max_lines then
    table.remove(self._output_buffer, 1)
  end
end

function console:_draw_buffer(buffer, offset_x, offset_y)
  -- An empty buffer prints nothing and just returns the offsets given.
  -- This is so other code can treat all the draw calls the same.
  if #buffer == 0 then
    return offset_x, offset_y
  end

  offset_x = offset_x or 0
  offset_y = offset_y or 0
  local full_width = self.font:getWidth(table.concat(buffer)) + offset_x
  if full_width <= self.width then
    -- When the buffer is shorter than or equal to the width, we can just draw
    -- it.
    love.graphics.print(buffer, offset_x, offset_y)
    print(full_width)
    return full_width, offset_y
  else
    -- When the buffer is longer than the width, we have to draw line by line.
    local start_idx = 1
    local n = #buffer
    local end_idx = n
    local line_num = 0
    local last_width = 0

    while start_idx <= n do
      -- Find maximum line length that does not exceed console width.
      -- We do a binary search for the index that maximizes the width without
      -- going over the console width.
      local left = start_idx
      local right = n
      local iterations = 0
      while left <= right do
        iterations = iterations + 1
        local mid = math.floor((left + right) / 2)
        local current_width =
          self.font:getWidth(table.concat(buffer, '', start_idx, mid)) + offset_x
        if current_width < self.width then
          left = mid + 1
          end_idx = mid
          last_width = current_width
        elseif current_width > self.width then
          right = mid - 1
          last_width = current_width
        else
          end_idx = mid
          last_width = current_width
          break
        end
      end

      if last_width > self.width then
        last_width = last_width - offset_x
        line_num = line_num + 1
        offset_x = 0
      end

      love.graphics.print(
        table.concat(buffer, '', start_idx, end_idx),
        offset_x,
        offset_y + line_num * self.font:getLineHeight() * self.font:getHeight()
      )
      start_idx = end_idx + 1
      line_num = line_num + 1
      offset_x = 0
    end
    return last_width, offset_y + (line_num - 1) * self.font:getLineHeight() * self.font:getHeight()
  end
end

function console:_draw_cursor(cursor_x, cursor_y)
  if type(self.cursor) == 'string' then
    love.graphics.print(self.cursor, cursor_x, cursor_y)
  elseif self.cursor.typeOf and self.cursor:typeOf('Drawable') then
    love.graphics.draw(self.cursor, cursor_x, cursor_y)
  end
end

function console:_normalize_input()
end

return console
