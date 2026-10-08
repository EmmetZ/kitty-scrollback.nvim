#!/usr/bin/env python3
from string import Template
from typing import List
from kitty.boss import Boss
from kittens.tui.handler import result_handler
from kitty.fast_data_types import get_options
from kitty.constants import config_dir, version
from kitty.utils import resolved_shell, which
from kitty.shell_integration import get_effective_ksi_env_var

import json
import os
import inspect

ksb_dir = os.path.dirname(
    os.path.dirname(os.path.abspath(inspect.getfile(lambda: None))))
cmd_not_found_title = Template(
    '😿 Failed to find $cmd executable. Please check your environment variable PATH.'
)
cmd_not_found_error = Template("""
Kitty failed to find $cmd in your PATH. If your PATH environment looks correct
and you are on MacOS, you may need to add an override to the file
<kitty config dir>/macos-launch-services-cmdline due to limitations of Apple
allowing you to use command line options with GUI applications.

  Please read the following section from the Kitty FAQ:
    How do I specify command line options for kitty on macOS?
    See https://sw.kovidgoyal.net/kitty/faq/#how-do-i-specify-command-line-options-for-kitty-on-macos

  For example, you could get the values of your current PATH environment variable and add them
  to ~/.config/kitty/macos-launch-services-cmdline which would look similar to the following.

  --override env=PATH="/Users/bram/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/sbin"

  After updating the macos-launch-services-cmdline file, completely quit and reopen Kitty
  to pick up those changes. If $cmd is in the PATH you specified, then this error should no longer occur.

Additionally, you can configure exe_search_path in Kitty to add additional paths that Kitty
will use to find programs to run. See https://sw.kovidgoyal.net/kitty/conf/#opt-kitty.exe_search_path



""")
open_an_issue_msg = """
 |\\___/|
=) ^Y^ (=
 \\  ^  /       If you have any issues or questions using kitty-scrollback.nvim then
  )=*=(        please create an issue at
 /     \\       https://github.com/mikesmithgh/kitty-scrollback.nvim/issues
 |     |
/| | | |\\
\\| | |_|/\\
 /_// ___/
    \\_)
"""


def main():
    raise SystemExit('Must be run as kitten kitty_scrollback_nvim')


# based on kitty source window.py
def pipe_data(w, target_window_id, config, kitty_path):
    kitty_opts = get_options()
    kitty_shell_integration = get_effective_ksi_env_var(kitty_opts)
    return {
        'kitty_path': kitty_path,
        'kitty_scrollback_config': config,
        'scrolled_by': w.screen.scrolled_by,
        'cursor_x': w.screen.cursor.x + 1,
        'cursor_y': w.screen.cursor.y + 1,
        'lines': w.screen.lines + 1,
        'columns': w.screen.columns,
        'window_id': int(target_window_id),
        'window_title': w.title,
        'ksb_dir': ksb_dir,
        'kitty_opts': {
            # shell_integration is no longer used by our validation (ref: #71), consider deprecating
            "shell_integration":
            kitty_shell_integration,
            "scrollback_fill_enlarged_window":
            kitty_opts.scrollback_fill_enlarged_window,
            "scrollback_lines":
            kitty_opts.scrollback_lines,
            "scrollback_pager":
            kitty_opts.scrollback_pager,
            "allow_remote_control":
            kitty_opts.allow_remote_control,
            "listen_on":
            kitty_opts.listen_on,
            "scrollback_pager_history_size":
            kitty_opts.scrollback_pager_history_size
        },
        'kitty_config_dir': config_dir,
        'kitty_version': version,
        'shell': resolved_shell(kitty_opts)[0]
    }


def parse_nvim_args(args=[]):
    for idx, arg in enumerate(args):
        if arg == '--nvim-args':
            if idx + 1 < len(args):
                return tuple(filter(None, args[idx + 1:]))
            return ()
    return ()


def parse_env(args):
    env_args = []
    for idx, arg in reversed(list(enumerate(args))):
        if arg == '--env' and (idx + 1 < len(args)):
            env_args.append('--env')
            env_args.append(args[idx + 1])
            del args[idx:idx + 2]
    return tuple(env_args)


def parse_config(args):
    config_args = []
    for idx, arg in reversed(list(enumerate(args))):
        if arg == '--config' and (idx + 1 < len(args)):
            config_args = args[idx + 1]
            del args[idx:idx + 2]
            return config_args
    return 'ksb_builtin_get_text_all'


