---@mod kitty-scrollback.windows
local ksb_footer_win = require('kitty-scrollback.footer_win')
local ksb_keymaps = require('kitty-scrollback.keymaps')
local ksb_util = require('kitty-scrollback.util')
local M = {}

---@type KsbPrivate
local p

---@type KsbOpts
local opts ---@diagnostic disable-line: unused-local

M.setup = function(private, options)
  p = private
  opts = options ---@diagnostic disable-line: unused-local
end

-- copied from https://github.com/folke/lazy.nvim/blob/dac844ed617dda4f9ec85eb88e9629ad2add5e05/lua/lazy/view/float.lua#L70
M.size = function(max, value)
  return value > 1 and math.min(value, max) or math.floor(max * value)
end

M.paste_winopts = function(row, col, height_offset)
  local target_height =
    math.floor(M.size(vim.o.lines, math.floor(M.size(vim.o.lines, (vim.o.lines + 2) / 3))))
  local line_height_diff = vim.o.lines - row - target_height - 5 -- TODO: magic number, 3 for footer and 2 for border
  if line_height_diff < 0 then
    target_height = target_height - math.abs(line_height_diff)
    if target_height <= 10 + 2 then -- TODO: magic number 2 for border
      target_height = M.size(vim.o.lines - 3, 10) -- TODO: magic number, 3 for footer
    end
    row = vim.o.lines - 5 - target_height -- TODO: magic number, 3 for footer and 2 for border
  end
  if vim.o.lines <= 5 then
    row = 0
    target_height = 1
  end
  local winopts = {
    relative = 'editor',
    zindex = 40,
    focusable = true,
    border = { '🭽', '▔', '🭾', '▕', '🭿', '▁', '🭼', '▏' },
    height = target_height + (height_offset or 0),
  }
  if row then
    winopts.row = row
  end
  if col then
    winopts.col = col
    winopts.width = M.size(vim.o.columns, vim.o.columns - col)
    if winopts.width <= 0 then
      -- No room to the right of the cursor; put the window below the current line.
      vim.fn.setcursorcharpos({ vim.fn.line('.'), 0 })
      ksb_util.restore_and_redraw()
      winopts.width = vim.o.columns - 1
      winopts.col = 0
    end
  end

  local winopts_overrides = opts.paste_window.winopts_overrides
  if winopts_overrides and type(winopts_overrides) == 'function' then
    winopts =
      vim.tbl_deep_extend('force', winopts, opts.paste_window.winopts_overrides(winopts) or {})
  elseif type(winopts_overrides) == 'table' then
    winopts = vim.tbl_deep_extend('force', winopts, winopts_overrides)
  end

  return winopts
end

M.open_paste_window = function(start_insert)
  vim.cmd.stopinsert()

  if ksb_util.command_line_editing_mode then
    p.pos = nil
  end

  if not p.pos then
    if
      (opts.kitty_get_text.extent == 'screen' or opts.kitty_get_text.extent == 'all')
      and not ksb_util.command_line_editing_mode
    then
      vim.notify(
        'kitty-scrollback.nvim: missing position with extent=' .. opts.kitty_get_text.extent,
        vim.log.levels.WARN,
        {}
      )
    end
    local last_nonempty_line = vim.fn.search('.', 'nb')
    p.pos = {
      cursor_line = last_nonempty_line + 3, -- TODO: magic number footer
      buf_last_line = vim.fn.line('$'),
      win_first_line = vim.fn.line('w0'),
      win_last_line = vim.fn.line('w$'),
      col = 0,
    }
  end

  local lnum = p.pos.cursor_line - p.pos.win_first_line - 1
  local col = p.pos.col + 1

  -- TermEnter may position cursor at the end of file with extra blank lines
  -- Adjust cursor to hide blank lines and move cursor to initial position set by set_cursor_position
  vim.fn.cursor(p.pos.win_first_line, 1)
  vim.cmd.redraw()
  vim.fn.cursor(p.pos.cursor_line, col)

  if not p.paste_bufid then
    p.paste_bufid = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_name(p.paste_bufid, vim.fn.tempname() .. '.ksb_pastebuf')
    local ft = opts.paste_window.filetype or vim.fn.fnamemodify(p.kitty_data.shell, ':t:r')
    vim.api.nvim_set_option_value('filetype', ft, { buf = p.paste_bufid })
    vim.api.nvim_set_option_value('swapfile', false, { buf = p.paste_bufid })
    ksb_keymaps.set_buffer_local_keymaps(p.paste_bufid)
  end
  if not p.paste_winid or vim.fn.win_id2win(p.paste_winid) == 0 then
    local winopts = M.paste_winopts(lnum + ksb_util.line_offset(), col)
    p.paste_winid = vim.api.nvim_open_win(p.paste_bufid, true, winopts)
    vim.api.nvim_set_option_value('scrolloff', 2, {
      win = p.paste_winid,
    })

    if not opts.paste_window.hide_footer then
      vim.schedule_wrap(ksb_footer_win.open_footer_window)(winopts)
    end

    vim.api.nvim_set_option_value(
      'winhighlight',
      'Normal:KittyScrollbackNvimPasteWinNormal,FloatBorder:KittyScrollbackNvimPasteWinFloatBorder,FloatTitle:KittyScrollbackNvimPasteWinFloatTitle',
      { win = p.paste_winid, scope = 'local' }
    )
    vim.api.nvim_set_option_value('winblend', opts.paste_window.winblend or 0, {
      win = p.paste_winid,
    })
  end
  if start_insert then
    vim.schedule(function()
      ---@diagnostic disable-next-line: param-type-mismatch
      vim.fn.cursor(vim.fn.line('$', p.paste_winid), 1)
      vim.cmd.startinsert({ bang = true })
    end)
  end
  ksb_util.restore_and_redraw()
  vim.schedule_wrap(vim.cmd.doautocmd)('WinResized')
