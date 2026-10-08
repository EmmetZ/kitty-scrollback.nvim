local assert = require('luassert')
local windows = require('kitty-scrollback.windows')

describe('scrollback position status window', function()
  local original_buf
  local original_columns
  local buf
  local win
  local options

  local function status_window()
    for _, id in ipairs(vim.api.nvim_list_wins()) do
      if
        vim.api.nvim_win_get_config(id).relative == 'editor'
        and not vim.api.nvim_win_get_config(id).focusable
      then
        return id
      end
    end
  end

  local function status_text()
    return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(status_window()), 0, -1, false)[1]
  end

  local function move(row, col)
    vim.api.nvim_win_set_cursor(win, { row, col or 0 })
    vim.api.nvim_exec_autocmds('CursorMoved', { buffer = buf })
  end

  before_each(function()
    original_buf = vim.api.nvim_get_current_buf()
    original_columns = vim.o.columns
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      'first',
      'second',
      '',
      'fourth',
      'fifth',
      'sixth',
      'seventh',
      'eighth',
      'ninth',
      'last',
    })
    vim.api.nvim_win_set_cursor(win, { 10, 0 })
    options = { status_window = { enabled = true, autoclose = false } }
    windows.setup({ bufid = buf, winid = win, orig_columns = original_columns }, options)
  end)

  after_each(function()
    for _, id in ipairs(vim.api.nvim_list_wins()) do
      if id ~= win then
        vim.api.nvim_win_close(id, true)
      end
    end
    vim.api.nvim_set_current_win(win)
    vim.api.nvim_set_current_buf(original_buf)
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
    vim.o.columns = original_columns
  end)

  it('counts backward from the bottom, including blank lines', function()
    windows.show_status_window()
    assert.are.equal('[1/10]', status_text())
    move(9)
    assert.are.equal('[2/10]', status_text())
    move(3)
    assert.are.equal('[8/10]', status_text())
    move(1)
    assert.are.equal('[10/10]', status_text())
  end)

  it('follows the focused split and retains its position in the paste window', function()
    windows.show_status_window()
    vim.cmd.vsplit()
    local split = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_cursor(split, { 6, 0 })
    vim.api.nvim_exec_autocmds('CursorMoved', { buffer = buf })
    assert.are.equal('[5/10]', status_text())

    local paste_buf = vim.api.nvim_create_buf(false, true)
    local paste_win = vim.api.nvim_open_win(paste_buf, true, {
      relative = 'editor',
      row = 2,
      col = 2,
      width = 10,
      height = 2,
    })
    vim.api.nvim_exec_autocmds('CursorMoved', { buffer = paste_buf })
    assert.are.equal('[5/10]', status_text())
    vim.api.nvim_win_close(paste_win, true)
    vim.api.nvim_buf_delete(paste_buf, { force = true })
    vim.api.nvim_set_current_win(win)
    assert.are.equal('[1/10]', status_text())
  end)

  it('stays aligned to the right when the text width or terminal width changes', function()
    windows.show_status_window()
    local id = status_window()
    local config = vim.api.nvim_win_get_config(id)
    assert.are.equal(vim.o.columns, config.col + config.width)
    move(1)
    config = vim.api.nvim_win_get_config(id)
    assert.are.equal(7, config.width)
    assert.are.equal(vim.o.columns, config.col + config.width)
    vim.o.columns = original_columns - 10
    vim.api.nvim_exec_autocmds('VimResized', {})
    config = vim.api.nvim_win_get_config(id)
    assert.are.equal(vim.o.columns, config.col + config.width)
  end)

  it('does not rewrite the counter when only the horizontal position changes', function()
    windows.show_status_window()
    local status_buf = vim.api.nvim_win_get_buf(status_window())
    local changedtick = vim.api.nvim_buf_get_changedtick(status_buf)
    move(10, 1)
    move(10, 2)
    assert.are.equal(changedtick, vim.api.nvim_buf_get_changedtick(status_buf))
  end)

  it('removes its event handlers when the status window closes', function()
    windows.show_status_window()
    vim.api.nvim_win_close(status_window(), true)
    assert.is_false(pcall(vim.api.nvim_get_autocmds, { group = 'KittyScrollBackNvimStatusWindow' }))
    assert.are.equal(0, #vim.fn.timer_info())
    move(1)
  end)

  it('closes the counter when the scrollback buffer is wiped', function()
    windows.show_status_window()
    local id = status_window()
    vim.api.nvim_buf_delete(buf, { force = true })
    assert.is_false(vim.api.nvim_win_is_valid(id))
  end)

  it('honors disabled and autoclose options', function()
    options.status_window.enabled = false
    windows.show_status_window()
    assert.is_nil(status_window())
    options.status_window.enabled = true
    options.status_window.autoclose = true
    windows.show_status_window()
    local id = status_window()
    assert.is_true(vim.wait(1500, function()
      return not vim.api.nvim_win_is_valid(id)
    end, 20))
  end)

  it('shows the ready counter immediately without an animation timer', function()
    windows.show_status_window()
    assert.are.equal('[1/10]', status_text())
    move(9)
    assert.are.equal('[2/10]', status_text())
    assert.are.equal(
      vim.fn.strdisplaywidth(status_text()),
      vim.api.nvim_win_get_config(status_window()).width
    )
    assert.are.equal(0, #vim.fn.timer_info())
  end)

  it('shows the same ready counter in simple mode', function()
    options.status_window.style_simple = true
    windows.show_status_window()
    assert.are.equal('[1/10]', status_text())
  end)
end)
