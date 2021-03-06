/*
	Copyright (C) 2014 Johan Mattsson

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
using Math;

namespace BirdFont {

public class ZoomBar : Tool {

	public double zoom_level = 1 / 3.0;
	public bool update_zoom = false;
	
	public signal void new_zoom (double zoom_level);
	
	double margin_percent = 0.05;
	
	public ZoomBar () {
		base ();
		
		panel_press_action.connect ((selected, button, tx, ty) => {
			if (y <= ty <= y + h + 4) {
				set_zoom_from_mouse (tx);
				update_zoom = true;
			}
		});

		panel_move_action.connect ((selected, button, tx, ty) => {
			if (update_zoom) {
				set_zoom_from_mouse (tx);
			}
			
			return true;
		});
		
		panel_release_action.connect ((selected, button, tx, ty) => {
			if (update_zoom) {
				DrawingTools.zoom_tool.store_current_view ();
			}
			update_zoom = false;
			
		});
	}
	
	/** Zoom level from 0 to 1. */
	public void set_zoom (double z) {
		zoom_level = z;
	}
	
	void set_zoom_from_mouse (double tx) {
		double margin = w * margin_percent;
		double bar_width = w - margin - x;
		
		tx -= x;
		zoom_level = tx / bar_width;
		
		if (zoom_level > 1) {
			zoom_level = 1;
		}

		if (zoom_level < 0) {
			zoom_level = 0;
		}
		
		set_zoom (zoom_level);
		
		if (!MenuTab.has_suppress_event ()) {
			new_zoom (zoom_level);
		}
		
		FontDisplay.dirty_scrollbar = true;
		redraw ();
	}
	
	public override void draw_tool (Context cr, double px, double py) {
		double margin = w * margin_percent;
		double bar_width = w - margin - x;
		
		// filled
		cr.save ();
		Theme.color (cr, "Button Border 1");
		draw_bar (cr, px, py);
		cr.fill ();
		cr.restore ();
		
		// remove non filled parts
		cr.save ();
		Theme.color (cr, "Default Background");
		cr.rectangle (x + bar_width * zoom_level - px, y - py, w, h);
		cr.fill ();
		cr.restore ();
		
		// border
		cr.save ();
		Theme.color (cr, "Zoom Bar Border");
		cr.set_line_width (0.8);
		draw_bar (cr, px, py);
		cr.stroke ();
		cr.restore ();
	}
	
	void draw_bar (Context cr, double px, double py) {
		double x = this.x - px;
		double y = this.y - py;
		double w = this.w - px;
		double height = h;
		double radius = height / 2;
		double margin = w * margin_percent;
		
		cr.move_to (x + radius, y + height);
		cr.arc (x + radius, y + radius, radius, PI / 2, 3 * (PI / 2));
		cr.line_to (w - margin - radius, y);
		cr.arc (w - margin - radius, y + radius, radius, 3 * (PI / 2), 5 * (PI / 2));
		cr.line_to (x + radius, y + height);
		cr.close_path ();			
	}
}

}
