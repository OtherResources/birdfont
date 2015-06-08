/*
    Copyright (C) 2012 2014 Johan Mattsson

    This library is free software; you can redistribute it and/or modify 
    it under the terms of the GNU Lesser General Public License as 
    published by the Free Software Foundation; either version 3 of the 
    License, or (at your option) any later version.

    This library is distributed in the hope that it will be useful, but 
    WITHOUT ANY WARRANTY; without even the implied warranty of 
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU 
    Lesser General Public License for more details.
*/

using Cairo;

namespace BirdFont {

/** A display with all glyphs present in this font. */
public class OverView : FontDisplay {
	public WidgetAllocation allocation = new WidgetAllocation ();
	
	OverViewItem selected_item = new OverViewItem (null, '\0', 0, 0);

	public Gee.ArrayList<GlyphCollection> copied_glyphs = new Gee.ArrayList<GlyphCollection> ();
	public Gee.ArrayList<GlyphCollection> selected_items = new Gee.ArrayList<GlyphCollection> ();	
	
	int selected = 0;
	int first_visible = 0;
	int rows = 0;
	int items_per_row = 0;
	
	double view_offset_y = 0;
	double view_offset_x = 0;
	
	public signal void open_new_glyph_signal (unichar c);
	public signal void open_glyph_signal (GlyphCollection c);
	
	public GlyphRange glyph_range;
	string search_query = "";
	
	Gee.ArrayList<OverViewItem> visible_items = new Gee.ArrayList<OverViewItem> ();
	
	/** List of undo commands. */
	Gee.ArrayList<OverViewUndoItem> undo_items = new Gee.ArrayList<OverViewUndoItem> ();
	Gee.ArrayList<OverViewUndoItem> redo_items = new Gee.ArrayList<OverViewUndoItem> ();
	
	/** Show all characters that has been drawn. */
	public bool all_available {
		set {
			_all_available = value;
			update_item_list ();
		}
		
		get {
			return _all_available;
		}
	}
	
	bool _all_available = false;
	
	/** Show unicode database info. */
	CharacterInfo? character_info = null;
	
	double scroll_size = 1;
	const double UCD_LINE_HEIGHT = 17 * 1.3;

	public OverView (GlyphRange? range = null, bool open_selected = true) {
		GlyphRange gr;

		if (range == null) {
			gr = new GlyphRange ();
			set_glyph_range (gr);
		}

		if (open_selected) {
			this.open_glyph_signal.connect ((glyph_collection) => {
				TabBar tabs = MainWindow.get_tab_bar ();
				string n = glyph_collection.get_current ().name;
				bool selected = tabs.select_char (n);
				GlyphCanvas canvas;
				Glyph g = glyph_collection.get_current (); 
				
				if (!selected) {
					canvas = MainWindow.get_glyph_canvas ();
					tabs.add_tab (g, true, glyph_collection);
					canvas.set_current_glyph_collection (glyph_collection);
					set_initial_zoom ();
				}
			});

			this.open_new_glyph_signal.connect ((character) => {
				create_new_glyph (character);
			});
		}

		IdleSource idle = new IdleSource ();

		idle.set_callback (() => {			
			selected_canvas ();
			use_default_character_set ();
			return false;
		});
		
		idle.attach (null);
		
		update_scrollbar ();
		reset_zoom ();
		update_item_list ();
	}
	
	public void use_default_character_set () {
		GlyphRange gr = new GlyphRange ();
		all_available = false;
		DefaultCharacterSet.use_default_range (gr);
		set_glyph_range (gr);
		OverviewTools.update_overview_characterset ();
		FontDisplay.dirty_scrollbar = true;
	}
	
	public GlyphCollection create_new_glyph (unichar character) {
		StringBuilder name = new StringBuilder ();
		TabBar tabs = MainWindow.get_tab_bar ();
		bool selected;
		Glyph glyph;
		GlyphCollection glyph_collection = MainWindow.get_current_glyph_collection ();
		GlyphCanvas canvas;
			
		name.append_unichar (character);
		selected = tabs.select_char (name.str);
				
		if (!selected) {
			glyph_collection = add_character_to_font (character);
			
			glyph = glyph_collection.get_current ();
			tabs.add_tab (glyph, true, glyph_collection);
			
			selected_items.add (glyph_collection);
			
			canvas = MainWindow.get_glyph_canvas ();
			canvas.set_current_glyph_collection (glyph_collection);
			
			set_initial_zoom ();
		} else {
			warning ("Glyph is already open");
		}
		
		OverviewTools.update_overview_characterset ();
		return glyph_collection;
	}
	
	public GlyphCollection add_empty_character_to_font (unichar character, bool unassigned, string name) {
		return add_character_to_font (character, true, unassigned);
	}
	
