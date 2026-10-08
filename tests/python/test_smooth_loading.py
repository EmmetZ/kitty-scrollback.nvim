"""Lifecycle checks for the native status layer, without launching Kitty."""
import runpy
import sys
import unittest
from pathlib import Path
from types import ModuleType, SimpleNamespace
from unittest.mock import Mock, patch


class LoadingStatusTest(unittest.TestCase):
    def setUp(self):
        self.native = ModuleType('kitty.fast_data_types')
        self.native.DECAWM = 7
        self.native.Screen = Mock(side_effect=lambda *args: SimpleNamespace(
            columns=args[2], cursor=SimpleNamespace(x=0, bold=False),
            reset_mode=Mock(), copy_colors_from=Mock(), draw=Mock()))
        self.native.add_timer = Mock(return_value=42)
        self.native.remove_timer = Mock()
        self.native.cell_size_for_window = Mock(return_value=(10, 20))
        self.native.mark_os_window_dirty = Mock()
        self.native.set_window_title_bar_render_data = Mock()
        handler = ModuleType('kittens.tui.handler')
        handler.result_handler = lambda **kwargs: lambda fn: fn
        self.modules = patch.dict(sys.modules, {
            'kitty.fast_data_types': self.native, 'kittens.tui.handler': handler,
        })
        self.modules.start()
        self.addCleanup(self.modules.stop)
        self.module = runpy.run_path(str(Path(__file__).resolve().parents[2]
                                        / 'python' / 'smooth_loading.py'))
        self.source = SimpleNamespace(
            id=1, os_window_id=2, tab_id=3, screen=object(), is_focused=True,
            geometry=SimpleNamespace(left=0, top=0, right=800, bottom=600),
            update_title_bar=Mock())
        self.overlay = SimpleNamespace(id=4, keys_redirected_till_ready_from=1,
                                       actions_on_removal=[], handle_overlay_ready=Mock())
        self.original_ready = self.overlay.handle_overlay_ready
        self.boss = SimpleNamespace(window_id_map={1: self.source, 4: self.overlay})

    def start(self):
        return self.module['start'](self.source, self.overlay, self.boss)

    def test_clear_before_ready_releases_input(self):
        status = self.start()
        self.assertEqual('⠋', status.screen.draw.call_args.args[0])
        self.assertEqual(self.native.add_timer.call_args.args[1:], (0.08, True))
        self.original_ready.side_effect = lambda msg: self.assertTrue(status.closed)
        self.overlay.handle_overlay_ready(b'ready')
        self.original_ready.assert_called_once_with(b'ready')
        self.native.remove_timer.assert_called_once_with(42)
        self.assertFalse(hasattr(self.overlay, 'ksb_loading_status'))
        self.assertEqual(self.overlay.actions_on_removal, [])
        self.assertEqual(self.native.set_window_title_bar_render_data.call_args.args[-4:], (0, 0, 0, 0))
        status.clear()
        self.native.remove_timer.assert_called_once()

    def test_restores_existing_title_bar(self):
        self.source._title_bar_screen = object()
        status = self.start()
        status.clear()
        self.source.update_title_bar.assert_called_once_with(is_active=True)

    def test_removal_keeps_other_callbacks(self):
        self.start()
        after = Mock()
        self.overlay.actions_on_removal.append(after)
        for callback in self.overlay.actions_on_removal:
            callback(self.overlay)
        after.assert_called_once_with(self.overlay)
        self.native.remove_timer.assert_called_once_with(42)

    def test_configures_disabled_or_simple_status(self):
        status = self.start()
        self.module['handle_result'](['helper', '--simple'], None, 4, self.boss)
        status.draw()
        self.assertTrue(status.screen.draw.call_args.args[0].isascii())
        self.module['handle_result'](['helper', '--disabled'], None, 4, self.boss)
        self.assertTrue(status.closed)

    def test_follows_geometry_and_font_size(self):
        status = self.start()
        self.source.geometry.right = 60
        self.native.cell_size_for_window.return_value = (12, 24)
        status.draw()
        self.assertEqual(status.screen.columns, 1)
        self.assertEqual(self.native.set_window_title_bar_render_data.call_args.args[-4:], (48, 0, 60, 24))

    def test_source_disappearance_stops_timer(self):
        status = self.start()
        del self.boss.window_id_map[1]
        status.draw()
        self.assertTrue(status.closed)
        self.native.remove_timer.assert_called_once_with(42)

    def test_old_kitty_without_text_layer_still_starts(self):
        del self.native.set_window_title_bar_render_data
        self.assertIsNone(self.start())
        self.assertIs(self.overlay.handle_overlay_ready, self.original_ready)


if __name__ == '__main__':
    unittest.main()
