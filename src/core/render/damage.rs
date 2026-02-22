use crate::util::geometry::Rect;

/// Tracks damage across the entire scene.
#[derive(Debug, Default)]
pub struct SceneDamage {
    pub global_damage: Vec<Rect>,
}

impl SceneDamage {
    pub fn new() -> Self {
        Self {
            global_damage: Vec::new(),
        }
    }

    /// Adds damage from a specific surface, translated to absolute scene coordinates.
    pub fn add_surface_damage(
        &mut self,
        abs_x: i32,
        abs_y: i32,
        abs_scale: f32,
        surface_damage: &[crate::core::surface::damage::DamageRegion],
    ) {
        for region in surface_damage {
            // Translate surface-local damage to absolute screen space
            let scene_rect = Rect {
                x: abs_x + (region.x as f32 * abs_scale) as i32,
                y: abs_y + (region.y as f32 * abs_scale) as i32,
                width: (region.width as f32 * abs_scale) as u32,
                height: (region.height as f32 * abs_scale) as u32,
            };
            self.add_rect(scene_rect);
        }
    }

    pub fn add_rect(&mut self, rect: Rect) {
        // In a more advanced implementation, we would merge overlapping rects
        self.global_damage.push(rect);
    }

    pub fn clear(&mut self) {
        self.global_damage.clear();
    }

    pub fn is_empty(&self) -> bool {
        self.global_damage.is_empty()
    }
}