	public GlyphCollection add_character_to_font (unichar character, bool empty = false,
			bool unassigned = false, string glyph_name = "") {
		StringBuilder name = new StringBuilder ();
		Font font = BirdFont.get_current_font ();
		GlyphCollection? fg;
		Glyph glyph;
		GlyphCollection glyph_collection;

		if (glyph_name == "") {
			name.append_unichar (character);
		} else {
			name.append (glyph_name);
		}
		
		if (all_available) {
			fg = font.get_glyph_collection_by_name (name.str);
		} else {
			fg = font.get_glyph_collection (name.str);
		}

		if (fg != null) {
			glyph_collection = (!) fg;
		} else {
			glyph_collection = new GlyphCollection (character, name.str);
			
			if (!empty) {
				glyph = new Glyph (name.str, (!unassigned) ? character : '\0');
				glyph_collection.insert_glyph (glyph, true);
			}
			
			font.add_glyph_collection (glyph_collection);
		}
		
		glyph_collection.set_unassigned (unassigned);
		
		return glyph_collection;
	}
	
	public static void search () {
		OverView ow = MainWindow.get_overview ();
		TextListener listener = new TextListener (t_("Search"), ow.search_query, t_("Filter"));
		
		listener.signal_text_input.connect ((text) => {
			OverView o = MainWindow.get_overview ();
			o.search_query = text;
		});
		
		listener.signal_submit.connect (() => {
			OverView o = MainWindow.get_overview ();
			GlyphRange r = CharDatabase.search (o.search_query);
			o.set_glyph_range (r);
			TabContent.hide_text_input ();
			MainWindow.get_tab_bar ().select_tab_name ("Overview");
		});
		
		TabContent.show_text_input (listener);
	}
	
	public Glyph? get_current_glyph () {
		OverViewItem oi = selected_item;
		if (oi.glyphs != null) {
			return ((!) oi.glyphs).get_current ();
		}
		return null;
	}
	
	private void set_initial_zoom () {
		Toolbox tools = MainWindow.get_toolbox ();
		ZoomTool z = (ZoomTool) tools.get_tool ("zoom_tool");
		z.store_current_view ();
		MainWindow.get_current_glyph ().default_zoom ();
		z.store_current_view ();
		OverViewItem.reset_label ();
	}

	public double get_height () {
		double l;
		Font f;
		
		if (rows == 0) {
			return 0;
		}
				
		if (all_available) {
			f = BirdFont.get_current_font ();
			l = f.length ();
		} else {
			l = glyph_range.length ();
		}
				
		return 2.0 * OverViewItem.height * (l / rows);
	}

	public bool selected_char_is_visible () {
		return first_visible <= selected <= first_visible + items_per_row * rows;
	}

	public override bool has_scrollbar () {
		return true;
	}

	public override void scroll_wheel_up (double x, double y) {
		key_up ();
		update_scrollbar ();
		GlyphCanvas.redraw ();
		hide_menu ();

		selected_item = get_selected_item ();
		selected_items.clear ();
		if (selected_item.glyphs != null) {
			selected_items.add ((!) selected_item.glyphs);
		}
	}
	
	public override void scroll_wheel_down (double x, double y) {
		key_down ();
		update_scrollbar ();
		GlyphCanvas.redraw ();
		hide_menu ();

		selected_item = get_selected_item ();
		selected_items.clear ();
		if (selected_item.glyphs != null) {
			selected_items.add ((!) selected_item.glyphs);
		}
	}
	
	public override void selected_canvas () {
		OverviewTools.update_overview_characterset ();
		KeyBindings.set_require_modifier (true);
		update_scrollbar ();
		update_zoom_bar ();
		OverViewItem.glyph_scale = 1;
		update_item_list ();
		selected_item = get_selected_item ();
		GlyphCanvas.redraw ();

		IdleSource idle = new IdleSource ();

		idle.set_callback (() => {	
			use_default_character_set ();
			GlyphCanvas.redraw ();
			return false;
		});
		
		idle.attach (null);
	}
	
	public void update_zoom_bar () {
		double z = OverViewItem.width / OverViewItem.DEFAULT_WIDTH - 0.5;
		Toolbox.overview_tools.zoom_bar.set_zoom (z);
		Toolbox.redraw_tool_box ();
		update_item_list ();
	}
	
	public void set_zoom (double zoom) {
		double z = zoom + 0.5;
		OverViewItem.glyph_scale = 1;
		OverViewItem.width = OverViewItem.DEFAULT_WIDTH * z;
		OverViewItem.height = OverViewItem.DEFAULT_HEIGHT * z;
		OverViewItem.margin = OverViewItem.DEFAULT_MARGIN * z;
		update_item_list ();
		OverViewItem.reset_label ();
		GlyphCanvas.redraw ();	
	}
	
