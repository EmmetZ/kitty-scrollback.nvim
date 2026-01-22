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
    if target_height <= 10 + 2 then               -- TODO: magic number 2 for border
      target_height = M.size(vim.o.lines - 3, 10) -- TODO: magic number, 3 for footer
    end
    row = vim.o.lines - 5 - target_height         -- TODO: magic number, 3 for footer and 2 for border
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
    if winopts.width < 0 then
      -- current line is larger than window, put window below current line
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
  if opts.status_window.enabled then
    local show_line_numbers = true
    if opts.status_window.show_line_numbers ~= nil then
      show_line_numbers = opts.status_window.show_line_numbers
    end

    local show_icons = true
    if opts.status_window.show_icons ~= nil then
      show_icons = opts.status_window.show_icons
    end

    -- get current window and buffer (calculate line numbers)
    local target_win = vim.api.nvim_get_current_win()
    local target_buf = vim.api.nvim_win_get_buf(target_win)

    local kitty_icon = opts.status_window.icons.kitty
    local love_icon = opts.status_window.icons.heart
    local nvim_icon = opts.status_window.icons.nvim

    if opts.status_window.style_simple then
      kitty_icon = 'kitty-scrollback.nvim'
      love_icon = ''
      nvim_icon = ''
    end

    -- build icon group string in advance
    -- if show_icons=false, then it's an empty string
    local icon_group_str = ""
    if show_icons then
      icon_group_str = kitty_icon .. ' ' .. love_icon .. ' ' .. nvim_icon .. ' '
    end

    local popup_bufid = vim.api.nvim_create_buf(false, true)

    local winopts = function(display_width)
      return {
        relative = 'editor',
        zindex = 39,
        style = 'minimal',
        focusable = false,
        width = M.size(p.orig_columns or vim.o.columns, display_width),
        height = 1,
        row = 0,
        col = vim.o.columns,
        border = 'none',
      }
    end

    vim.api.nvim_set_option_value('swapfile', false, { buf = popup_bufid })

    local popup_winid = vim.api.nvim_open_win(
      popup_bufid,
      false,
      vim.tbl_deep_extend('force', winopts(10), { noautocmd = true })
    )
    vim.api.nvim_set_option_value('winhighlight', 'NormalFloat:KittyScrollbackNvimStatusWinNormal',
      { win = popup_winid, scope = 'local' })

    -- render status function
    local function render_status(is_loading, spinner_char)
      if not vim.api.nvim_win_is_valid(popup_winid) then return false end

      -- get line number text
      local line_text = ""
      if show_line_numbers and vim.api.nvim_win_is_valid(target_win) and vim.api.nvim_buf_is_valid(target_buf) then
        local total = vim.api.nvim_buf_line_count(target_buf)
        local current = vim.api.nvim_win_get_cursor(target_win)[1]
        local reversed_row = total - current + 1
        line_text = string.format("[%d/%d]", reversed_row, total)
      end

      -- build status string: prefix + (spinner + space) + icon group + (line text)
      local fmt_msg = ""
      local prefix = " "
      local spinner_part = ""

      if is_loading then
        spinner_part = spinner_char .. " "
      end

      fmt_msg = prefix .. spinner_part .. icon_group_str .. line_text

      -- compute final width
      local final_width = vim.fn.strdisplaywidth(fmt_msg)
      if final_width < 1 then final_width = 1 end

      local ok, _ = pcall(vim.api.nvim_win_set_config, popup_winid,
        vim.tbl_deep_extend('force', winopts(final_width), {}))
      if not ok then return false end

      vim.api.nvim_buf_set_lines(popup_bufid, 0, -1, false, { fmt_msg })

      -- set highlights using extmarks
      local nid = vim.api.nvim_create_namespace('scrollbacknvim')
      vim.api.nvim_buf_clear_namespace(popup_bufid, nid, 0, -1)

      local current_byte_col = #prefix

      -- spinner highlight
      if is_loading then
        local end_pos = current_byte_col + #spinner_char
        local spinner_hl = (spinner_char == '✔') and 'KittyScrollbackNvimStatusWinReadyIcon' or
            'KittyScrollbackNvimStatusWinSpinnerIcon'
        vim.api.nvim_buf_set_extmark(popup_bufid, nid, 0, current_byte_col, { hl_group = spinner_hl, end_col = end_pos })

        current_byte_col = current_byte_col + #spinner_char + 1 -- 跳过 spinner + 空格
      end

      -- icon highlights
      if show_icons and not opts.status_window.style_simple then
        -- Kitty
        local end_pos = current_byte_col + #kitty_icon
        vim.api.nvim_buf_set_extmark(popup_bufid, nid, 0, current_byte_col,
          { hl_group = 'KittyScrollbackNvimStatusWinKittyIcon', end_col = end_pos })
        current_byte_col = end_pos + 1

        -- Heart
        end_pos = current_byte_col + #love_icon
        vim.api.nvim_buf_set_extmark(popup_bufid, nid, 0, current_byte_col,
          { hl_group = 'KittyScrollbackNvimStatusWinHeartIcon', end_col = end_pos })
        current_byte_col = end_pos + 1

        -- Nvim
        end_pos = current_byte_col + #nvim_icon
        vim.api.nvim_buf_set_extmark(popup_bufid, nid, 0, current_byte_col,
          { hl_group = 'KittyScrollbackNvimStatusWinNvimIcon', end_col = end_pos })
        current_byte_col = end_pos + 1
      end

      -- line number highlight
      if line_text ~= "" then
        local end_pos = current_byte_col + #line_text
        vim.api.nvim_buf_set_extmark(popup_bufid, nid, 0, current_byte_col, {
          hl_group = 'KittyScrollbackNvimStatusWinLineNum',
          end_col = end_pos
        })
      end

      return true
    end

    local count = 0
    local spinner = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '✔' }
    if opts.status_window.style_simple then
      spinner = { '-', '-', '\\', '\\', '|', '|', '*' }
    end

    vim.fn.timer_start(80, function(status_window_timer)
      count = count + 1
      local spinner_icon = count > #spinner and spinner[#spinner] or spinner[count]

      vim.defer_fn(function()
        render_status(true, spinner_icon)

        if count > #spinner then
          vim.fn.timer_stop(status_window_timer)

          if opts.status_window.autoclose then
            render_status(false, "")
            vim.fn.timer_start(60, function(close_window_timer)
              local ok_cfg, current_winopts = pcall(vim.api.nvim_win_get_config, popup_winid)
              if not ok_cfg then
                vim.fn.timer_stop(close_window_timer); return
              end
              if current_winopts.width > 2 then
                pcall(vim.api.nvim_win_set_config, popup_winid,
                  vim.tbl_deep_extend('force', current_winopts, { width = current_winopts.width - 1 }))
              else
                pcall(vim.api.nvim_win_close, popup_winid, true)
                vim.fn.timer_stop(close_window_timer)
              end
            end, { ['repeat'] = -1 })
          else
            if show_icons then
              local hl_def = vim.api.nvim_get_hl(0, { name = 'KittyScrollbackNvimStatusWinReadyIcon', link = false })
              hl_def = next(hl_def) and hl_def or {}
              local fg_dec = hl_def.fg or 16777215
              local fg_hex = string.format('#%06x', fg_dec)
              local darken_hex = ksb_util.darken(fg_hex, 0.7)
              vim.api.nvim_set_hl(0, 'KittyScrollbackNvimStatusWinReadyIcon', { fg = darken_hex })
            end

            render_status(false, "")

            -- register autocmd to update line numbers on cursor move
            -- only if show_line_numbers is true
            if show_line_numbers then
              vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
                buffer = target_buf,
                group = vim.api.nvim_create_augroup('KittyScrollBackStatusUpdate', { clear = true }),
                callback = function()
                  if not vim.api.nvim_win_is_valid(popup_winid) then return true end
                  render_status(false, "")
                end
              })
            end
          end
        end
      end, count > #spinner and 200 or 0)
    end, { ['repeat'] = -1 })

    vim.api.nvim_create_autocmd('WinResized', {
      group = vim.api.nvim_create_augroup('KittyScrollBackNvimStatusWindowResized', { clear = true }),
      callback = function()
        p.orig_columns = vim.o.columns
        local ok_cfg, current_winopts = pcall(vim.api.nvim_win_get_config, popup_winid)
        if not ok_cfg then return true end
        pcall(vim.api.nvim_win_set_config, popup_winid, vim.tbl_deep_extend('force', winopts(current_winopts.width), {
          width = M.size(vim.o.columns, current_winopts.width),
        }))
        return false
      end,
    })
  end
end

return M
