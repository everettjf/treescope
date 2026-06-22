"""Unit tests for the pure formatting / search helpers (no server needed)."""

from treescope_cli import format as fmt
from treescope_cli.protocol import Flag, capability_names, display_value, hex_color
from treescope_cli.screenshot import pick_screenshot_nodes

from mock_server import DEVICE, mock_hierarchy


def _snapshot():
    return {"device": DEVICE, "roots": mock_hierarchy(), "timestamp": 1, "serverVersion": "0.1.0"}


def test_render_tree_one_line_per_node_with_ids_and_frames():
    out = fmt.render_tree(mock_hierarchy(), {"max_depth": 0})
    assert "#obj:4" in out
    assert "LoginButton" in out
    assert "(16, 200, 358, 48)" in out
    assert "hidden" in out  # obj:4 has the hidden flag
    assert "α0.50" in out


def test_render_tree_visible_only_drops_hidden_and_zero():
    out = fmt.render_tree(mock_hierarchy(), {"max_depth": 0, "visible_only": True})
    assert "UIImageView" not in out  # zero-size
    assert "LoginButton" not in out  # hidden


def test_render_tree_filter_keeps_matches_and_ancestors():
    out = fmt.render_tree(mock_hierarchy(), {"max_depth": 0, "match": "login"})
    assert "LoginButton" in out
    assert "UIWindow" in out      # ancestor kept
    assert "UILabel" not in out


def test_render_tree_depth_limit_notes_elided_children():
    out = fmt.render_tree(mock_hierarchy(), {"max_depth": 2})
    assert "depth limit" in out
    assert "UILabel" not in out


def test_find_nodes_by_class_label_and_attr_text():
    roots = mock_hierarchy()
    assert fmt.find_nodes(roots, "Welcome", 50)[0]["id"] == "obj:3"      # attribute text
    assert fmt.find_nodes(roots, "Log In", 50)[0]["id"] == "obj:4"        # label
    assert fmt.find_nodes(roots, "UIImageView", 50)[0]["id"] == "obj:5"   # class
    assert fmt.find_nodes(roots, "UILabel", 50)[0]["path"] == "UIWindow › RootView › UILabel"


def test_find_nodes_respects_limit():
    assert len(fmt.find_nodes(mock_hierarchy(), "UI", 2)) == 2


def test_find_node_by_id():
    roots = mock_hierarchy()
    assert fmt.find_node(roots, "obj:3")["displayName"] == "UILabel"
    assert fmt.find_node(roots, "nope") is None


def test_render_node_shows_sections_and_editable_keypaths():
    node = fmt.find_node(mock_hierarchy(), "obj:3")
    out = fmt.render_node(node)
    assert "[Text]" in out
    assert "(editable: text)" in out
    assert "Welcome back" in out


def test_display_value_formats_typed_values():
    assert display_value({"t": "number", "v": 0.5}) == "0.5"
    assert display_value({"t": "number", "v": 12}) == "12.0"
    assert display_value({"t": "integer", "v": 3}) == "3"
    assert display_value({"t": "bool", "v": True}) == "true"
    assert display_value({"t": "null"}) == "nil"
    assert display_value({"t": "size", "v": {"width": 10, "height": 20}}) == "10.0 x 20.0"


def test_hex_color_with_and_without_alpha():
    assert hex_color({"red": 1, "green": 0, "blue": 0, "alpha": 1}) == "#FF0000"
    assert hex_color({"red": 0, "green": 0, "blue": 0, "alpha": 0.5}) == "#00000080"


def test_capability_names_decodes_bitset():
    assert capability_names(31) == ["snapshots", "liveEditing", "swiftUI", "highlighting", "pushUpdates"]
    assert capability_names(Flag.hidden) == ["snapshots"]


def test_count_and_summary():
    snap = _snapshot()
    assert fmt.count_nodes(snap["roots"]) == 5
    assert fmt.snapshot_summary(snap) == "1 root(s), 5 nodes total"


def test_render_device():
    out = fmt.render_device(DEVICE)
    assert "MockApp" in out
    assert "393 x 852 @3x" in out


def test_pick_screenshot_nodes_prefers_window_then_content_view():
    ids = pick_screenshot_nodes(mock_hierarchy())
    assert ids[0] == "obj:1"   # the window, largest visible root
    assert "obj:2" in ids       # content-view fallback