	public override void zoom_min () {
		OverViewItem.width = OverViewItem.DEFAULT_WIDTH * 0.5;
		OverViewItem.height = OverViewItem.DEFAULT_HEIGHT * 0.5;
		OverViewItem.margin = OverViewItem.DEFAULT_MARGIN * 0.5;
		update_item_list ();
		OverViewItem.reset_label ();
		GlyphCanvas.redraw ();
		update_zoom_bar ();
	}
	
	public override void reset_zoom () {
		OverViewItem.width = OverViewItem.DEFAULT_WIDTH;
		OverViewItem.height = OverViewItem.DEFAULT_HEIGHT;
		OverViewItem.margin = OverViewItem.DEFAULT_MARGIN;
		update_item_list ();
		OverViewItem.reset_label ();
		GlyphCanvas.redraw ();
		update_zoom_bar ();
	}

	public override void zoom_max () {
		OverViewItem.width = allocation.width;
		OverViewItem.height = allocation.height;
		update_item_list ();
		OverViewItem.reset_label ();
		GlyphCanvas.redraw ();
	}
	
	public override void zoom_in () {
		OverViewItem.width *= 1.1;
		OverViewItem.height *= 1.1;
		OverViewItem.margin *= 1.1;
		update_item_list ();
		OverViewItem.reset_label ();
		GlyphCanvas.redraw ();
		update_zoom_bar ();
	}
	
	public override void zoom_out () {
		OverViewItem.width *= 0.9;
		OverViewItem.height *= 0.9;
		OverViewItem.margin *= 0.9;
		update_item_list ();
		OverViewItem.reset_label ();
		GlyphCanvas.redraw ();
		update_zoom_bar ();
	}

	public override void store_current_view () {
	}
	
	public override void restore_last_view () {
	}

	public override void next_view () {
	}

	public override string get_label () {
		return t_("Overview");
	}
	
	public override string get_name () {
		return "Overview";
	}
	
	public void display_all_available_glyphs () {
		all_available = true;

		first_visible = 0;
		selected = 0;
		
		update_item_list ();
		selected_item = get_selected_item ();
		GlyphCanvas.redraw ();
	}
	
	OverViewItem get_selected_item () {
		if (visible_items.size == 0) {
			return new OverViewItem (null, '\0', 0, 0);
		}
		
		if (unlikely (!(0 <= selected < visible_items.size))) { 
			warning (@"0 <= $selected < $(visible_items.size)");
			return new OverViewItem (null, '\0', 0, 0);
		}	
		
 		return visible_items.get (selected);
	}
	
	int get_items_per_row () {
		int i = 1;
		OverViewItem.margin = OverViewItem.width * 0.1;
		double l = OverViewItem.margin + OverViewItem.full_width ();
		while (l <= allocation.width) {
			l += OverViewItem.full_width ();
			i++;
		}
		return i - 1;
	}
	
	public void update_item_list (int item_list_length = -1) {
		string character_string;
		Font f = BirdFont.get_current_font ();
		GlyphCollection? glyphs = null;
		uint32 index;
		OverViewItem item;
		double x, y;
		unichar character;
		Glyph glyph;
		
		items_per_row = get_items_per_row ();
		rows = (int) (allocation.height /  OverViewItem.full_height ()) + 2;
		
		if (item_list_length == -1) {
			item_list_length = items_per_row * rows;
		}
		
		visible_items.clear ();
		visible_items = new Gee.ArrayList<OverViewItem> ();
						
		// update item list
		index = (uint32) first_visible;
		x = OverViewItem.margin;
		y = OverViewItem.margin;
		for (int i = 0; i < item_list_length; i++) {
			if (all_available) {
				if (! (0 <= index < f.length ())) {
					break;
				}
				
				glyphs = f.get_glyph_collection_indice ((uint32) index);
				return_if_fail (glyphs != null);
				
				glyph = ((!) glyphs).get_current ();
				character_string = glyph.name;
				character = glyph.unichar_code;
			} else {
				if (!(0 <= index < glyph_range.get_length ())) {
					break;
				}
				
				character_string = glyph_range.get_char ((uint32) index);
				glyphs = f.get_glyph_collection_by_name (character_string);
				character = character_string.get_char (0);
			}
			
			item = new OverViewItem (glyphs, character, x, y);
			item.adjust_scale ();
			
			x += OverViewItem.full_width ();
			
			if (x + OverViewItem.full_width () >= allocation.width) {
				x = OverViewItem.margin;
				y += OverViewItem.full_height ();
			}
			
			item.selected = (i == selected);
			
			if (glyphs != null) {
				item.selected |= selected_items.index_of ((!) glyphs) != -1;
			}
			
			visible_items.add (item);
			index++;
		}
		
		// offset 
		item = get_selected_item ();
		if (item.y + OverViewItem.height > allocation.height) {
			view_offset_y = allocation.height - (item.y + OverViewItem.height);
		}

		if (item.y + view_offset_y < 0) {
			view_offset_y = 0;
		}
		
		foreach (OverViewItem i in visible_items) {
			i.y += view_offset_y;
			i.x += view_offset_x;
		}		
	}
	