def parse_cwd(args, default_cwd):
    for idx, arg in reversed(list(enumerate(args))):
        if arg == '--cwd' and (idx + 1 < len(args)):
            cwd_args = args[idx + 1]
            del args[idx:idx + 2]
            return ('--cwd', cwd_args)
    if default_cwd:
        return ('--cwd', default_cwd)
    return ()


@result_handler(type_of_input=None, no_ui=True, has_ready_notification=False)
def handle_result(args: List[str],
                  result: str,
                  target_window_id: int,
                  boss: Boss) -> None:
    del args[0]
    # Only parse kitten arguments before --nvim-args.
    kitten_arg_end = args.index('--nvim-args') if '--nvim-args' in args else len(args)
    smooth_start = '--smooth-start' in args[:kitten_arg_end]
    if smooth_start:
        args.remove('--smooth-start')
        from kitty.fast_data_types import (set_redirect_keys_to_overlay,
                                          buffer_keys_in_window, add_timer)
    w = boss.window_id_map.get(target_window_id)
    if w is not None:
        kitty_path = which('kitty')
        if not kitty_path:
            boss.show_error(
                cmd_not_found_title.substitute(cmd='kitty'),
                cmd_not_found_error.substitute(cmd='kitty') +
                open_an_issue_msg)
            return

        config = parse_config(args)
        cwd = parse_cwd(args, w.child.foreground_cwd)
        env = parse_env(args)
        kitty_data_str = pipe_data(w,
                                   target_window_id,
                                   config,
                                   kitty_path)
        kitty_data_str['kitty_overlay_behind'] = smooth_start
        kitty_data = json.dumps(kitty_data_str)

        if w.title.startswith('kitty-scrollback.nvim'):
            print(
                f'[Warning] kitty-scrollback.nvim: skipping action, window {target_window_id} has title that '
                'starts with "kitty-scrollback.nvim"')
            print(json.dumps(kitty_data_str, indent=2))
            return

        kitty_args = (
            '--copy-env',
            '--env',
            'KITTY_SCROLLBACK_NVIM=true',
            '--type',
            'overlay',
            '--title',
            'kitty-scrollback.nvim',
        ) + env + cwd
        if smooth_start:
            kitty_args += ('--keep-focus', '--env',
                           'KITTY_SCROLLBACK_NVIM_SMOOTH_START=true')

        # Prefer this launcher's Lua modules over another installed copy.
        nvim_args = parse_nvim_args(args) + (
            '--cmd',
            ' lua'
            ' vim.api.nvim_create_autocmd([[VimEnter]], {'
            '  group = vim.api.nvim_create_augroup([[KittyScrollBackNvimVimEnter]], { clear = true }),'
            '  pattern = [[*]],'
            '  callback = function()'
            f'  vim.opt.runtimepath:prepend([[{ksb_dir}]])'
            '   vim.api.nvim_exec_autocmds([[User]], { pattern = [[KittyScrollbackLaunch]], modeline = false })'
            f'  require([[kitty-scrollback.launch]]).setup_and_launch([[{kitty_data}]])'
            ' end,'
            ' })')

        nvim_path = which('nvim')
        if not nvim_path:
            boss.show_error(
                cmd_not_found_title.substitute(cmd='nvim'),
                cmd_not_found_error.substitute(cmd='nvim') + open_an_issue_msg)
            return

        cmd = ('launch', ) + kitty_args + (nvim_path, ) + nvim_args
        overlay_id = boss.call_remote_control(w, cmd)
        if smooth_start:
            overlay_id = int(overlay_id)
            overlay = boss.window_id_map[overlay_id]
            # Keep the source visible, buffering input until Neovim reports ready.
            set_redirect_keys_to_overlay(w.os_window_id, w.tab_id, w.id,
                                         overlay.id)
            buffer_keys_in_window(w.os_window_id, w.tab_id, overlay.id, True)
            overlay.keys_redirected_till_ready_from = w.id

            # Render only a small status layer; never write into the source buffer.
            from runpy import run_path
            run_path(os.path.join(ksb_dir, 'python', 'smooth_loading.py'))['start'](
                w, overlay, boss)

            # Startup error prompts can block Neovim before its timers run.
            # Reveal after five seconds so an error or hung startup stays usable.
            def reveal_if_still_pending(timer_id):
                pending = boss.window_id_map.get(overlay_id)
                if pending is not None and pending.keys_redirected_till_ready_from:
                    pending.handle_overlay_ready(memoryview(b''))

            add_timer(reveal_if_still_pending, 5.0, False)
    else:
        raise Exception(f'Failed to get window with id: {target_window_id}')
