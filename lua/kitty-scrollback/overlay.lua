---@mod kitty-scrollback.overlay
local M = { shown = false }

---Reveal the prepared overlay after its first frame has been written.
M.show = function()
  if M.shown or vim.env.KITTY_SCROLLBACK_NVIM_SMOOTH_START ~= 'true' then
    return
  end
  vim.cmd('redraw!')
  local ready = '\27P@kitty-overlay-ready|\27\\'
  if vim.api.nvim_ui_send then
    vim.api.nvim_ui_send(ready)
  else
    assert(io.stdout:write(ready))
    assert(io.stdout:flush())
  end
  M.shown = true
end

return M