	public override void draw (WidgetAllocation allocation, Context cr) {
		this.allocation = allocation;
		
		// clear canvas
		cr.save ();
		Theme.color (cr, "Background 1");
		cr.rectangle (0, 0, allocation.width, allocation.height);
		cr.fill ();
		cr.restore ();
		
		foreach (OverViewItem i in visible_items) {
			i.draw (allocation, cr);
		}
		
		if (unlikely (visible_items.size == 0)) {
			draw_empty_canvas (allocation, cr);
		}
		
		if (unlikely (character_info != null)) {
			draw_character_info (cr);
		}
	}
		
	void draw_empty_canvas (WidgetAllocation allocation, Context cr) {
		Text t;
		
		cr.save ();
		t = new Text (t_("No glyphs in this view."), 24);
		Theme.text_color (t, "Text Foreground");
		t.widget_x = 40;
		t.widget_y = 30;
		t.draw (cr);
		cr.restore ();
	}
	
	public void scroll_rows (int row_adjustment) {
		for (int i = 0; i < row_adjustment; i++) {
			scroll (-OverViewItem.height);
		}
		
		for (int i = 0; i > row_adjustment; i--) {
			scroll (OverViewItem.height);
		}
	}
	
	public void scroll_adjustment (double pixel_adjustment) {
		double l;
		Font f;
				
		if (all_available) {
			f = BirdFont.get_current_font ();
			l = f.length ();
		} else {
			l = glyph_range.length ();
		}
		
		if (first_visible <= 0) {
			return;
		}

		if (first_visible + rows * items_per_row >= l) {
			return;
		}
		
		scroll ((int64) pixel_adjustment);
	}
	
	void default_position () {
		scroll_top ();
		scroll_rows (1);
	}
	
	void scroll_to_position (int64 r) {
		if (r < 0) {
			scroll_top ();
			return;
		}
		
		default_position ();
		
		first_visible = (int) r;
		update_item_list ();
	}
	
	public override void scroll_to (double position) requires (items_per_row > 0) {
		double r;
		int nrows;
		Font f;
		
		if (all_available) {
			f = BirdFont.get_current_font ();
			nrows = (int) (f.length () / items_per_row);
		} else {
			nrows = (int) (glyph_range.length () / items_per_row);
		}
		
		view_offset_y = 0;
		r = (int64) (position * (nrows - rows + 3)); // 3 invisible rows
		r *= items_per_row;
		
		scroll_to_position ((int64) r);
		update_item_list ();
		GlyphCanvas.redraw ();
	}
		
	private void scroll (double pixel_adjustment) {
		if (first_visible < 0 && pixel_adjustment < 0) {
			scroll_top ();
			return;
		}
				
		view_offset_y += pixel_adjustment;
		
		if (view_offset_y >= 0) {
			while (view_offset_y > OverViewItem.height) {			
				view_offset_y -= OverViewItem.height;
				first_visible -= items_per_row;
			}

			first_visible -= items_per_row;
			view_offset_y -= OverViewItem.height;
		} else if (view_offset_y < -OverViewItem.height) {
			view_offset_y = 0;
			first_visible += items_per_row;
		}
		
		update_item_list ();
	}
	
	public void scroll_top () {
		selected = 0;
		first_visible = 0;
		
		update_item_list ();
		
		if (visible_items.size != 0) {
			selected_item = get_selected_item ();
		}
	}

	/** Returns true if the selected glyph is at the last row. */
	private bool last_row () {
		return visible_items.size - selected <= items_per_row;
	}

	public void key_down () {
		Font f = BirdFont.get_current_font ();
		int64 len = (all_available) ? f.length () : glyph_range.length ();
		
		if (at_bottom () && last_row ()) {
			return;
		}
		
		selected += items_per_row;
		
		if (selected >= items_per_row * rows) {
			first_visible += items_per_row;
			selected -= items_per_row;
		}
		
		if (first_visible + selected >= len) {
			selected = (int) (len - first_visible - 1);
			
			if (selected < items_per_row * (rows - 1)) {
				first_visible -= items_per_row;
				selected += items_per_row;
			}
		}
		
		if (selected >= visible_items.size) { 
			selected = (int) (visible_items.size - 1); 
		}

		selected_item = get_selected_item ();
		update_item_list ();
	}

	public void key_right () {
		Font f = BirdFont.get_current_font ();
		int64 len = (all_available) ? f.length () : glyph_range.length ();

		if (at_bottom () && first_visible + selected + 1 >= len) {
			selected = (int) (visible_items.size - 1);
			selected_item = get_selected_item ();
			return;
		}
		
		selected += 1;
		
		if (selected >= items_per_row * rows) {
			first_visible += items_per_row;
			selected -= items_per_row;
			selected -= 1;
		}		

		if (first_visible + selected > len) {
			first_visible -= items_per_row;
			selected = (int) (len - first_visible - 1);
			selected_item = get_selected_item ();
		}
		update_item_list ();
	}
	