end

M.show_status_window = function()
  if not opts.status_window.enabled then
    return
  end

  local popup_bufid = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = popup_bufid })
  local popup_winid = vim.api.nvim_open_win(popup_bufid, false, {
    relative = 'editor',
    zindex = 39,
    style = 'minimal',
    focusable = false,
    width = 1,
    height = 1,
    row = 0,
    col = vim.o.columns - 1,
    border = 'none',
    noautocmd = true,
  })
  vim.api.nvim_set_option_value(
    'winhighlight',
    'NormalFloat:KittyScrollbackNvimStatusWinNormal',
    { win = popup_winid, scope = 'local' }
  )

  local group = vim.api.nvim_create_augroup('KittyScrollBackNvimStatusWindow', { clear = true })
  local scrollback_winid = assert(p.winid)
  local previous_text
  local previous_columns

  local function update()
    if
      not vim.api.nvim_win_is_valid(popup_winid)
      or not vim.api.nvim_buf_is_valid(p.bufid)
      or not vim.api.nvim_win_is_valid(scrollback_winid)
      or vim.api.nvim_win_get_buf(scrollback_winid) ~= p.bufid
    then
      return
    end

    local total = vim.api.nvim_buf_line_count(p.bufid)
    local row = vim.api.nvim_win_get_cursor(scrollback_winid)[1]
    local text = ('[%d/%d]'):format(total - row + 1, total)
    local columns = vim.o.columns
    if text == previous_text and columns == previous_columns then
      return
    end

    local width = math.min(#text, columns)
    vim.api.nvim_win_set_config(popup_winid, {
      relative = 'editor',
      row = 0,
      col = columns - width,
      width = width,
    })
    if text ~= previous_text then
      vim.api.nvim_buf_set_lines(popup_bufid, 0, -1, false, { text })
    end
    previous_text = text
    previous_columns = columns
  end

  local function close()
    if vim.api.nvim_win_is_valid(popup_winid) then
      vim.api.nvim_win_close(popup_winid, true)
    end
  end

  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI', 'BufEnter', 'WinEnter' }, {
    group = group,
    buffer = p.bufid,
    callback = function()
      -- Follow the focused scrollback split, retaining its position while pasting.
      scrollback_winid = vim.api.nvim_get_current_win()
      update()
    end,
  })
  vim.api.nvim_create_autocmd('VimResized', {
    group = group,
    callback = function()
      p.orig_columns = vim.o.columns
      update()
    end,
  })
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = group,
    buffer = p.bufid,
    callback = close,
  })
  vim.api.nvim_create_autocmd('WinClosed', {
    group = group,
    pattern = tostring(popup_winid),
    callback = function()
      vim.api.nvim_del_augroup_by_id(group)
    end,
  })

  update()
  if opts.status_window.autoclose then
    vim.defer_fn(close, 1000)
  end
end

return M
