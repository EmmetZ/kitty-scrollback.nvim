"""Draw loading status independently of the source terminal's text buffer."""
from kittens.tui.handler import result_handler


class LoadingStatus:
    def __init__(self, source, overlay, boss):
        from kitty.fast_data_types import (DECAWM, Screen, add_timer,
                                          cell_size_for_window,
                                          mark_os_window_dirty, remove_timer,
                                          set_window_title_bar_render_data)
        self.source = source
        self.overlay = overlay
        self.boss = boss
        self.cell_size = cell_size_for_window
        self.mark_dirty = mark_os_window_dirty
        self.remove_timer = remove_timer
        self.set_render_data = set_window_title_bar_render_data
        self.screen_type = Screen
        self.wrap_mode = DECAWM
        self.screen = None
        self.font_size = None
        self.timer = None
        self.simple = False
        self.frame = 0
        self.closed = False
        self.original_ready = overlay.handle_overlay_ready
        overlay.handle_overlay_ready = self.ready
        overlay.actions_on_removal.append(self.clear)
        overlay.ksb_loading_status = self
        self.draw()
        self.timer = add_timer(self.draw, 0.08, True)

    def ready(self, message):
        # Clear in the same callback that releases input and reveals Neovim.
        self.clear()
        self.original_ready(message)

    def clear(self, window=None):
        if self.closed:
            return
        self.closed = True
        if self.timer is not None:
            self.remove_timer(self.timer)
        source = self.boss.window_id_map.get(self.source.id)
        if source is not None and self.screen is not None:
            title_bar = getattr(source, '_title_bar_screen', None)
            if title_bar is not None:
                source.update_title_bar(is_active=source.is_focused)
            else:
                self.set_render_data(source.os_window_id, source.tab_id, source.id,
                                     self.screen, 0, 0, 0, 0)
            self.mark_dirty(source.os_window_id)
        self.overlay.handle_overlay_ready = self.original_ready
        del self.overlay.ksb_loading_status
        if window is None:
            self.overlay.actions_on_removal.remove(self.clear)

    def draw(self, timer_id=None):
        if (self.closed or self.source.id not in self.boss.window_id_map
                or self.overlay.id not in self.boss.window_id_map
                or not self.overlay.keys_redirected_till_ready_from):
            self.clear()
            return
        spinner = '|/-\\' if self.simple else '⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
        text = spinner[self.frame % len(spinner)]
        self.frame += 1
        cw, ch = self.cell_size(self.source.os_window_id)
        geometry = self.source.geometry
        columns = min(len(text), max(1, (geometry.right - geometry.left) // cw))
        if (self.screen is None or self.screen.columns != columns
                or self.font_size != (cw, ch)):
            self.screen = self.screen_type(None, 1, columns, 0, cw, ch)
            self.screen.reset_mode(self.wrap_mode)
            self.font_size = (cw, ch)
        self.screen.copy_colors_from(self.source.screen)
        self.screen.cursor.x = 0
        self.screen.cursor.bold = True
        self.screen.draw(text[:columns])
        self.set_render_data(self.source.os_window_id, self.source.tab_id,
                             self.source.id, self.screen,
                             geometry.right - columns * cw, geometry.top,
                             geometry.right, geometry.top + ch)
        self.mark_dirty(self.source.os_window_id)


def start(source, overlay, boss):
    # Older Kitty releases lack the independent text layer; keep smooth-start usable.
    try:
        return LoadingStatus(source, overlay, boss)
    except ImportError:
        return None


def main(args):
    pass


@result_handler(no_ui=True)
def handle_result(args, result, target_window_id, boss):
    overlay = boss.window_id_map.get(target_window_id)
    status = getattr(overlay, 'ksb_loading_status', None)
    if status is not None:
        if '--disabled' in args:
            status.clear()
        else:
            status.simple = '--simple' in args