	public void key_up () {
		selected -= items_per_row;
		
		if (selected < 0) {
			first_visible -= items_per_row;
			selected += items_per_row;			
		}
		
		if (first_visible < 0) {
			first_visible = 0;		
		}
		update_item_list ();
	}
	
	public void key_left () {
		selected -= 1;

		if (selected < 0) {
			first_visible -= items_per_row;
			selected += items_per_row;
			selected += 1;			
		}

		if (first_visible < 0) {
			scroll_top ();
		}
		update_item_list ();
	}
	
	public string get_selected_char () {
		Font f;
		Glyph? g;
		
		if (all_available) {
			f = BirdFont.get_current_font ();
			g = f.get_glyph_indice (selected);
			return_val_if_fail (g != null, "".dup ());
			return ((!) g).get_name ();
		}
		
		return glyph_range.get_char (selected);
	}
	
	public override void key_press (uint keyval) {
		hide_menu ();
		update_item_list ();
		GlyphCanvas.redraw ();

		if (KeyBindings.modifier == CTRL) {
			return;
		}

		switch (keyval) {
			case Key.ENTER:
				open_current_glyph ();
				return;
			
			case Key.UP:
				key_up ();
				selected_item = get_selected_item ();
				
				selected_items.clear ();
				if (selected_item.glyphs != null) {
					selected_items.add ((!) selected_item.glyphs);
				}
				return;
				
			case Key.RIGHT:
				key_right ();
				selected_item = get_selected_item ();
				
				selected_items.clear ();
				if (selected_item.glyphs != null) {
					selected_items.add ((!) selected_item.glyphs);
				}
				return;
				
			case Key.LEFT:
				key_left ();
				selected_item = get_selected_item ();
				
				selected_items.clear ();
				if (selected_item.glyphs != null) {
					selected_items.add ((!) selected_item.glyphs);
				}
				return;
				
			case Key.DOWN:
				key_down ();
				selected_item = get_selected_item ();
				
				selected_items.clear ();
				if (selected_item.glyphs != null) {
					selected_items.add ((!) selected_item.glyphs);
				}
				return;
				
			case Key.PG_UP:
				for (int i = 0; i < rows; i++) {
					key_up ();
				}
				selected_item = get_selected_item ();
				
				selected_items.clear ();
				if (selected_item.glyphs != null) {
					selected_items.add ((!) selected_item.glyphs);
				}
				return;
				
			case Key.PG_DOWN:
				for (int i = 0; i < rows; i++) {
					key_down ();
				}
				selected_item = get_selected_item ();

				selected_items.clear ();
				if (selected_item.glyphs != null) {
					selected_items.add ((!) selected_item.glyphs);
				}
				return;
				
			case Key.DEL:
				delete_selected_glyph ();
				selected_item = get_selected_item ();
				return;
				
			case Key.BACK_SPACE:
				delete_selected_glyph ();
				selected_item = get_selected_item ();
				return;
		}

		scroll_to_char (keyval);
		selected_item = get_selected_item ();

		selected_items.clear ();
		if (selected_item.glyphs != null) {
			selected_items.add ((!) selected_item.glyphs);
		}
		
		update_item_list ();
	}
	
	public void delete_selected_glyph () {
		Font font = BirdFont.get_current_font ();
		OverViewUndoItem undo_item = new OverViewUndoItem ();
		
		foreach (GlyphCollection g in selected_items) {
			undo_item.glyphs.add (g.copy ());
		}
		store_undo_items (undo_item);

		foreach (GlyphCollection gc in selected_items) {
			font.delete_glyph (gc);
		}
	}
	
	public override void undo () {
		Font font = BirdFont.get_current_font ();
		OverViewUndoItem previous_collection;
		
		if (undo_items.size == 0) {
			return;
		}
		
		previous_collection = undo_items.get (undo_items.size - 1);
		redo_items.add (get_current_state (previous_collection));
		
		// remove the old glyph and add the new one
		foreach (GlyphCollection g in previous_collection.glyphs) {
			font.delete_glyph (g);
			
			if (g.length () > 0) {
				font.add_glyph_collection (g);
			}
		}
		
		undo_items.remove_at (undo_items.size - 1);
		GlyphCanvas.redraw ();
	}
	
	public override void redo () {
		Font font = BirdFont.get_current_font ();
		OverViewUndoItem previous_collection;

		if (redo_items.size == 0) {
			return;
		}
		
		previous_collection = redo_items.get (redo_items.size - 1);
		undo_items.add (get_current_state (previous_collection));

		// remove the old glyph and add the new one
		foreach (GlyphCollection g in previous_collection.glyphs) {
			font.delete_glyph (g);
			font.add_glyph_collection (g);
		}
		
		redo_items.remove_at (redo_items.size - 1);
		GlyphCanvas.redraw ();
	}	
	
