local console = require('console')

local dev_console

function love.load()
  dev_console = console.new(200, 200)
end

function love.draw()
  dev_console:draw()
  love.graphics.rectangle('line', 0, 0, 200, 200)
end

function love.textinput(t)
  dev_console:textinput(t)
end

function love.keypressed(scancode)
  if scancode == 'left' then
    dev_console:move_cursor(1)
  elseif scancode == 'right' then
    dev_console:move_cursor(-1)
  end
end