	public OverViewUndoItem get_current_state (OverViewUndoItem previous_collection) {
		GlyphCollection? gc;
		OverViewUndoItem ui = new OverViewUndoItem ();
		Font font = BirdFont.get_current_font ();
		
		foreach (GlyphCollection g in previous_collection.glyphs) {
			gc = font.get_glyph_collection (g.get_name ());
			
			if (gc != null) {
				ui.glyphs.add (((!) gc).copy ());
			} else {
				ui.glyphs.add (new GlyphCollection (g.get_unicode_character (), g.get_name ()));
			}
		}
		
		return ui;		
	}
	
	public void store_undo_state (GlyphCollection gc) {
		OverViewUndoItem i = new OverViewUndoItem ();
		i.glyphs.add (gc);
		store_undo_items (i);
	}

	public void store_undo_items (OverViewUndoItem i) {
		undo_items.add (i);
		redo_items.clear ();
	}
	
	bool select_visible_glyph (string name) {
		int i = 0;
		
		foreach (OverViewItem o in visible_items) {
			if (o.get_name () == name) {
				selected = i;
				selected_item = get_selected_item ();
				return true;
			}
			
			if (i > 1000) {
				warning ("selected character not found");
				return true;
			}
			
			i++;
		}
		
		return false;
	}
	
	public void scroll_to_char (unichar c) {
		StringBuilder s = new StringBuilder ();

		if (is_modifier_key (c)) {
			return;
		}
		
		s.append_unichar (c);
		scroll_to_glyph (s.str);
	}
		
	public void scroll_to_glyph (string name) {
		GlyphRange gr = glyph_range;
		int i, r, index;
		string ch;
		Font font = BirdFont.get_current_font ();
		GlyphCollection? glyphs = null;
		Glyph glyph;
		
		index = -1;
		
		if (items_per_row <= 0) {
			return;
		}

		ch = name;

		// selected char is visible
		if (select_visible_glyph (ch)) {
			return;
		}
		
		// scroll to char
		if (all_available) {
			
			// don't search for glyphs in huge CJK fonts 
			if (font.length () > 300) {
				r = 0;
			} else {
				// FIXME: too slow
				for (r = 0; r < font.length (); r += items_per_row) {
					for (i = 0; i < items_per_row; i++) {
						glyphs = font.get_glyph_collection_indice ((uint32) r + i);
						return_if_fail (glyphs != null);
						glyph = ((!) glyphs).get_current ();
						
						if (glyph.name == ch) {
							index = i;
						}
					}
					
					if (index > -1) {
						break;
					}
				}
			}
		} else {
			
			if (ch.char_count () > 1) {
				warning ("Can't scroll to ligature in this view");
				return;
			}
			
			for (r = 0; r < gr.length (); r += items_per_row) {
				for (i = 0; i < items_per_row; i++) {
					if (gr.get_char (r + i) == ch) {
						index = i;
					}
				}
				
				if (index > -1) {
					break;
				}
			}
		}
		
		if (index > -1) {
			first_visible = r;
			update_item_list ();
			select_visible_glyph (ch);
		}
	}
	
	public override void double_click (uint button, double ex, double ey) 
		requires (!is_null (visible_items) && !is_null (allocation)) {
		
		return_if_fail (!is_null (this));
		
		foreach (OverViewItem i in visible_items) {
			if (i.double_click (button, ex, ey)) {
				open_overview_item (i);
			}
		}
	
		GlyphCanvas.redraw ();
	}

	public void open_overview_item (OverViewItem i) {
		if (i.glyphs != null) {
			open_glyph_signal ((!) i.glyphs);
			((!) i.glyphs).get_current ().close_path ();
		} else {
			open_new_glyph_signal (i.character);
		}
	}
	
	public void set_character_info (CharacterInfo i) {
		character_info = i;
	}

	public int get_selected_index () {
		GlyphCollection gc;
		int index = 0;
		
		if (selected_items.size == 0) {
			return 0;
		}
		
		gc = selected_items.get (0);
		
		foreach (OverViewItem i in visible_items) {
			if (i.glyphs != null && gc == ((!) i.glyphs)) {
				break;
			}
			
			index++;
		}
		
		return index;
	}

	public void hide_menu () {
		foreach (OverViewItem i in visible_items) {
			i.hide_menu ();
		}	
	}

	public override void button_press (uint button, double x, double y) {
		OverViewItem i;
		int index = 0;
		int selected_index = -1;
		bool update = false;
		
		if (character_info != null) {
			character_info = null;
			GlyphCanvas.redraw ();
			return;
		}
		
		for (int j = 0; j < visible_items.size; j++) {
			i = visible_items.get (j);
			
			if (i.click (button, x, y)) {
				selected = index;
				selected_item = get_selected_item ();
				
				if (KeyBindings.has_shift ()) {
					if (selected_item.glyphs != null) {
						
						selected_index = selected_items.index_of ((!) selected_item.glyphs);
						if (selected_index == -1) {
							selected_items.add ((!) selected_item.glyphs);
						} else {
							return_if_fail (0 <= selected_index < selected_items.size);
							selected_items.remove_at (selected_index);
							selected = get_selected_index ();
							selected_item = get_selected_item ();
						}
					}
				} else {
					selected_items.clear ();
					if (selected_item.glyphs != null) {
						selected_items.add ((!) selected_item.glyphs);
					}
				}
				
				update = !i.version_menu.menu_visible;
			}
			index++;
		}
	
		if (update) {
			update_item_list ();
		}
		
		// FIXME: update_item_list ();
		GlyphCanvas.redraw ();
	}

	/** Returns true if overview shows the last character. */
	private bool at_bottom () {
		Font f;
		double t = rows * items_per_row + first_visible;
		
		if (all_available) {
			f = BirdFont.get_current_font ();
			return t >= f.length ();
		}
		
		return t >= glyph_range.length ();
	}

	public void set_glyph_range (GlyphRange range) {
		GlyphRange? current = glyph_range;
		string c;
		
		if (current != null) {
			c = glyph_range.get_char (selected);
		}
		
		all_available = false;
		
		glyph_range = range;
		scroll_top ();

		// TODO: scroll down to c
		update_item_list ();
		selected_item = get_selected_item ();

		GlyphCanvas.redraw ();
	}

	public void select_next_glyph () {
		key_right ();
	}
	
	public void open_current_glyph () {
		open_overview_item (selected_item);
	}

	public override void update_scrollbar () {
		Font f;
		double nrows = 0;
		double pos = 0;
		double size;
		double visible_rows;
		
		if (rows == 0) {
			MainWindow.set_scrollbar_size (0);
			MainWindow.set_scrollbar_position (0);
		} else {
			if (all_available) {
				f = BirdFont.get_current_font ();
				nrows = Math.floor ((f.length ()) / rows);
				size = f.length ();
			} else {
				nrows = Math.floor ((glyph_range.length ()) / rows);
				size = glyph_range.length ();
			}
			
			if (nrows <= 0) {
				nrows = 1;
			}
			
			// FIXME: this is not correct
			visible_rows = allocation.height / OverViewItem.height;
			scroll_size = visible_rows / nrows;
			MainWindow.set_scrollbar_size (scroll_size);
			pos = first_visible / (nrows * items_per_row - visible_rows * items_per_row);
			MainWindow.set_scrollbar_position (pos);
		}
	}

	/** Display one entry from the Unicode Character Database. */
	void draw_character_info (Context cr) 
	requires (character_info != null) {
		double x, y, w, h;
		int i;
		string unicode_value, unicode_description;
		string[] column;
		string entry;
		int len = 0;
		int length = 0;
		bool see_also = false;
		WidgetAllocation allocation = MainWindow.get_overview ().allocation;
		string name;
		string[] lines;
		double character_start;
		double character_height;
		
		entry = ((!)character_info).get_entry ();
		lines = entry.split ("\n");
		
		foreach (string line in entry.split ("\n")) {
			len = line.char_count ();
			if (len > length) {
				length = len;
			}
		}
		
		x = allocation.width * 0.1;
		y = allocation.height * 0.1;
		w = allocation.width * 0.9 - x; 
		h = allocation.height * 0.9 - y;
		
		if (w < 8 * length) {
			w = 8 * length;
			x = (allocation.width - w) / 2.0;
		}
		
		if (x < 0) {
			x = 2;
		}
		
		// background	
		cr.save ();
		Theme.color_opacity (cr, "Background 1", 0.98);
		cr.rectangle (x, y, w, h);
		cr.fill ();
		cr.restore ();

		cr.save ();
		Theme.color_opacity (cr, "Foreground 1", 0.98);
		cr.set_line_width (2);
		cr.rectangle (x, y, w, h);
		cr.stroke ();
		cr.restore ();

		// database entry
		
		if (((!)character_info).is_ligature ()) {
			name = ((!)character_info).get_name ();
			draw_info_line (t_("Ligature") + ": " + name, cr, x, y, 0);
		} else {
			i = 0;
			foreach (string line in lines) {
				if (i == 0) {
					column = line.split ("\t");
					return_if_fail (column.length == 2);
					unicode_value = "U+" + column[0];
					unicode_description = column[1];

					draw_info_line (unicode_description, cr, x, y, i);
					i++;

					draw_info_line (unicode_value, cr, x, y, i);
					i++;			
				} else {
					
					if (line.has_prefix ("\t*")) {
						draw_info_line (line.replace ("\t*", "•"), cr, x, y, i);
						i++;					
					} else if (line.has_prefix ("\tx (")) {
						if (!see_also) {
							i++;
							draw_info_line (t_("See also:"), cr, x, y, i);
							i++;
							see_also = true;
						}
						
						draw_info_line (line.replace ("\tx (", "•").replace (")", ""), cr, x, y, i);
						i++;
					} else {
						i++;
					}
				}
			}
			
			character_start = y + 10 + i * UCD_LINE_HEIGHT;
			character_height = h - character_start;
			draw_fallback_character (cr, x, character_start, character_height);
		}
	}
	
	/** Fallback character in UCD info. */
	void draw_fallback_character (Context cr, double x, double y, double height)
	requires (character_info != null) {
		unichar c = ((!)character_info).unicode;
		
		cr.save ();
		Text character = new Text ();
		Theme.text_color (character, "Foreground 1");
		character.set_text ((!) c.to_string ());
		character.set_font_size (height);
		character.draw_at_top (cr, x + 10, y);
		cr.restore ();
	}

	void draw_info_line (string line, Context cr, double x, double y, int row) {
		Text ucd_entry = new Text (line);
		cr.save ();
		Theme.text_color (ucd_entry, "Foreground 1");
		ucd_entry.widget_x = 10 + x;
		ucd_entry.widget_y = 10 + y + row * UCD_LINE_HEIGHT;
		ucd_entry.draw (cr);
		cr.restore ();		
	}
	
	public void paste () {
		GlyphCollection gc = new GlyphCollection ('\0', "");
		GlyphCollection? c;
		Glyph glyph;
		uint32 index;
		int i;
		int skip = 0;
		int s;
		string character_string;
		Gee.ArrayList<GlyphCollection> glyps = new Gee.ArrayList<GlyphCollection> ();
		Font f = BirdFont.get_current_font ();
		OverViewUndoItem undo_item;
		
		copied_glyphs.sort ((a, b) => {
			return (int) ((GlyphCollection) a).get_unicode_character () 
				- (int) ((GlyphCollection) b).get_unicode_character ();
		});

		index = (uint32) first_visible + selected;
		for (i = 0; i < copied_glyphs.size; i++) {
			if (all_available) {
				if (f.length () == 0) {
					c = add_empty_character_to_font (copied_glyphs.get (i).get_unicode_character (),
						copied_glyphs.get (i).is_unassigned (), 
						copied_glyphs.get (i).get_name ());
				} else if (index >= f.length ()) {
					// FIXME: duplicated unicodes?
					c = add_empty_character_to_font (copied_glyphs.get (i).get_unicode_character (),
						copied_glyphs.get (i).is_unassigned (), 
						copied_glyphs.get (i).get_name ());
				} else {
					c = f.get_glyph_collection_indice ((uint32) index);
				}
				
				if (c == null) {
					c = add_empty_character_to_font (copied_glyphs.get (i).get_unicode_character (),
						copied_glyphs.get (i).is_unassigned (),
						copied_glyphs.get (i).get_name ());
				}
				
				return_if_fail (c != null);
				gc = (!) c; 
			} else {			
				if (i != 0) {
					s = (int) copied_glyphs.get (i).get_unicode_character ();
					s -= (int) copied_glyphs.get (i - 1).get_unicode_character ();
					s -= 1;
					skip += s;
				}

				character_string = glyph_range.get_char ((uint32) (index + skip));
				c = f.get_glyph_collection_by_name (character_string);

				if (c == null) {
					gc = add_empty_character_to_font (character_string.get_char (), 
						copied_glyphs.get (i).is_unassigned (),
						copied_glyphs.get (i).get_name ());
				} else {
					gc = (!) c;
				}
			}
			
			glyps.add (gc);
			index++;
		}

		undo_item = new OverViewUndoItem ();
		foreach (GlyphCollection g in glyps) {
			undo_item.glyphs.add (g.copy ());
		}
		store_undo_items (undo_item);

		if (glyps.size != copied_glyphs.size) {
			warning ("glyps.size != copied_glyphs.size");
			return;
		}

		i = 0;
		foreach (GlyphCollection g in glyps) {
			glyph = copied_glyphs.get (i).get_current ().copy ();
			glyph.version_id = (glyph.version_id == -1 || g.length () == 0) ? 1 : g.get_last_id () + 1;
			glyph.unichar_code = g.get_unicode_character ();

			if (!g.is_unassigned ()) {
				glyph.name = (!) glyph.unichar_code.to_string ();
			} else {
				glyph.name = g.get_name ();
			}
			
			g.insert_glyph (glyph, true);
			i++;
		}
		
		f.touch ();
	}
	
	public class OverViewUndoItem {
		public Gee.ArrayList<GlyphCollection> glyphs = new Gee.ArrayList<GlyphCollection> ();
	}
}

}
